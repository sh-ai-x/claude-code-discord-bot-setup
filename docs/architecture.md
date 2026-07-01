# Architecture

## Process tree

```
tmux session: <bot>          (manually started; or via launchd tmux plist on boot)
  └─ /usr/bin/script -q /dev/null (pty)
      └─ claude --channels plugin:discord@claude-plugins-official
              └─ bun --install=fallback $PLUGIN/server.ts
                  ├─ discord.js WebSocket → Discord Gateway
                  ├─ StdioServerTransport (MCP stdio ↔ claude)
                  └─ access.json gate (per channel/DM)
```

Each bot runs in its own tmux session. Independent process trees — one dying does not affect the other.

## Message flow

```
Discord user → @mention in registered channel
  → Discord Gateway (WebSocket)
  → discord.js messageCreate
  → server.ts:805  if (msg.author.id === self.id) return  // skip own bot only
  → gate() — requireMention, allowFrom, channel allowlist
  → fetch last 20 msgs → channel_bots auto-injection (meta.channel_bots)
  → mcp notification → claude stdin
  → LLM (uses mcp__plugin_discord_discord__reply)
  → reply → Discord API
```

## Patches (in `patches/server.ts`)

**1. Bot-to-bot mention allow**
```diff
- if (msg.author.bot) return
+ if (msg.author.id === client.user?.id) return
```
Original code blocks all bot-authored messages. Patch only skips self; `gate()` handles the rest.

**2. channel_bots injection**
```ts
const recent = await msg.channel.messages.fetch({ limit: 20 })
const seen = new Set<string>()
for (const m of recent.values()) {
  if (m.author.bot && m.author.id !== client.user?.id) seen.add(m.author.id)
}
// meta: { ..., channel_bots: [...seen].join(',') }
```
Lets the LLM see other bots active in the channel so cross-bot hand-off rules in `soul.md` can fire.

**3. `.mcp.json` launch command**
```diff
- "args": ["run", "--cwd", "${CLAUDE_PLUGIN_ROOT}", "--shell=bun", "--silent", "start"]
+ "args": ["--install=fallback", "${CLAUGIN_ROOT}/server.ts"]
```
`bun run --cwd` does not change cwd (flag is global, not subcommand). Direct absolute path avoids the bug.

## Why tmux, not launchd direct

| | tmux wrapper | launchd direct |
|---|---|---|
| stdin | tmux holds open → MCP handshake completes | launchd closes immediately → claude hangs at MCP spawn |
| attach | `tmux attach -t <bot>` | not possible (detached child of launchd) |
| boot auto-restart | needs launchd tmux plist (`launchd/com.user.<bot>-tmux-claude.plist`) | built into launchd |
| restart command | `bot <name> restart` | `launchctl kickstart -k` |

Recommendation: tmux for the bot itself; launchd only as a tmux-session-creator (the existing tmux plist template).

## access.json shape

```json
{
  "dmPolicy": "pairing",
  "allowFrom": ["<user_snowflake>"],
  "groups": {
    "<channel_id>": { "requireMention": true, "allowFrom": [] }
  },
  "mentionPatterns": ["@<bot>", "<@BOT_ID>", "<@!BOT_ID>"],
  "ackReaction": "👀",
  "replyToMode": "all"
}
```

- `dmPolicy`: `pairing` (default, requires 6-digit code on first DM) | `allowlist` | `disabled`
- `groups`: channel snowflake → config. Threads inherit parent channel policy.
- `requireMention`: true = respond only on @mention; false = respond to all messages
- `replyToMode`: `first` (default) | `all` | `off`

The plugin re-reads `access.json` on every inbound message, so editing it takes effect immediately — no restart.

## Limitations

1. **single token = single instance per bot**: multi-bot needs multiple tokens + multiple plists/wrappers.
2. **cache vs marketplace sync**: discord plugin update can re-overwrite cache, dropping the patch. `cp patches/server.ts $PLUGIN_CACHE/server.ts` to reapply.
3. **no boot-time auto-start yet**: the `launchd/com.user.<bot>-tmux-claude.plist` template exists but must be copied + `{{BOT}}`/`{{HOME}}` substituted + `launchctl load`ed manually per bot.