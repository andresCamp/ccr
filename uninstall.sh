#!/usr/bin/env bash
# ccr uninstaller — removes the binary, hook, and registry, and unregisters
# the SessionStart hook from Claude Code's settings.json.

set -euo pipefail

CCR_DIR="${CCR_DIR:-$HOME/.ccr}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
HOOK_DEST="$CCR_DIR/hooks/session-start.sh"
CCR_BIN="$BIN_DIR/ccr"
SETTINGS="$HOME/.claude/settings.json"

green()  { printf "\033[32m%s\033[0m\n" "$1"; }
yellow() { printf "\033[33m%s\033[0m\n" "$1"; }

# Unregister hook
if [[ -f "$SETTINGS" ]] && command -v jq >/dev/null; then
    TMP="$(mktemp)"
    if jq --arg cmd "bash $HOOK_DEST" '
        .hooks.SessionStart? |= (
            map(select(
                (.hooks // []) | any(.command? == $cmd) | not
            ))
        )
        | if .hooks.SessionStart == [] then del(.hooks.SessionStart) else . end
        | if .hooks == {} then del(.hooks) else . end
    ' "$SETTINGS" > "$TMP"; then
        mv "$TMP" "$SETTINGS"
        green "  ✓ Unregistered hook from $SETTINGS"
    fi
fi

# Remove binary symlink
[[ -L "$CCR_BIN" ]] && rm -f "$CCR_BIN" && green "  ✓ Removed $CCR_BIN"

# Remove ccr dir (registry, hooks, bin) — ask first
if [[ -d "$CCR_DIR" ]]; then
    yellow "  ? Remove $CCR_DIR (registry of bindings)? [y/N]"
    read -r ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        rm -rf "$CCR_DIR"
        green "  ✓ Removed $CCR_DIR"
    else
        yellow "  · Kept $CCR_DIR (run rm -rf manually to delete)"
    fi
fi

green "Uninstalled."
