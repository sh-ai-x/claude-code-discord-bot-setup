# `/bot` Skill — Discord Bot Management — Design

**Date**: 2026-07-01
**Status**: Approved
**Author**: brainstorming (Claude)

## Goal

A Claude Code skill that lets the user list installed Discord bots and start / stop / restart / check status of any one of them, all from the main terminal session. Triggered via slash command `/bot`.

## Context

This repo (`claude-code-discord-bot-setup`) installs bots as launchd agents (`com.user.<bot>-claude` plists in `~/Library/LaunchAgents/`). Each bot has its own state dir (`~/.claude/channels/discord-<bot>/`) with `.env` (token), `soul.md`, `access.json`. Currently there is no first-class CLI for managing them — operators fall back to raw `launchctl` commands, which require knowing the exact plist name pattern.

This skill wraps those `launchctl` invocations + status checks behind a single, discoverable slash command.

## Decisions

| Decision | Value | Rationale |
|---|---|---|
| Invocation | Slash command `/bot <args>` | Matches existing Claude Code conventions (`/discord:access`, etc.) |
| Actions | `start`, `stop`, `restart`, `status` (+ `list` when no args) | Most useful daily ops; restart + status make troubleshooting trivial |
| Discovery | Scan `~/Library/LaunchAgents/com.user.*-claude.plist` | Source of truth = what's installed; new bots appear automatically |
| Location | User-level `~/.claude/skills/bot/` | Available in all sessions, not tied to repo |
| Implementation | Bash helper script + thin SKILL.md | Testable shell logic; also usable as CLI directly |
| Token handling for status | Read from `~/.claude/channels/discord-<bot>/.env`, chmod 600 | Don't echo the token in output |
| Output routing | stdout = data, stderr = errors/warnings | Standard CLI convention; pipeable |

## Architecture

```
~/.claude/skills/bot/
├── SKILL.md         # frontmatter + body — tells Claude to invoke bin/bot
├── bin/
│   └── bot          # bash script: `bot <name> <action>` or `bot list`
└── tests/
    └── test_bot.sh  # unit tests
```

**SKILL.md** is the Claude-side wrapper. It exists so Claude Code can discover and invoke the skill via `/bot`. It contains no logic — just instructions on how to call `bin/bot`.

**bin/bot** is a self-contained bash script that:
1. Accepts `list` (no args) or `<name> <action>`
2. Validates the bot exists by checking its plist
3. Maps action → launchctl / status commands
4. Returns data on stdout, errors on stderr
5. Exits 0 on success, non-zero on error

## Invocation

| Form | Effect |
|---|---|
| `/bot` | lists installed bots (one per line) |
| `/bot <name>` | shows `status` of that bot |
| `/bot <name> start` | loads the plist via launchctl |
| `/bot <name> stop` | unloads the plist via launchctl |
| `/bot <name> restart` | `launchctl kickstart -k` (works whether loaded or not) |
| `/bot <name> status` | full health check (see below) |

## `bin/bot` design

### Action mappings

| Subcommand | Command(s) | Output (stdout) |
|---|---|---|
| `list` | `ls ~/Library/LaunchAgents/com.user.*-claude.plist \| sed 's\|.*com.user.\|\|; s\|-claude.plist\|\|'` | bot names, one per line |
| `<name> start` | `launchctl load ~/Library/LaunchAgents/com.user.<name>-claude.plist` | `✓ <name> started` or `INFO: <name> already running (PID <pid>)` |
| `<name> stop` | `launchctl unload ~/Library/LaunchAgents/com.user.<name>-claude.plist` | `✓ <name> stopped` or `INFO: <name> already stopped` |
| `<name> restart` | `launchctl kickstart -k gui/501/com.user.<name>-claude` | `✓ <name> restarted` |
| `<name> status` | composite (see below) | 6-line block |

### `<name> status` output (6 lines)

```
<name>
  launchd:   <PID>  <exit-code>  (or "not loaded")
  claude:    <PID>  /Users/.../claude --effort <level>  (or "<not running>")
  bun:       <PID>  /Users/.../bun server.ts  (or "<not running>")
  gateway:   <N> ESTABLISHED TCP to Discord  (or "<not running>")
  api:       HTTP <code>  (https://discord.com/api/v10/users/@me)
```

Each line is a real probe — `bin/bot` never lies about a bot's state.

### Token handling for status

