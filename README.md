# Claude Code + Discord Bot — tmux-based 2-bot setup

> Discord 봇 (plannerbot + dsbot) 을 tmux 세션으로 띄우고, `/bot` 슬래시 커맨드로 관리. Mac (Darwin).

---

## 현재 상태 (실측 2026-07-01)

| 항목 | 상태 |
|---|---|
| `~/.claude/channels/discord-plannerbot/` | ✅ 봇 state (medium effort) |
| `~/.claude/channels/discord-dsbot/` | ✅ 봇 state (high effort) |
| `.env` (DISCORD_BOT_TOKEN, chmod 600) | ✅ 둘 다 |
| `soul.md` (기획팀장 / 시니어 DS) | ✅ 둘 다 |
| `access.json` groups | ✅ 8 채널 (일반, 주식, project-manage, 지식베이스, 구직, hermes관리, 미팅룸, +1 thread) |
| discord plugin (`claude-plugins-official/discord`) | ✅ enabled in `/tmp/<bot>-settings.json` |
| discord `server.ts` patch (봇-봇 + channel_bots) | ✅ cache + marketplace 둘 다 |
| `.mcp.json` (`bun --install=fallback server.ts`) | ✅ |
| `/tmp/<bot>-claude-wrapper.sh` (script pty wrapper) | ✅ 둘 다 |
| tmux 세션 (`tmux:plannerbot`, `tmux:dsbot`) | ✅ 둘 다 alive |
| Discord gateway ESTABLISHED | ✅ 162.159.x.x (각 봇당 2-4개 TCP) |
| 봇 응답 (DM/스레드/채널 mention) | ✅ 둘 다 |
| `/bot` skill (list/start/stop/restart/status) | ✅ `~/.claude/skills/bot/` |
| `/bot` skill tests | ✅ 20 assertions / 7 tests, exit 0 |
| 부팅 시 자동 시작 | ❌ tmux 세션은 reboot 후 사라짐 → 수동 재시작 필요 |

---

## 🏗 아키텍처 (실제 동작)

```
tmux session: plannerbot  ──┐
tmux session: dsbot       ──┤  (수동: tmux new-session, 또는 launchd-tmux plist)
                            │
                            └─ script -q /dev/null (pty)
                                 └─ claude --channels plugin:discord@claude-plugins-official
                                      --effort medium|high
                                      --settings /tmp/<bot>-settings.json  ← enabledPlugins.discord
                                      └─ bun --install=fallback server.ts
                                           └─ Discord WebSocket gateway
                                           └─ StdioServerTransport (←→ claude)
                                           └─ Reply/Edit/React/Read 도구
```

각 tmux 세션은 독립 프로세스 트리. 한 쪽이 죽어도 다른 쪽 영향 없음.

**tmux launch 가 필요한 이유**: launchd 가 `script -q /dev/null claude ...` 의 stdin 을 즉시 닫아 claude 가 MCP spawn 직전 EOF 수신 → hang. tmux 가 stdin 을 hold 해서 MCP handshake 가 끝까지 진행됨. 자세한 내용: [docs/troubleshooting.md](docs/troubleshooting.md) 의 "claude 가 launchd 에서 멈춤" 섹션.

---

## 📂 파일

**Repo (`claude-code-discord-bot-setup/`):**

