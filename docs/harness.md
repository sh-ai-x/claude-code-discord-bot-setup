# plannerbot 한정 강한 자율 하네스

`plannerbot` 은 일반 claude 세션과 다르게, Discord 채널에서 다봇 협업 + 빠른 자율 응답이 필요. 이 하네스는 **plannerbot 한정** 으로 적용되며, 사용자 본체 claude 세션에는 영향 없음.

## 적용 위치

`launchd` 가 `com.user.plannerbot-claude` plist 로 띄울 때, wrapper script 가 `claude` 에 **추가 CLI flags** 전달:

```
/bin/zsh /tmp/plannerbot-claude-wrapper.sh
  → script -q /dev/null (pty)
  → claude --channels plugin:discord@claude-plugins-official
           --dangerously-skip-permissions
           --effort medium
           --settings /tmp/plannerbot-settings.json
           --disallowedTools "AskUserQuestion,ExitPlanMode,TodoWrite,NotebookEdit"
```

## 각 flag 가 하는 일

| Flag | 효과 |
|---|---|
| `--channels plugin:discord@claude-plugins-official` | discord MCP server 자동 load |
| `--dangerously-skip-permissions` | 도구 사용 시 permission 묻지 않음 (모든 도구 자동 승인) |
| `--effort medium` | 깊은 사고 줄임 → **빠른 응답** (이전: high = 깊게 생각) |
| `--settings /tmp/plannerbot-settings.json` | `effortLevel: medium` + `permissions.deny` (defense in depth) |
| `--disallowedTools "AskUserQuestion"` | **사용자에게 선택지 안 줌**, 자기가 결정 |
| `--disallowedTools "ExitPlanMode"` | plan mode 진입 못함 |
| `--disallowedTools "TodoWrite"` | todo list 관리 시도 차단 (오버헤드 줄임) |
| `--disallowedTools "NotebookEdit"` | notebook 직접 편집 시도 차단 |

## 두 단계 deny (defense in depth)

1. **CLI flag** (`--disallowedTools`): claude code 가 도구 호출 자체를 거부
2. **settings.json** (`permissions.deny`): claude 가 정책적으로 거부

둘 다 설정해서 한 쪽이 우회되어도 다른 쪽이 차단.

`/tmp/plannerbot-settings.json`:
```json
{
  "effortLevel": "medium",
  "permissions": {
    "deny": [
      "AskUserQuestion",
      "ExitPlanMode"
    ]
  }
}
```

## 사용자 본체 세션과 격리

이 하네스는 **plannerbot launchd wrapper** 안에서만 적용. 사용자 본체 claude 세션 (예: PID 9485) 은 `~/.claude/settings.json` 의 기본 설정 사용:

```json
{
  "effortLevel": "high",   ← plannerbot 은 medium, 본체는 high
  "enabledPlugins": {...}
  ...
}
```

→ **사용자는 본체 세션에서 high effort + AskUserQuestion 사용 가능** (전략적 결정). 봇은 medium + 자발적.

## access.json — 채널 / 봇 응답 정책

`~/.claude/channels/discord-plannerbot/access.json` (예시: `templates/access.json.example`):

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
    "@plannerbot",
    "<@1520719061498204262>",
    "<@!1520719061498204262>"
  ],
  "ackReaction": "👀"
}
```

- `dmPolicy: pairing` — 첫 DM 은 pairing code, 이후 자동 도달
- `requireMention: true` — 스레드/채널에서 `@plannerbot` 멘션 필수
- `mentionPatterns` — 디스플레이명 + raw ID 양쪽 매칭
- `ackReaction: 👀` — 메시지 수신 즉시 👀 이모지 리액션 (도구 사용 시작 신호)

## soul.md 핵심 규율

- 즉시 응답 (ack + typing + chunk 발신)
- 교차 봇 협업 (같은 채널 다른 봇 자동 멘션, `meta.channel_bots` 활용)
- 시그니처 `— plannerbot`
- 페르소나 = 기획팀장

## server.ts 핵심 patch

`patches/server.ts` 적용된 변경:

1. `if (msg.author.bot) return` → `if (msg.author.id === client.user?.id) return`
   → 봇-봇 멘션 허용 (gate() 가 나머지 필터링)

2. `meta.channel_bots` 자동 주입 (최근 20 메시지 fetch → 봇 ID 수집)
   → LLM 이 같은 채널 다른 봇을 자동 인지

3. `.mcp.json` launch command 단순화
   → `bun --install=fallback $PLUGIN_ROOT/server.ts` (절대경로)

## 관리

```bash
# 하네스 변경 후 재시작
launchctl kickstart -k gui/501/com.user.plannerbot-claude

# 설정 파일 검증
cat /tmp/plannerbot-settings.json
cat /tmp/plannerbot-claude-wrapper.sh

# 봇 응답 시간 측정 (Discord 에서 DM 보내고 stopwatch)
```
