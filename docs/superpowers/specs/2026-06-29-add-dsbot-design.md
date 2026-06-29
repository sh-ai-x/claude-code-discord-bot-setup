# Add `dsbot` (Senior Data Scientist) — Design

**Date**: 2026-06-29
**Status**: Approved
**Author**: brainstorming (Claude)

## Goal

Add a second Discord bot — `dsbot`, a senior data scientist generalist — to the existing `plannerbot` infrastructure. The two bots run as independent launchd agents with separate tokens, working dirs, state dirs, and Discord identities, and collaborate via cross-bot mention in shared channels.

## Context

This repo (`claude-code-discord-bot-setup`) currently operates one Discord bot — `plannerbot`, a planning team lead. Its `install.sh` is parameterized by bot name (`bash install.sh <bot>`), but the wrapper, settings, and soul template are hardcoded for `plannerbot`'s "medium effort, autonomous" configuration.

Adding `dsbot` with **high effort** requires parameterizing the wrapper + settings templates, and adding a new `soul-dsbot.md` template that mirrors `soul-plannerbot.md` structure with a senior DS generalist persona.

## Decisions

| Decision | Value | Rationale |
|---|---|---|
| Bot name | `dsbot` | Matches `<role>bot` pattern (`plannerbot`); short, unambiguous |
| Domain | Senior DS generalist | Broad — covers ML, stats, analytics; partners with `plannerbot` on strategy + execution |
| Relationship | Independent bot + cross-bot Discord mention | Two launchd agents; same channels; auto-mention each other via `meta.channel_bots` |
| Effort | `--effort high` | Senior DS analysis benefits from deeper thinking; plannerbot stays at `medium` for speed |
| Autonomy | `--disallowedTools "AskUserQuestion,ExitPlanMode,TodoWrite,NotebookEdit"` | Same as `plannerbot`; dsbot decides, doesn't ask |
| Ack reaction | 📊 | Distinct from plannerbot's 👀 |
| Working dir | `~/dev/projects/dsbot/` | Independent; no shared files with plannerbot |
| State dir | `~/.claude/channels/discord-dsbot/` | Independent token + access.json |
| Senior traits (4) | Statistical rigor, Pragmatic generalism, Code/notebook discipline, Decision framing | All four selected |

## Architecture

```
launchd (PID 1)
  ├─ com.user.plannerbot-claude  (existing, --effort medium)
  └─ com.user.dsbot-claude        (new, --effort high)
       └─ /tmp/dsbot-claude-wrapper.sh (from wrapper.template)
           └─ script -q /dev/null (pty)
               └─ claude --channels plugin:discord@claude-plugins-official
                        --dangerously-skip-permissions
                        --effort high
                        --settings /tmp/dsbot-settings.json
                        --disallowedTools "AskUserQuestion,ExitPlanMode,TodoWrite,NotebookEdit"
                   └─ bun --install=fallback (discord MCP server, shared patch)
                       └─ Discord gateway (websocket, separate token → dsbot#XXXX)
```

**Shared**: `patches/server.ts` (cross-bot mentions + `meta.channel_bots` inject). Discord plugin cache is shared but each bot opens its own WebSocket connection with its own token.

**Differences from `plannerbot`**:

| | plannerbot | dsbot |
|---|---|---|
| Token | plannerbot Discord app | dsbot Discord app |
| State dir | `~/.claude/channels/discord-plannerbot/` | `~/.claude/channels/discord-dsbot/` |
| Working dir | `~/dev/projects/plannerbot/` | `~/dev/projects/dsbot/` |
| Effort | medium | **high** |
| Persona | 기획팀장 (strategy) | senior DS generalist (analysis) |
| Mention pattern | `@plannerbot` | `@dsbot` |
| Ack reaction | 👀 | 📊 |

## Repo Changes

### New files

| Path | Purpose |
|---|---|
| `templates/soul-dsbot.md` | dsbot persona (identity, signature, senior DS traits, cross-bot rules, thread/channel separation) |
| `wrappers/bot-claude-wrapper.sh.template` | Parameterized wrapper. Placeholders: `{{BOT}}`, `{{EFFORT}}`, `{{DISALLOWED_TOOLS}}` |
| `templates/settings.json.template` | Parameterized settings. Placeholders: `{{BOT}}`, `{{EFFORT_LEVEL}}` |

### Modified files

| Path | Change |
|---|---|
| `install.sh` | Add `EFFORT` / `DISALLOWED_TOOLS` env vars; route wrapper + settings through parameterized templates; per-bot soul template selection |
| `README.md` | Add "Adding a new bot" section with `EFFORT=high bash install.sh dsbot` example |
| `docs/harness.md` | Note that dsbot uses `--effort high` (autonomous still) instead of medium |