```
install.sh                                EFFORT=medium|high bash install.sh <bot>
launchd/
  com.user.tmplbot-tmux-claude.plist      launchd → tmux new-session 래퍼 ({{BOT}}/{{HOME}} 치환)
wrappers/
  bot-claude-wrapper.sh.template          파라미터화된 wrapper ({{BOT}}, {{EFFORT}}, {{DISALLOWED_TOOLS}})
templates/
  soul-plannerbot.md                      기획팀장 persona
  soul-dsbot.md                           시니어 DS persona
  settings.json.template                  effortLevel + enabledPlugins + permissions.deny
  access.json.example                     allowFrom/groups/mentionPatterns 예시
patches/
  server.ts                               discord plugin patch (봇-봇 + channel_bots 주입)
scripts/
  gh-autoswitch-on-start.sh               gh CLI 계정 자동 전환 hook
docs/
  troubleshooting.md                      트러블슈팅 — tmux launch, access.json 채널, enabledPlugins
  harness.md                              다봇 강한 자율 (plannerbot=medium, dsbot=high)
  architecture.md                         아키텍처 상세
  superpowers/{specs,plans}/              기능 design + plan 문서
tests/
  templates/                              settings/wrapper/soul 템플릿 회귀 테스트
  install/                                install.sh 회귀 테스트
  docs/                                   README / harness.md 회귀 테스트
```

**Bot state (`~/.claude/channels/discord-<bot>/`, runtime, git 밖):**

```
.env                  DISCORD_BOT_TOKEN (chmod 600)
soul.md               templates/soul-<bot>.md 에서 복사
access.json           groups, allowFrom, mentionPatterns, ackReaction
```

**Bot 런타임 (`/tmp/`, runtime, git 밖):**

```
/tmp/<bot>-claude-wrapper.sh     script -q /dev/null claude ... wrapper
/tmp/<bot>-settings.json         --settings 플래그가 가리키는 파일
/tmp/<bot>-claude-stdout.log     claude TUI 출력
/tmp/<bot>-claude-stderr.log     claude + bun stderr
```

**`/bot` skill (`~/.claude/skills/bot/`, runtime, git 밖):**

```
SKILL.md               slash command 정의 (Claude Code 가 auto-discover)
bin/bot                bash helper, tmux 세션 관리 + 5-line status
tests/test_bot.sh      20 assertions / 7 tests, bash 직접 실행
```

`~/.local/bin/bot` 에 symlink 되어 있어 PATH 에서 `bot` 직접 호출 가능.

---

## 🛠 관리 명령

**`/bot` skill (권장):**

```bash
bot                       # 봇 목록
bot dsbot status          # 5-line health check
bot dsbot restart         # tmux 세션 재시작
bot dsbot start           # tmux 세션 생성
bot dsbot stop            # tmux 세션 + claude 프로세스 종료
```

**직접 tmux (디버깅용):**

```bash
tmux attach -t dsbot                       # TUI 직접 보기 (detach: Ctrl-B D)
tmux kill-session -t dsbot                 # 종료
tmux new-session -d -s dsbot -c ~/dev/projects/dsbot \
  "/tmp/dsbot-claude-wrapper.sh > /tmp/dsbot-claude-stdout.log 2> /tmp/dsbot-claude-stderr.log"
```

**로그:**

```bash
tail -f /tmp/dsbot-claude-stderr.log
tail -f /tmp/plannerbot-claude-stderr.log
tail -f /tmp/dsbot-claude-stdout.log        # TUI ANSI 포함
```

**Discord 게이트웨이 확인:**

```bash
BUN=$(ps aux | awk '/[b]un.*discord\/0.0.4\/server\.ts/ {print $2}' | head -1)
lsof -nP -p $BUN 2>/dev/null | grep ESTABLISHED
# 예상: 162.159.x.x:443 또는 160.79.x.x:443 ESTABLISHED TCP
```

---

## 🧪 정상 동작 확인

```bash
bot dsbot status
```

출력 예시 (실제 dsbot):

```
dsbot
  tmux:      session 'dsbot' alive
  claude:    7681  --effort high
  bun:       7785
  gateway:   2 ESTABLISHED TCP (162.159.134.234 )
  api:       HTTP 200 in 0.27s
```

5개 신호:

- `tmux:` — tmux 세션 alive 여부
- `claude:` — claude PID + effort
- `bun:` — discord MCP server PID
- `gateway:` — Discord 게이트웨이 ESTABLISHED TCP 수 + 원격 IP
- `api:` — `discord.com/api/v10/users/@me` HTTP status (토큰 검증, 토큰은 echo 안 됨)

