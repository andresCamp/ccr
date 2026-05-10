#!/usr/bin/env bash
# ccr installer — copies the launcher binary and SessionStart hook into
# stable user-locations (~/.ccr, ~/.local/bin), patches Claude Code's
# settings.json idempotently, and triggers the AppleScript permission
# prompt in a known context.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
CCR_DIR="${CCR_DIR:-$HOME/.ccr}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
HOOK_DEST="$CCR_DIR/hooks/session-start.sh"
CCR_BIN="$BIN_DIR/ccr"
SETTINGS="$HOME/.claude/settings.json"

red()    { printf "\033[31m%s\033[0m\n" "$1"; }
green()  { printf "\033[32m%s\033[0m\n" "$1"; }
yellow() { printf "\033[33m%s\033[0m\n" "$1"; }
bold()   { printf "\033[1m%s\033[0m\n" "$1"; }

bold "ccr installer"
echo

# ── Preflight checks ──────────────────────────────────────────────────────

if [[ "$(uname -s)" != "Darwin" ]]; then
    red "ccr requires macOS (uses Ghostty AppleScript + window-save-state)."
    exit 1
fi

if ! command -v /usr/bin/jq >/dev/null && ! command -v jq >/dev/null; then
    red "Missing dependency: jq"
    yellow "  Install with: brew install jq"
    exit 1
fi

if ! command -v /usr/bin/osascript >/dev/null; then
    red "Missing /usr/bin/osascript (system tool — should always be present)"
    exit 1
fi

# Python 3.10+ check
PYTHON="${PYTHON:-python3}"
if ! command -v "$PYTHON" >/dev/null; then
    red "Missing dependency: python3"
    yellow "  Install with: brew install python@3.12"
    exit 1
fi
PY_OK=$("$PYTHON" -c 'import sys; print(1 if sys.version_info >= (3,10) else 0)')
if [[ "$PY_OK" != "1" ]]; then
    PY_VER=$("$PYTHON" --version 2>&1)
    red "ccr requires Python 3.10+ (detected: $PY_VER)"
    yellow "  Install with: brew install python@3.12"
    exit 1
fi

if ! ls /Applications/Ghostty.app >/dev/null 2>&1; then
    yellow "Warning: Ghostty.app not found at /Applications/. ccr only works inside Ghostty."
fi

if [[ ! -f "$SETTINGS" ]]; then
    yellow "Note: $SETTINGS not found yet. ccr will register the hook on first install of Claude Code."
fi

# ── Copy binary + hook ────────────────────────────────────────────────────

mkdir -p "$CCR_DIR/hooks" "$BIN_DIR"
chmod 700 "$CCR_DIR"

cp -f "$REPO_ROOT/bin/ccr"                 "$CCR_DIR/bin/ccr" 2>/dev/null || {
    mkdir -p "$CCR_DIR/bin"
    cp -f "$REPO_ROOT/bin/ccr" "$CCR_DIR/bin/ccr"
}
cp -f "$REPO_ROOT/hooks/session-start.sh"  "$HOOK_DEST"
chmod +x "$CCR_DIR/bin/ccr" "$HOOK_DEST"

ln -sf "$CCR_DIR/bin/ccr" "$CCR_BIN"
green "  ✓ Installed bin → $CCR_BIN"
green "  ✓ Installed hook → $HOOK_DEST"

# ── Patch Claude settings.json ────────────────────────────────────────────

if [[ -f "$SETTINGS" ]]; then
    # Idempotently add SessionStart hook entry
    TMP="$(mktemp)"
    if jq --arg cmd "bash $HOOK_DEST" '
        .hooks //= {}
        | .hooks.SessionStart //= []
        | .hooks.SessionStart |= (
            map(select(
                (.hooks // []) | any(.command? == $cmd) | not
            ))
            + [{matcher: ".*", hooks: [{type: "command", command: $cmd, timeout: 5}]}]
          )
    ' "$SETTINGS" > "$TMP"; then
        mv "$TMP" "$SETTINGS"
        green "  ✓ Registered SessionStart hook in $SETTINGS"
    else
        red "  ✗ Failed to patch $SETTINGS — please add the hook manually:"
        cat <<EOF
        "SessionStart": [{
          "matcher": ".*",
          "hooks": [{"type": "command", "command": "bash $HOOK_DEST", "timeout": 5}]
        }]
EOF
        rm -f "$TMP"
        exit 1
    fi
else
    mkdir -p "$(dirname "$SETTINGS")"
    cat > "$SETTINGS" <<EOF
{
  "hooks": {
    "SessionStart": [{
      "matcher": ".*",
      "hooks": [{"type": "command", "command": "bash $HOOK_DEST", "timeout": 5}]
    }]
  }
}
EOF
    green "  ✓ Created $SETTINGS with SessionStart hook"
fi

# ── Trigger AppleScript permission prompt ─────────────────────────────────

echo
bold "Triggering Ghostty Automation permission (one-time grant required)…"
PROBE_OUT=$(/usr/bin/osascript -e '
tell application "Ghostty"
    try
        return id of focused terminal of selected tab of front window as text
    on error e
        return "ERR:" & e
    end try
end tell
' 2>&1 || true)

if [[ "$PROBE_OUT" == ERR:* ]] || [[ -z "$PROBE_OUT" ]]; then
    yellow "  ✗ AppleScript probe failed: $PROBE_OUT"
    yellow "  Open System Settings → Privacy & Security → Automation, and"
    yellow "  ensure your terminal/shell can control Ghostty. Then re-run."
else
    green "  ✓ Ghostty AppleScript responding: surface $PROBE_OUT"
fi

# ── Done ──────────────────────────────────────────────────────────────────

echo
bold "Installed."
cat <<'EOF'

  Try it:
    ccr help            # all commands
    ccr state           # registry + live tab status
    claude              # in any tab → SessionStart hook auto-binds
    ccr                 # resume the session bound to this tab

  After a Ghostty crash:
    Reopen Ghostty (window-save-state restores tabs with same UUIDs)
    ccr restore-all     # dispatches resume to every restored tab in parallel

  Make sure $HOME/.local/bin is on your PATH:
    echo $PATH | tr ':' '\n' | grep -q "$HOME/.local/bin" || \
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

EOF
