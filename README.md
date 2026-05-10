# ccr — Claude Code Resume

Each Ghostty tab remembers its Claude Code session. After a crash, every tab auto-resumes its exact previous conversation.

```
$ ccr restore-all
  ✓ 6E4B5E8D… → 04098887…  /Users/me/onc9-systems
  ✓ 2E99AE11… → 2ba800e1…  /Users/me/onc9-systems
  ✓ ABCB70F0… → e7c1b559…  /Users/me/Projects/osis
  ...
ccr: dispatched 50 resume command(s)
```

## The problem

If you run many parallel Claude Code sessions in Ghostty (one per task / branch / idea), a Ghostty crash leaves you with restored tabs but no memory of which session was in which tab. Title-based recovery doesn't work because Claude Code overwrites the title on every spinner tick. cwd-based recovery doesn't work when you have 20 sessions in the same project directory.

## The trick

Ghostty assigns every terminal surface a stable UUID that survives `window-save-state` (verified in [`SurfaceView_AppKit.swift`][surface-view] — the UUID round-trips through `Codable`/`NSCoder`). That UUID is queryable via Ghostty's [AppleScript API][applescript].

ccr binds `surface_uuid → claude_session_id` in a small registry on disk. When Ghostty restores tabs, the UUIDs come back unchanged — ccr looks each one up and dispatches `claude --resume <id>` into the matching tab via AppleScript.

[surface-view]: https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Ghostty/Surface%20View/SurfaceView_AppKit.swift
[applescript]: https://ghostty.org/docs/features/applescript

## Architecture

```
                 user runs `claude` in a Ghostty tab
                              │
                              ▼
              ┌───────────── SessionStart hook ──────────────┐
              │  AppleScripts Ghostty for the focused tab's  │
              │  surface UUID, writes binding:               │
              │   ~/.ccr/registry.json                       │
              │   { "<surface_uuid>": {                      │
              │       "session_id": "<uuid>",                │
              │       "cwd": "/path",                        │
              │       "started_at": "..." }}                 │
              └──────────────────────────────────────────────┘
                              │
              ── time passes, Ghostty crashes ──
                              │
                              ▼
              ┌──────── window-save-state restore ───────────┐
              │   tabs come back with the same surface       │
              │   UUIDs (Ghostty preserves them through      │
              │   NSCoder secure-coding)                     │
              └──────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────── ccr restore-all ────────────────┐
              │   single AppleScript loops over registry,    │
              │   types `claude --resume <id>` into each     │
              │   live tab whose UUID matches                │
              └──────────────────────────────────────────────┘
```

## CRUD lifecycle

| Operation | Trigger |
|---|---|
| **C**reate | `claude` start fires SessionStart hook → writes binding |
| **R**ead   | `ccr`, `ccr ls`, `ccr state`, `ccr pick`, `ccr restore-all` |
| **U**pdate | `ccr adopt` (retroactively bind), or running `claude` again in same tab overwrites |
| **D**elete | Automatic on **tab close** (lazy: at every mutating ccr command). Plus `ccr unbind` (this tab) and `ccr clear` (stale JSONL bindings). Bindings persist when Claude exits but the tab stays open — type `ccr` to resume. |

## Install

```bash
git clone https://github.com/andresCamp/ccr.git
cd ccr
./install.sh
```

The installer:
1. Copies `bin/ccr` to `~/.ccr/bin/ccr` and symlinks `~/.local/bin/ccr`
2. Copies `hooks/session-start.sh` to `~/.ccr/hooks/`
3. Idempotently registers the SessionStart hook in `~/.claude/settings.json`
4. Triggers Ghostty's Automation permission prompt (you'll need to grant it once)

Make sure `~/.local/bin` is on your `PATH`.

## Commands

```
ccr                  resume the session bound to this tab
ccr help             list all commands
ccr state            full registry + Ghostty live-state table
ccr ls               compact list of bindings
ccr ls .             bindings for current cwd only
ccr pick             fzf picker over sessions in current cwd
ccr adopt            bind current tab → most recent session in cwd
ccr restore-all      bulk recovery: resume all bound sessions in their tabs
ccr <uuid|prefix>    resume a specific session id (must be unambiguous)
ccr unbind           remove this tab's binding
ccr clear            remove bindings whose session JSONL has been deleted
ccr --version
```

## Recovery flow

1. Ghostty crashes / you force-quit.
2. Reopen Ghostty — `window-save-state` restores your tabs with the same surface UUIDs (cwds intact, shells fresh).
3. From any tab: `ccr restore-all`.
4. Every tab whose UUID is in the registry receives `claude --resume <id>` typed into it. They all spin up in parallel, in their original positions.

## Requirements

| | |
|---|---|
| OS | macOS (Ghostty's `window-save-state` and AppleScript are macOS-only currently) |
| Ghostty | 1.3.0+ (AppleScript object model added in 1.3) |
| Python | 3.10+ |
| `jq` | required (`brew install jq`) |
| `fzf` | optional, for `ccr pick` (`brew install fzf`) |
| Claude Code | any recent version |

## Caveats

- **macOS only.** Ghostty's window-save-state restoration is macOS-specific. Linux support depends on Ghostty's roadmap.
- **AppleScript permission required.** First use prompts. Cached after grant.
- **tmux nested inside Ghostty.** Auto-binding doesn't work because the surface's reported cwd is tmux's launch dir, not the pane's. Use `ccr adopt` manually.
- **Splits.** `focused terminal of selected tab of front window` returns the focused split — correct in current Ghostty.
- **Race conditions.** Concurrent `claude` invocations are serialized via `flock` on `~/.ccr/registry.lock`, so bindings can't be lost.

## Uninstall

```bash
./uninstall.sh
```

Removes the binary symlink, unregisters the hook from settings.json, and (with confirmation) removes `~/.ccr/`.

## Why "ccr"

Claude Code Resume. Three letters, one keystroke per character, no shift.

## License

MIT — see [LICENSE](./LICENSE).