---

## 🚀 설치

### `install.sh` (현재 상태 — launchd 기반)

```bash
# clone 후
git clone https://github.com/sh-ai-x/claude-code-discord-bot-setup ~/claude-code-discord-bot-setup
cd ~/claude-code-discord-bot-setup

# 봇 한 개 설치
EFFORT=high bash install.sh dsbot
EFFORT=medium bash install.sh plannerbot
```

`install.sh` 가 자동 처리:
1. 의존성 확인 (bun, node, claude)
2. `~/.claude/channels/discord-<bot>/{soul.md,.env}` 셋업
3. discord plugin cache 에 `patches/server.ts` 복사 + `.mcp.json` 작성
4. `/tmp/<bot>-claude-wrapper.sh` 생성 (wrapper template 에서)
5. `/tmp/<bot>-settings.json` 생성 (settings template 에서)
6. `~/Library/LaunchAgents/com.user.<bot>-claude.plist` 생성 + `launchctl load`

**⚠ install.sh 의 알려진 한계** (수동 보완 필요):

| 한계 | 수동 보완 |
|---|---|
| `settings.json` 에 `enabledPlugins: discord@claude-plugins-official` 누락 → `--channels` 플래그 무시, 봇 online 이지만 메시지 무반응 | `/tmp/<bot>-settings.json` 에 `enabledPlugins` 추가 후 `bot <bot> restart` |
| `access.json` 에 채널 ID 자동 추가 안 됨 → 새 채널에서 봇 무반응 | `~/.claude/channels/discord-<bot>/access.json` groups 에 수동 추가 |
| launchd 직접 wrapper 실행 시 stdin EOF 로 claude hang → tmux 권장 | launchd unload 후 tmux 세션으로 수동 시작 |
| `/bot` skill 자동 설치 안 됨 | 수동: `mkdir -p ~/.claude/skills/bot/{bin,tests}` + SKILL.md/bin/bot/test_bot.sh 복사 |

### 1줄 인스톨러 (미구현 — 1-line URL 미테스트)

```bash
# 이 URL 이 실제 동작하는지 검증 안 됨. install.sh 에 위 한계 있음.
# bash <(curl -fsSL https://raw.githubusercontent.com/sh-ai-x/claude-code-discord-bot-setup/main/install.sh)
```

### `install.sh` 가 안 만드는 것들

- **tmux 세션**: install.sh 는 launchd 만 셋업. tmux 세션은 수동 (`bot <bot> start` 또는 tmux 명령).
- **`/bot` skill**: skill 파일은 `~/.claude/skills/bot/` 에 별도 위치 (이 repo 외부).
- **부팅 시 자동 tmux 시작**: `launchd/com.user.<bot>-tmux-claude.plist` 템플릿은 존재하지만 `{{BOT}}` 치환 + 수동 `launchctl load` 필요. 동작 미검증.

---

## ➕ 새 봇 추가

```bash
EFFORT=high bash install.sh <botname>
```

기존 봇: `plannerbot` (medium, 기획), `dsbot` (high, 시니어 DS). 새 봇 추가 시 `templates/soul-<botname>.md` 가 있으면 사용, 없으면 `templates/soul-plannerbot.md` fallback.

**Discord Developer Portal 사전 준비** (봇마다):

1. New Application → Bot → Reset Token → 토큰 복사
2. Privileged Gateway Intents → **Message Content Intent ON**
3. OAuth2 → URL Generator: scopes `bot` + `applications.commands`, 봇 초대
4. 봇 snowflake ID + 본인 user ID + 채널 ID 수집

`install.sh` 실행 전 `.env` 파일을 직접 만들어야 함 (`echo "DISCORD_BOT_TOKEN=..." > ~/.claude/channels/discord-<bot>/.env; chmod 600`).

---

## 🤖 `/bot` skill