### Unchanged files

- `patches/server.ts` — already supports cross-bot mentions + `meta.channel_bots` inject. Works for any bot.
- `launchd/com.user.plannerbot-claude.plist` — used as raw template; `install.sh` does `sed` substitution to produce `com.user.dsbot-claude.plist`.
- `templates/access.json.example` — already shows the structure; user copies + edits for dsbot.

## Template Contents

### `wrappers/bot-claude-wrapper.sh.template`

```bash
#!/bin/zsh
# {{BOT}} wrapper — generated from bot-claude-wrapper.sh.template
#   - effort: {{EFFORT}}
#   - autonomous (AskUserQuestion, ExitPlanMode, TodoWrite, NotebookEdit denied)
#   - script -q /dev/null → pty (claude interactive mode)
export PATH="/Users/sanghee/.bun/bin:/Users/sanghee/.nvm/versions/node/v22.20.0/bin:/opt/homebrew/bin:/usr/bin:/bin"
export DISCORD_STATE_DIR="/Users/sanghee/.claude/channels/discord-{{BOT}}"
cd "/Users/sanghee/dev/projects/{{BOT}}"
exec /usr/bin/script -q /dev/null /Users/sanghee/.nvm/versions/node/v22.20.0/bin/claude \
  --channels plugin:discord@claude-plugins-official \
  --dangerously-skip-permissions \
  --effort {{EFFORT}} \
  --settings /tmp/{{BOT}}-settings.json \
  --disallowedTools "{{DISALLOWED_TOOLS}}"
```

### `templates/settings.json.template`

```json
{
  "effortLevel": "{{EFFORT_LEVEL}}",
  "permissions": {
    "deny": [
      "AskUserQuestion",
      "ExitPlanMode"
    ]
  }
}
```

### `templates/soul-dsbot.md` (persona)

The full soul-dsbot.md is large; the key sections:

**Identity**: "I am `dsbot`. Senior data scientist generalist — supporting user's decisions with data, regardless of ML/stats/analytics domain."

**Signature lines** (decision moments only):
- 가설·제안: `📐 가정 — dsbot`
- 검증·결론: `✓ 결론 — dsbot`
- 이상 감지: `⚠️ dsbot 이상 신호 (confounder / leakage / sample issue)`
- 분석 완수: `🏁 분석 완수 — dsbot`

**Senior principles** (4, all selected):
1. **Statistical rigor** — always questions metric, baseline, sample size, confounders. p-value alone is forbidden; effect size + CI required. Causal claims require DAG / identification strategy.
2. **Pragmatic generalism** — pick simplest model that answers. "80% answer with 20% effort". Over-engineering avoided.
3. **Code/notebook discipline** — fixed seeds, pinned env, single-responsibility cells, parameterized pipelines, `data/`, `notebooks/`, `models/`, `reports/` folder separation.
4. **Decision framing** — translates findings into actions. Ends with "what action would we take differently?"

**Cross-bot collaboration** — same rules as `plannerbot`: auto-mention other bots in the same channel/thread via `<@BOT_ID>`; DM exception; mention only when other bots present.

**Thread/channel separation** — same `chat_id` / `message_id` discipline as `plannerbot`.

## `install.sh` Changes (Diff Sketch)

```bash
# New env vars (defaults preserve plannerbot behavior)
EFFORT="${EFFORT:-medium}"
DISALLOWED_TOOLS="${DISALLOWED_TOOLS:-AskUserQuestion,ExitPlanMode,TodoWrite,NotebookEdit}"

# Wrapper: prefer bot-specific, fall back to parameterized template
if [ -f "$(dirname "$0")/wrappers/$BOT-claude-wrapper.sh" ]; then
    cp "$(dirname "$0")/wrappers/$BOT-claude-wrapper.sh" "/tmp/$BOT-claude-wrapper.sh"
else
    sed -e "s|{{BOT}}|$BOT|g" \
        -e "s|{{EFFORT}}|$EFFORT|g" \
        -e "s|{{DISALLOWED_TOOLS}}|$DISALLOWED_TOOLS|g" \
        "$(dirname "$0")/wrappers/bot-claude-wrapper.sh.template" \
      | sed -e "s|/Users/sanghee/dev/projects/plannerbot|$WD_DIR|g" \
            -e "s|/Users/sanghee/.claude/channels/discord-plannerbot|$STATE_DIR|g" \
      > "/tmp/$BOT-claude-wrapper.sh"
fi
chmod +x "/tmp/$BOT-claude-wrapper.sh"

# Settings.json: from template
sed -e "s|{{BOT}}|$BOT|g" \
    -e "s|{{EFFORT_LEVEL}}|$EFFORT|g" \
    "$(dirname "$0")/templates/settings.json.template" > "/tmp/$BOT-settings.json"

# soul.md: pick per-bot template if exists, else plannerbot default
SOUL_TEMPLATE="$(dirname "$0")/templates/soul-$BOT.md"
[ -f "$SOUL_TEMPLATE" ] || SOUL_TEMPLATE="$(dirname "$0")/templates/soul-plannerbot.md"
[ -f "$STATE_DIR/soul.md" ] || cp "$SOUL_TEMPLATE" "$STATE_DIR/soul.md"
```

