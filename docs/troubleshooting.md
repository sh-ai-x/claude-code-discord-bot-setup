# 트러블슈팅

## 봇이 offline 으로 보임

1. `launchctl list | grep planner` — plist status 확인
2. `tail -20 /tmp/plannerbot-claude-stderr.log` — claude / bun 에러
3. `ps aux | grep -E '[c]laude.*--channels|[b]un.*server'` — 프로세스 트리

## stdin EOF → 즉시 종료

`server.ts:725-735` 의 shutdown handler 가 stdin EOF 시 `discord channel: shutting down` 출력 후 2초 후 종료. launchd 환경에서 stdin 이 /dev/null 이면 즉시 EOF.

**해결**: `script -q /dev/null` 로 pty 할당 (launchd plist 의 wrapper).

## claude 가 launchd 에서 즉시 종료

`Error: Input must be provided either through stdin or as a prompt argument when using --print` — pty 없이 stdin 이 pipe 이면 --print 모드 fallback.

**해결**: `script` 또는 `expect` 로 pty 할당.

## 같은 토큰으로 다중 bun process → 즉시 disconnect

Discord 는 토큰당 1 gateway connection 허용. 2개 동시 연결 시 즉시 kick.

**해결**: `pkill -9 -f 'server.ts'` 후 단일 인스턴스만 띄우기.

## 봇은 online 인데 메시지 무반응

1. **Message Content Intent OFF**: Developer Portal → Bot → Privileged Gateway Intents → ON
2. **access.json requireMention**: 채널 등록 안 됐거나 allowFrom 비어있음
3. **MCP handshake fail**: `claude mcp list` 가 ✘ 인 경우 — launchd 환경에서 pty 문제. wrapper 확인.

## 봇-봇 멘션 무반응

`patches/server.ts` 의 `if (msg.author.id === client.user?.id) return` (line 805) 가 적용됐는지 확인. 옛 `if (msg.author.bot) return` 이 남아있으면 봇-봇 멘션 무조건 차단.

## tmux 환경에서 세션이 죽음

Bash tool sandbox 안에서 `tmux new-session -d` 로 띄운 세션이 Bash 명령 종료 시 정리됨. → launchd + pty wrapper 사용 권장.

## bot.log 에 DeprecationWarning

`discord.js` v15 에서 `ready` 이벤트가 `clientReady` 로 변경 예정. 무시 가능. server.ts 가 아직 `ready` 사용 중.

## bun server.ts 가 즉시 종료 (gateway 연결 전)

`bun --install=fallback /path/to/server.ts` 단독 실행 시 stdin 이 /dev/null 또는 closed pipe 면 EOF 즉시 → shutdown. 테스트용으로 keep-alive stdin 필요시:

```bash
# FIFO 로 stdin hold
mkfifo /tmp/test-fifo
exec 9<>/tmp/test-fifo
bun --install=fallback /path/to/server.ts <&9
```

## `claude mcp list` ✘ 인데 봇 online

MCP health check artifact 일 뿐 Discord 게이트웨이 연결과 무관. Discord 에서 실제 응답 테스트로 확인.

## Discord rate limit

같은 토큰으로 다수 reconnect 시도 시 일시 차단. 5-10분 cooldown 후 자연 회복.

## launchctl unload 안 됨

```bash
# PID 직접 kill
launchctl print system | grep planner   # 실제 PID 확인
sudo launchctl kill TERM <pid>
```

또는 `~/Library/LaunchAgents/com.user.plannerbot-*.plist` 삭제 후 reboot.

## claude 가 launchd 에서 멈춤 (MCP 서버 미스폰)

증상: `launchctl list | grep -E 'planner|dsbot'` PID + exit code 0 인데 `ps` 에서 봇 claude 자식 프로세스가 없음. stdout 에 `^D` 만 반복.

원인: launchd 가 `script -q /dev/null claude ...` 의 stdin 을 즉시 닫아 claude 가 pty 모드 진입 전에 EOF 수신 → MCP 서버(bun) spawn 안 함.

**해결 (권장)**: tmux 세션으로 직접 실행 — launchd 의 stdin 처리를 우회.

```bash
# 봇 1개 시작
tmux new-session -d -s <bot> -c ~/dev/projects/<bot> \
  "/tmp/<bot>-claude-wrapper.sh > /tmp/<bot>-claude-stdout.log 2> /tmp/<bot>-claude-stderr.log"

# 상태 확인
tmux list-sessions       # dsbot, plannerbot
ps aux | grep '[c]laude.*--effort' | head
ps aux | grep '[b]un.*discord/0.0.4' | head
```

장점: pty 안정, MCP 정상 spawn, 5초 안에 Discord 게이트웨이 ESTABLISHED.
단점: reboot 시 tmux 세션 살아남지 않음 → 부팅 후 위 명령 재실행 필요. (자동 재시작 launchd job 추가 가능 — `templates/launchd-tmux-bot.plist` 참조.)

## 새 채널 추가 시 봇이 무반응

`access.json` 의 `groups` 에 채널 ID 가 없으면 discord plugin 의 `gate()` 가 메시지를 폐기 → claude 가 수신 못함.

증상: 봇은 online 인데 특정 채널/스레드 mention 에 응답 없음. `← discord · ...` 줄이 claude TUI 에 안 뜸.

**해결**: `~/.claude/channels/discord-<bot>/access.json` 의 `groups` 에 채널 ID 추가. discord plugin 은 다음 메시지마다 자동 reload 하므로 재시작 불필요.

```json
"groups": {
  "<기존 채널들>": { "requireMention": true, "allowFrom": [] },
  "<새_채널_ID>": { "requireMention": true, "allowFrom": [] }
}
```

채널 ID 확인: Discord 클라이언트 우클릭 → "채널 ID 복사" (개발자 모드 ON 필요).

## settings.json 에 enabledPlugins 누락

증상: `launchctl list` OK + 프로세스 살아있음 + TCP 도 살아있지만 봇이 어떤 메시지에도 반응 없음. `--channels plugin:discord@claude-plugins-official` 플래그가 무시됨.

원인: claude 는 `--channels` 플래그 + settings.json 의 `enabledPlugins` 가 둘 다 있어야 플러그인을 로드함.

**해결**: `/tmp/<bot>-settings.json` 에 다음 추가:

```json
{
  "effortLevel": "medium",
  "enabledPlugins": { "discord@claude-plugins-official": true },
  "permissions": { "deny": ["AskUserQuestion", "ExitPlanMode"] }
}
```

`effortLevel` 은 `medium` (plannerbot) / `high` (dsbot).