`/bot` 슬래시 커맨드 = `~/.claude/skills/bot/bin/bot` 의 thin wrapper. Claude Code 가 SKILL.md 보고 자동 invoke.

| 명령 | 동작 |
|---|---|
| `/bot` 또는 `bot` | 설치된 봇 목록 |
| `/bot <name>` 또는 `bot <name>` | status (action 생략 시 기본) |
| `/bot <name> start` | tmux 세션 생성 |
| `/bot <name> stop` | tmux 세션 + claude 프로세스 종료 |
| `/bot <name> restart` | stop + start |
| `/bot <name> status` | 5-line health check |

**Discovery**: `bin/bot` 은 `/tmp/*-claude-wrapper.sh` 를 glob 으로 스캔. `install.sh` 가 wrapper 를 만들면 `/bot` 목록에 자동 등장 — 별도 등록 작업 불필요.

**Exit codes:**

| Code | 의미 |
|---|---|
| 0 | success |
| 2 | unknown action |
| 3 | bot not installed (wrapper 없음) |
| 4 | tmux not in PATH |

**테스트:**

```bash
bash ~/.claude/skills/bot/tests/test_bot.sh
# 20 assertions, 7 tests, 모두 PASS (exit 0)
```

---

## 📁 디렉토리 구조 (정확)

```
claude-code-discord-bot-setup/
├── README.md                              본 문서
├── install.sh                             EFFORT=medium|high bash install.sh <bot>
├── launchd/
│   └── com.user.tmplbot-tmux-claude.plist launchd → tmux 래퍼 템플릿
├── wrappers/
│   └── bot-claude-wrapper.sh.template     파라미터 wrapper ({{BOT}}, {{EFFORT}}, …)
├── templates/
│   ├── soul-plannerbot.md
│   ├── soul-dsbot.md
│   ├── settings.json.template             effortLevel + enabledPlugins + permissions.deny
│   └── access.json.example
├── patches/
│   └── server.ts                          discord plugin patch
├── scripts/
│   └── gh-autoswitch-on-start.sh
├── tests/
│   ├── templates/  install/  docs/
├── docs/
│   ├── troubleshooting.md
│   ├── architecture.md
│   ├── harness.md
│   └── superpowers/{specs,plans}/
```

# Runtime (git 밖)
```
~/.claude/channels/discord-<bot>/
~/.claude/skills/bot/                      /bot skill (SKILL.md, bin/bot, tests/test_bot.sh)
/tmp/<bot>-claude-wrapper.sh
/tmp/<bot>-settings.json
/tmp/<bot>-claude-{stdout,stderr}.log
```

---

## 🔍 트러블슈팅

| 증상 | 원인 | 대응 |
|---|---|---|
| 봇 online 이지만 새 채널에 무반응 | access.json `groups` 에 채널 ID 없음 | `~/.claude/channels/discord-<bot>/access.json` groups 에 ID 추가 (자동 reload) |
| 봇 online 이지만 어떤 채널에도 무반응 | `/tmp/<bot>-settings.json` 에 `enabledPlugins: discord@claude-plugins-official` 없음 | settings.json 에 추가 후 `bot <bot> restart` |
| launchd 직접 wrapper 시 claude stdin EOF 로 hang | launchd 가 stdin 즉시 닫음 | tmux 세션으로 시작: `bot <bot> start` |
| `claude mcp list` ✘ 인데 봇 online | MCP health check artifact (무시 가능) | Discord 에서 실제 응답 테스트 |
| 봇-봇 멘션 무반응 | `patches/server.ts` 미적용 | cache + marketplace 에 패치 파일 복사 후 `bot <bot> restart` |
| 같은 토큰으로 다중 bun → 즉시 offline | Discord 가 토큰당 1 gateway 만 허용 | `pkill -9 -f server.ts` 후 단일 인스턴스만 |

자세한 내용: [docs/troubleshooting.md](docs/troubleshooting.md)