```bash
TK=$(grep -E '^DISCORD_BOT_TOKEN=' ~/.claude/channels/discord-<name>/.env | cut -d= -f2-)
curl -sS -o /dev/null -w 'HTTP %{http_code} in %{time_total}s' \
  -H "Authorization: Bot $TK" \
  https://discord.com/api/v10/users/@me
```

Token is **never** echoed in script output. If `.env` is missing or unreadable, the `api:` line shows `<token unreadable>`.

## Error handling

| Case | bin/bot behavior | Exit |
|---|---|---|
| No args | Print usage + list installed bots | 0 |
| `<name>` only | Run `status` on that bot | 0 |
| `<name>` + invalid action | `ERROR: unknown action '<x>' (use: start\|stop\|restart\|status)` | 2 |
| `<name>` + valid action, plist missing | `ERROR: bot '<x>' not installed (no plist at ~/Library/LaunchAgents/com.user.<x>-claude.plist)` | 3 |
| `start` but already loaded | `INFO: <x> already running (PID <pid>)` | 0 |
| `stop` but not loaded | `INFO: <x> already stopped` | 0 |
| launchctl itself errors | Surface launchctl's stderr | launchctl's exit code |
| `.env` unreadable for `status` | `api: <token unreadable>` | 0 (don't fail the whole status) |

All errors → **stderr**. Success → **stdout**. Pipeable.

## Testing (`tests/test_bot.sh`)

Pure-shell tests. Use real commands against real plists already on disk. Each test exits 0 on pass, 1 on fail.

1. `list` — exits 0, output contains `plannerbot` AND `dsbot`
2. `nonexistent_bot status` — exits 3, stderr contains `not installed`
3. `plannerbot invalid_action` — exits 2, stderr contains `unknown action`
4. `plannerbot status` — exits 0, stdout contains `launchd:`, `claude:`, `bun:`, `gateway:`, `api:`
5. `plannerbot start` (when already running) — exits 0, stdout contains `already running`
6. `plannerbot stop` → `plannerbot start` round-trip — both succeed

Test #6 is **destructive** — it actually stops and starts the bot. Gated by `BOT_TEST_DESTRUCTIVE=1` env var; skip by default.

## `SKILL.md` body

```markdown
---
name: bot
description: Manage installed Discord bots — list, start, stop, restart, status. Uses ~/Library/LaunchAgents/com.user.*-claude.plist as source of truth.
---

# /bot — Discord bot management

Invokes `~/.claude/skills/bot/bin/bot` to manage bots installed via `claude-code-discord-bot-setup`.

## Usage

- `/bot` — list installed bots
- `/bot <name>` — status of one bot (PID, gateway, API)
- `/bot <name> start|stop|restart|status` — manage

## Behavior

1. Parse `<name>` and `<action>` from the user's request
2. Run `~/.claude/skills/bot/bin/bot <args>`
3. Display the script's stdout verbatim
4. If the script exits non-zero, surface its stderr and exit code

## Notes

- Bots are discovered by scanning `~/Library/LaunchAgents/com.user.*-claude.plist`. New bots installed via `install.sh` appear automatically.
- `start` / `stop` map to `launchctl load` / `unload`. `restart` maps to `launchctl kickstart -k` (single command, works whether loaded or not).
- `status` checks: launchd PID, claude PID, bun PID, Discord gateway TCP, Discord API ping — five independent signals of bot health.
```

## Out of scope (YAGNI)

- Color output (ANSI escape codes) — plain text is enough; users can pipe through `bat` / `less` for highlighting
- Web dashboard / GUI
- Per-bot config edits (e.g., changing `EFFORT`) — that's `install.sh`'s job
- Log tailing (`/tmp/<bot>-claude-stdout.log`) — could add later, not core to on/off
- Cross-bot orchestration (e.g., "restart all") — `for bot in $(bot list); do bot $bot restart; done` works from the terminal
- Non-launchd bot management — only supports the `claude-code-discord-bot-setup` plist pattern

## Open Questions (resolved)

- ~~Invocation style~~ → Slash command `/bot`
- ~~Actions~~ → start / stop / restart / status (+ `list`)
- ~~Discovery mechanism~~ → Scan LaunchAgents plists
- ~~Skill location~~ → `~/.claude/skills/bot/` (user-level)
- ~~Implementation shape~~ → Bash helper script + thin SKILL.md