## User-side Setup

### State dir contents

| File | Source | User action |
|---|---|---|
| `~/.claude/channels/discord-dsbot/.env` | — | **user creates** with `DISCORD_BOT_TOKEN=<dsbot-token>` |
| `~/.claude/channels/discord-dsbot/soul.md` | `templates/soul-dsbot.md` | automatic copy |
| `~/.claude/channels/discord-dsbot/access.json` | `templates/access.json.example` | **user edits**: `allowFrom` (own snowflake), `mentionPatterns` (add `@dsbot` + dsbot ID), `ackReaction: "📊"` |

### access.json example for dsbot

```json
{
  "dmPolicy": "pairing",
  "replyToMode": "all",
  "allowFrom": ["<user_snowflake>"],
  "groups": {
    "<channel_id>": { "requireMention": true, "allowFrom": [] }
  },
  "pending": {},
  "mentionPatterns": [
    "@dsbot",
    "<@<dsbot_bot_id>>",
    "<@!<dsbot_bot_id>>"
  ],
  "ackReaction": "📊"
}
```

### Working dir

`~/dev/projects/dsbot/` is created by `install.sh` as an empty dir. User (separately) drops in:
- `CLAUDE.md` — project-level instructions specific to dsbot's analyses
- Optional subdirs: `data/`, `notebooks/`, `models/`, `reports/`

**Out of scope for this design**: dsbot-specific `CLAUDE.md` content — depends on user's actual data/analyses.

### Discord Developer Portal (one-time, per bot)

1. New Application → name = "dsbot" → Bot tab → Reset Token → copy
2. Privileged Gateway Intents → **Message Content Intent ON**
3. OAuth2 → URL Generator → `bot` + `applications.commands` scopes → invite to server
4. Get bot's snowflake ID (right-click bot in Discord → Copy User ID; needs Developer Mode)
5. Get user's own snowflake ID
6. Get channel IDs (initially the same as `plannerbot`, for cross-bot collaboration)

### Install command

```bash
EFFORT=high bash install.sh dsbot
```

## Verification

```bash
# Step 1: launchd + processes
launchctl list | grep dsbot
# expected: <PID> 0 com.user.dsbot-claude

ps aux | grep -E '[c]laude.*--channels|[b]un.*server\.ts'
# expected: 6 lines (3 for plannerbot, 3 for dsbot) — separate parent chains

# Step 2: Discord gateway
tail -5 /tmp/dsbot-claude-stderr.log
# expected: "discord channel: gateway connected as dsbot#XXXX"

# Step 3: Discord app
# - bot list: dsbot status = 🟢 online
# - DM: "안녕" → pairing code
# - paired: "안녕" → dsbot responds with senior DS persona
# - same channel as plannerbot: "dsbot 의견?" → dsbot responds + mentions @plannerbot
```

## Out of Scope (YAGNI)

- dsbot-specific MCP server overrides (`.mcp.json` per-WD) — global MCPs are sufficient
- dsbot-specific `CLAUDE.md` content — user-driven, project-specific
- Multi-bot coordinator / orchestrator layer — cross-bot mention is sufficient
- Rate limiting / per-bot quotas — Discord handles gateway; no current pain point
- Per-bot access.json template file — user edits example

## Open Questions (resolved during brainstorming)

- ~~Bot name~~ → `dsbot`
- ~~Domain~~ → Generalist (broad DS)
- ~~Relationship to plannerbot~~ → Independent + cross-bot mention
- ~~Senior traits~~ → 4 selected: statistical rigor, pragmatic generalism, code discipline, decision framing
- ~~Effort level~~ → `high` (autonomous)
- ~~Approach~~ → A: parameterized templates
- ~~Ack reaction~~ → 📊
