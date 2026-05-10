#!/bin/bash
# ccr SessionStart hook — CREATE the binding (surface UUID → session_id).
#
# Runs when the user invokes `claude`. The user's tab is the focused Ghostty
# terminal at this moment. We query AppleScript for `focused terminal of
# selected tab of front window` to get its stable surface UUID. This UUID
# survives Ghostty crash + window-save-state restoration.
#
# Stdin: {session_id, cwd, ...} (Claude Code hook JSON)

set -u

CCR_DIR="${CCR_DIR:-$HOME/.ccr}"
REGISTRY="$CCR_DIR/registry.json"
LOCKFILE="$CCR_DIR/registry.lock"
mkdir -p "$CCR_DIR"
chmod 700 "$CCR_DIR" 2>/dev/null
[ -f "$REGISTRY" ] || { echo '{}' >"$REGISTRY"; chmod 600 "$REGISTRY" 2>/dev/null; }

# Required tools — fail silently if missing (don't break Claude startup)
command -v /usr/bin/jq >/dev/null 2>&1 || exit 0
command -v /usr/bin/osascript >/dev/null 2>&1 || exit 0

INPUT=$(/bin/cat)
SID=$(printf '%s' "$INPUT" | /usr/bin/jq -r '.session_id // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | /usr/bin/jq -r '.cwd // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0
[ -z "$CWD" ] && exit 0

# AppleScript injection guard: pass cwd via env-var, read inside AS via
# `system attribute`. Heredoc is single-quoted so bash does not interpolate.
# This protects against paths containing quotes, backslashes, or other AS
# metacharacters.
UUID=$(CCR_CWD="$CWD" /usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null
tell application "Ghostty"
    set targetCwd to (system attribute "CCR_CWD")
    try
        set t to focused terminal of selected tab of front window
        if (working directory of t as text) is targetCwd then
            return id of t as text
        end if
    end try
    -- Fallback: scan for an unambiguous match by cwd. If multiple terminals
    -- share this cwd, refuse to guess; user can `ccr adopt` later.
    try
        set matches to every terminal whose working directory is targetCwd
        if (count of matches) is 1 then
            return id of (item 1 of matches) as text
        end if
    end try
    return ""
end tell
APPLESCRIPT
)

[ -z "$UUID" ] && exit 0

NOW=$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)

# Atomic, locked registry update
(
    /usr/bin/flock -x 9
    /usr/bin/jq --arg u "$UUID" \
                --arg sid "$SID" \
                --arg cwd "$CWD" \
                --arg ts "$NOW" \
                '.[$u] = {session_id: $sid, cwd: $cwd, started_at: $ts}' \
                "$REGISTRY" >"$REGISTRY.tmp" 2>/dev/null \
        && /bin/mv "$REGISTRY.tmp" "$REGISTRY"
    chmod 600 "$REGISTRY" 2>/dev/null
) 9>"$LOCKFILE"

exit 0
