# 아키텍처 상세

## 프로세스 트리

```
launchd (PID 1)
  └─ com.user.plannerbot-claude (KeepAlive=true)
      └─ /tmp/plannerbot-claude-wrapper.sh
          └─ /usr/bin/script -q /dev/null (pty 할당)
              └─ claude --channels plugin:discord@claude-plugins-official --dangerously-skip-permissions
                  ├─ SessionStart hook (soul.md inject)
                  ├─ claude mcp list 의 모든 MCP servers
                  │   ├─ context7, notebooklm, kaggle, colab, vault-search, playwright
                  │   └─ discord (plugin auto-launch)
                  │       └─ bun --install=fallback server.ts
                  │           ├─ discord.js WebSocket → Discord Gateway
                  │           ├─ StdioServerTransport (MCP)
                  │           └─ 채널별 access.json gate
                  └─ tmux attach 가능 (현재는 detached)
```

## 메시지 흐름

```
Discord 사용자
  ↓
  메시지 (@plannerbot 또는 채널 등록 봇)
  ↓
Discord Gateway (WebSocket)
  ↓
discord.js client.on('messageCreate')
  ↓
server.ts:805 msg.author.id === self → skip
  ↓
handleInbound → gate() → requireMention, channel 등록 확인
  ↓
  channel_bots 자동 수집 (최근 20 메시지 fetch)
  ↓
mcp.notification({method: 'notifications/claude/channel', params: {content, meta: {..., channel_bots}}})
  ↓
  (claude 의 stdin pipe 로 전달)
  ↓
claude: soul.md 의 cross-bot 규율 + meta.channel_bots 사용
  ↓
  LLM 추론 (use mcp__plugin_discord_discord__reply)
  ↓
  응답 (channel_bots 의 봇 ID 들 자동 멘션)
  ↓
claude 가 reply 도구로 Discord 에 발신
  ↓
server.ts:reply → Discord API
  ↓
Discord 사용자 화면에 봇 응답 표시
```

## patch 설명

### server.ts:805 — 봇-봇 멘션 허용

```diff
- if (msg.author.bot) return
+ if (msg.author.id === client.user?.id) return
```

**Why**: 원래 `if (msg.author.bot)` 는 다른 봇 메시지를 무조건 차단. 봇-봇 협업 불가. 자기 자신만 skip 하도록 변경. gate() 가 나머지 (allowlist, requireMention 등) 처리.

### server.ts:894-905 — channel_bots 자동 주입

```ts
let channelBots: string[] = []
try {
  const recent = await msg.channel.messages.fetch({ limit: 20 })
  const seen = new Set<string>()
  for (const m of recent.values()) {
    if (m.author.bot && m.author.id !== client.user?.id) {
      seen.add(m.author.id)
    }
  }
  channelBots = Array.from(seen)
} catch {}
// ... meta: { ..., channel_bots: channelBots.join(',') }
```

**Why**: LLM 이 같은 채널의 다른 봇을 자동 인지 → cross-bot 멘션 규율 실행. soul.md 의 "교차 봇 협업 규율" 이 이 meta 를 사용.

### .mcp.json — launch command 단순화

```diff
- "args": ["run", "--cwd", "${CLAUDE_PLUGIN_ROOT}", "--shell=bun", "--silent", "start"]
+ "args": ["--install=fallback", "${CLAUDE_PLUGIN_ROOT}/server.ts"]
```

**Why**: `--cwd` 가 `bun run` 의 subcommand flag 가 아니라 global bun flag. 위 위치 잘못 → cwd 안 바뀜 → plannerbot WD 에서 server.ts 못 찾음 → "Module not found" crash. 절대경로 직접 호출로 우회.

## launchd vs tmux

| 구분 | tmux | launchd |
|---|---|---|
| 세션 lifecycle | shell + tmux server 종료 시 정리 | 시스템 부팅 시 시작 + 로그아웃 후에도 유지 |
| 환경 | tty / tmux pty | no tty (pty wrapper 필요) |
| 자동 재시작 | tmux 의 `respawn-window` 옵션 | `<key>KeepAlive</key><true/>` |
| 부팅 후 자동 시작 | tmux 서버 자동 시작 (login 시) | `<key>RunAtLoad</key><true/>` |
| 다중 인스턴스 | 가능 | 단일 (Label 기준) |
| 부하 | 가벼움 | 약간 무거움 (launchd 가 monitering) |
| 권장 | 개발 / 디버깅 | 프로덕션 / 영구 운영 |

## 환경별 launch command

### dev (tmux 안)

```bash
DISCORD_STATE_DIR="$HOME/.claude/channels/discord-plannerbot" \
  /tmp/launch-plannerbot.sh
# 또는 직접
exec claude --channels plugin:discord@claude-plugins-official --dangerously-skip-permissions
```

### prod (launchd)

plist 의 `ProgramArguments`:
```xml
<array>
    <string>/tmp/plannerbot-claude-wrapper.sh</string>
</array>
```

wrapper:
```bash
#!/bin/zsh
exec /usr/bin/script -q /dev/null /Users/sanghee/.nvm/versions/node/v22.20.0/bin/claude \
  --channels plugin:discord@claude-plugins-official \
  --dangerously-skip-permissions
```

**Why `script -q /dev/null`**: claude 가 stdin 으로 부터 prompt 읽을 때 (--print 모드 fallback) 가 아니라 interactive TUI 모드로 동작하게 pty 할당. `-q` quiet, `/dev/null` 으로 output redirect.

## access.json 구조

```json
{
  "dmPolicy": "pairing",
  "allowFrom": ["<user_snowflake>"],
  "groups": {
    "<channel_id>": {
      "requireMention": true,
      "allowFrom": []
    }
  },
  "pending": {},
  "mentionPatterns": ["@plannerbot", "<@BOT_ID>", "<@!BOT_ID>"],
  "ackReaction": "👀",
  "replyToMode": "all",
  "textChunkLimit": 2000,
  "chunkMode": "length"
}
```

- `dmPolicy`: `pairing` (default) | `allowlist` | `disabled`
- `groups`: 키는 channel snowflake. 스레드는 부모 채널 정책 상속
- `requireMention`: true 면 mention 필수, false 면 모든 메시지 처리
- `ackReaction`: 수신 즉시 리액션 이모지 ("" 면 비활성)
- `replyToMode`: `first` (default) | `all` | `off`

## 이 셋업의 한계

1. **cache vs marketplace 동기**: discord plugin update 시 marketplace 가 갱신되어도 cache 는 그대로. patches/server.ts 가 cache 에 patch 되므로 marketplace 만 update 시 cache 와 차이 발생. `cp patches/server.ts $PLUGIN_CACHE/server.ts` 로 재적용.
2. **단일 토큰 = 단일 인스턴스**: 다중 봇 (예: plannerbot + claudebot) 은 각자 다른 토큰 + 다른 launchd plist 필요.
3. **claude 의 stdin pipe 닫힘 시 MCP server death**: KeepAlive 가 즉시 재시작하지만 그 사이 메시지 손실.
