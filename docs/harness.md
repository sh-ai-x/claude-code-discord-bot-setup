# Bot harness

Bots (`plannerbot`, `dsbot`) get a tighter harness than the user's main session — fast autonomous Discord replies, no permission prompts, no plan mode, narrow tool set.

## What the wrapper passes to claude

```
script -q /dev/null                                  # pty so claude stays in interactive TUI mode
  claude
    --channels plugin:discord@claude-plugins-official
    --dangerously-skip-permissions
    --effort <level>
    --settings /tmp/<bot>-settings.json
    --disallowedTools "AskUserQuestion,ExitPlanMode,TodoWrite,NotebookEdit"
```

| Flag | Effect |
|---|---|
| `--channels …discord@…` | load discord MCP server (also requires `enabledPlugins` in settings.json) |
| `--dangerously-skip-permissions` | auto-approve all tool use (no permission prompts) |
| `--effort <level>` | depth of reasoning (see per-bot table) |
| `--settings /tmp/<bot>-settings.json` | `effortLevel` + `enabledPlugins` + `permissions.deny` |
| `--disallowedTools "AskUserQuestion"` | no user-facing choices; bot decides |
| `--disallowedTools "ExitPlanMode"` | no plan mode |
| `--disallowedTools "TodoWrite"` | no todo overhead |
| `--disallowedTools "NotebookEdit"` | no direct notebook edits |

## Per-bot effort

| Bot | effort | Rationale |
|---|---|---|
| `plannerbot` | medium | fast tactical replies; strategy stays in user's high-effort session |
| `dsbot` | high | statistical rigor needs deeper reasoning |

Set via `EFFORT` env var on `install.sh`:

```bash
EFFORT=high bash install.sh dsbot
EFFORT=medium bash install.sh plannerbot
```

`EFFORT` is injected into both the CLI flag and `settings.json` `effortLevel` — they cannot drift apart.

## Defense in depth

Two layers block the same tools — `--disallowedTools` (CLI-side) and `permissions.deny` (settings-side). Either layer alone would suffice; both means a bypass needs to defeat two checks.

## Isolation from main session

The harness applies only inside the wrapper — the user's main session uses `~/.claude/settings.json` (high effort + full tool set). Bots run a constrained profile; the user keeps the open profile.

## access.json shape (per bot)

See `templates/access.json.example`. Key fields:

- `dmPolicy`: `pairing` (default — 6-digit code on first DM) | `allowlist` | `disabled`
- `groups[<channel_id>].requireMention`: true = only respond on `@<bot>` mention
- `mentionPatterns`: display name + raw snowflake ID, both forms
- `ackReaction`: emoji added immediately on receipt (`""` disables)

Plugin re-reads `access.json` per inbound message — no restart needed to add a channel.

## Restart after harness change

```bash
bot <name> restart
```

## Verify settings

```bash
cat /tmp/<bot>-settings.json
cat /tmp/<bot>-claude-wrapper.sh
```