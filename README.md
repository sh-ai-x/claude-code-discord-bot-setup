# Claude Code + Discord Bot — Autonomous Setup (plannerbot + dsbot)

> **Mac (Darwin) + launchd 기반 영구 봇 운영 가이드**.
> 1줄 명령으로 부팅 시 자동 시작 + crash 자동 재시작 + 다봇 협업 (`@plannerbot` / `@dsbot` 멘션 + 봇-봇 핸드오프).

---

## 📋 결과 요약

| 항목 | 상태 |
|---|---|
| `~/.claude/channels/discord-plannerbot/` (700) | ✅ 봇 디렉토리 (medium effort) |
| `~/.claude/channels/discord-dsbot/` (700) | ✅ 봇 디렉토리 (high effort, 시니어 DS) |
| `.env` (chmod 600, `DISCORD_BOT_TOKEN`) | ✅ 둘 다 |
| `soul.md` (기획팀장 / 시니어 DS) | ✅ 둘 다 |
| `access.json` (7 채널 등록) | ✅ 둘 다 (dsbot ackReaction=📊) |
| discord plugin (`claude-plugins-official/discord`) | ✅ enabled |
| cache + marketplace `server.ts` patch | ✅ 봇-봇 멘션 + `channel_bots` 자동 주입 |
| `.mcp.json` launch command fix | ✅ `bun --install=fallback server.ts` |
| launchd plist (`com.user.<bot>-claude`) | ✅ RunAtLoad + KeepAlive, 봇별 |
| `script` pty wrapper | ✅ claude interactive 모드 |
| 봇 online + DM/스레드/봇-봇 멘션 응답 | ✅ 둘 다 |
| `/bot` skill (list/start/stop/restart/status) | ✅ `~/.claude/skills/bot/` |

---

## 🏗 아키텍처

```
launchd (PID 1)
  └─ com.user.plannerbot-claude (auto-restart)
      └─ script -q /dev/null (pty 할당)
          └─ claude --channels plugin:discord@claude-plugins-official --dangerously-skip-permissions
              └─ bun --install=fallback (discord MCP server)
                  ├─ Discord gateway (websocket)
                  ├─ StdioServerTransport (←→ claude)
                  └─ Reply/Edit/React 도구
```

**핵심 문제와 해결**:

1. **`.mcp.json` launch command 버그**: `bun run --cwd DIR ...` 의 `--cwd` 가 `bun run` 서브커맨드 플래그 아니라 global bun 플래그 → cwd 가 안 바뀌고 plannerbot WD 에서 `bun server.ts` 실행 → "Module not found" crash.
   → 수정: `args: ["--install=fallback", "${CLAUDE_PLUGIN_ROOT}/server.ts"]` (직접 server.ts 절대경로)

2. **stdin 즉시 EOF → server.ts `process.stdin.on('end')` → shutdown()**: launchd 또는 detached 환경에서 stdin 이 즉시 닫혀서 30초 후 봇 death.
   → 해결: `script -q /dev/null` 로 pty 할당 (launchd 환경)

3. **claude 가 launchd 에서 `--print` 모드 fallback** (pty 없음 → stdin required → 즉시 종료).
   → 해결: `script` 가 pty 만들어서 interactive 모드 유지

4. **봇-봇 멘션 무반응**: `server.ts:806` `if (msg.author.bot) return` 이 다른 봇 메시지를 무조건 차단.
   → 패치: `if (msg.author.id === client.user?.id) return` (자기 자신만 skip, gate() 가 나머지 필터링)

5. **Cross-bot 협업 가시성 부족**: 봇이 같은 채널의 다른 봇을 자동 멘션하지 않음.
   → `soul.md` 에 규율 + `server.ts` 에 `meta.channel_bots` 자동 주입 (최근 20 메시지 fetch → 봇 ID 수집)

---

## 🎯 현재 셋업 실행 흐름 (plannerbot 기준)

**Mac 부팅 → 봇 online 까지 자동**:
1. macOS 부팅
2. `launchd` 가 `~/Library/LaunchAgents/com.user.plannerbot-claude.plist` 의 `RunAtLoad=true` 로 자동 load
3. plist 가 `/tmp/plannerbot-claude-wrapper.sh` 실행
4. wrapper 의 `script -q /dev/null claude ...` 가 **pty 할당** + claude 를 interactive TUI 모드로 실행
5. claude 가 `--channels plugin:discord@claude-plugins-official` 플래그를 보고 discord plugin 자동 로드
6. plugin 의 `.mcp.json` (`bun --install=fallback server.ts`) 가 discord MCP server spawn
7. bun server.ts 가 Discord gateway 에 WebSocket 연결 (online 점 ✅)
8. Discord 메시지 → bun → claude stdio pipe → LLM 추론 → 응답

**핵심: 사용자가 따로 실행할 필요 없음**. 부팅 시 자동, crash 시 자동 재시작 (KeepAlive=true).

### 📂 관련 파일 경로

| 파일 | 경로 | 역할 |
|---|---|---|
| launchd plist | `~/Library/LaunchAgents/com.user.plannerbot-claude.plist` | launchd 가 읽는 설정. `RunAtLoad`, `KeepAlive`, `ProgramArguments` |
| claude wrapper | `/tmp/plannerbot-claude-wrapper.sh` | `script -q /dev/null claude ...` — pty 할당 + env export |
| discord MCP | `$HOME/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/` | bun 이 실행하는 server.ts + node_modules |
| 봇 state | `~/.claude/channels/discord-plannerbot/` | `.env`, `soul.md`, `access.json` |
| Working Directory | `~/dev/projects/plannerbot/` | claude 가 실행되는 WD (`CLAUDE.md` 자동 로드) |
| claude stderr log | `/tmp/plannerbot-claude-stderr.log` | claude + bun 의 stderr 출력 |
| claude stdout log | `/tmp/plannerbot-claude-stdout.log` | claude TUI 출력 |

#

## 🎚 하네스 (다봇 강한 자율)

[docs/harness.md](docs/harness.md) — `EFFORT` env var 로 봇별 effort 분리 (plannerbot=medium, dsbot=high). 사용자 본체 세션은 high effort + 자유.

## 🛠 관리 명령 (전체)

```bash
# ─── 상태 확인 ───
launchctl list | grep -E 'planner|dsbot'  # 모든 봇 plist status (PID + exit code)
ps aux | grep -E '[c]laude.*--channels'   # 모든 봇 프로세스 트리
tail -f /tmp/plannerbot-claude-stderr.log  # plannerbot stderr 실시간
tail -f /tmp/dsbot-claude-stderr.log       # dsbot stderr 실시간

# ─── 시작 / 중지 / 재시작 (plannerbot 예시; dsbot 도 동일 패턴) ───
launchctl load ~/Library/LaunchAgents/com.user.plannerbot-claude.plist    # 시작
launchctl unload ~/Library/LaunchAgents/com.user.plannerbot-claude.plist  # 중지
launchctl kickstart -k gui/501/com.user.plannerbot-claude                # 강제 재시작

# ─── attach (TUI 직접 조작) ───
# launchd 가 띄운 claude 는 tmux 세션이 아니라 detached process.
# TUI 에 attach 하려면 별도 tmux 안에서 claude 를 직접 띄워야 함:
tmux new-session -d -s plannerbot-debug -c ~/dev/projects/plannerbot \
  "/tmp/plannerbot-claude-wrapper.sh"
tmux attach -t plannerbot-debug
# → 이건 debug 용. main bot 은 launchd 가 관리.
# 같은 패턴으로 dsbot 도 attach 가능 (tmux session 이름만 다르게).

# ─── 페어링 (첫 DM) ───
# 1) Discord 앱에서 봇에 DM "안녕" → 봇이 6자리 pairing code 응답
# 2) 본체 claude 세션 (현재 작업중인 세션) 에서:
/discord:access pair <코드>
# 3) access.json 에 sender ID 자동 추가, 이후 DM 자동 도달

# ─── 완전 제거 (cleanup, plannerbot 예시) ───
launchctl unload ~/Library/LaunchAgents/com.user.plannerbot-claude.plist
rm ~/Library/LaunchAgents/com.user.plannerbot-claude.plist
rm -rf ~/.claude/channels/discord-plannerbot
rm -rf /tmp/plannerbot-*
# discord plugin 은 /plugin uninstall discord@claude-plugins-official
```

> **Tip**: 위 명령들을 매번 치기 귀찮으면 `/bot` 슬래시 커맨드를 쓰세요. 아래 섹션 참고.

### 🧪 정상 동작 확인 (3 단계)

**한 줄로 모든 봇 상태 확인** (위 `/bot` skill 섹션 참고):

```bash
bot              # 또는 /bot
bot plannerbot   # 또는 /bot plannerbot
bot dsbot        # 또는 /bot dsbot
```

**수동 확인 (launchctl 직접):**

**Step 1: launchd + 프로세스**
```bash
launchctl list | grep -E 'planner|dsbot'
# 예상: 두 줄 (plannerbot, dsbot) — 각 줄에 PID + exit code 0

ps aux | grep -E '[c]laude.*--channels'
# 예상: 두 claude 프로세스 — plannerbot (medium), dsbot (high)
```

**Step 2: Discord 게이트웨이**
```bash
lsof -nP -p <plannerbot-claude-pid> 2>/dev/null | grep ESTABLISHED
# 예상: ESTABLISHED TCP to Discord gateway IPs (160.79.x.x 또는 162.159.x.x)
```

> 참고: stderr 에 "gateway connected" 메시지가 안 떠도 정상 — 현재 discord plugin 버전에서는 stdout/TUI 로만 표시됨.

**Step 3: Discord 앱**
- 봇 목록에서 `plannerbot`, `dsbot` 상태 점 = 🟢 online
- DM → `안녕` → 봇 응답 (페어링 코드 또는 첫 인사)
- 채널/스레드 → `@plannerbot 메시지` → 봇 응답
- 같은 채널 → `@dsbot 의견?` → dsbot 응답 + `@plannerbot` 자동 멘션

### ⚠️ 운영 시 주의사항

1. **discord plugin update 시 cache 도 patch 갱신 필요**:
   ```bash
   cp patches/server.ts ~/.claude/plugins/cache/claude-plugins-official/discord/0.0.4/server.ts
   cp patches/server.ts ~/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/discord/server.ts
   launchctl kickstart -k gui/501/com.user.plannerbot-claude  # 재시작
   ```

2. **soul.md 수정 시 SessionStart hook 가 자동 inject** (다음 메시지부터). launchd 재시작 불필요.

3. **access.json 수정 시 server 가 자동 reload** (다음 메시지마다). 즉 Discord 에서 `/discord:access allow 1234` 같은 명령 즉시 반영.

4. **launchd 가 PID 를 잃은 경우 (강제 종료 후)**:
   ```bash
   # PID -1 (실패) / 빈 PID → crash. KeepAlive 가 자동 재시작하지만
   # 10회 연속 실패 시 ThrottleInterval 로 backoff. 직접 kickstart:
   launchctl kickstart -k gui/501/com.user.plannerbot-claude
   ```

5. **claude 의 stdin pipe 가 닫히면 server.ts 가 shutdown → bun death → launchd 재시작**. 이 사이 1-2 초 메시지 손실. KeepAlive 로 자동 복구되지만 자주 발생하면 봇이 자주 깜빡임. → FIFO + script pty 로 stdin keep-alive.

---

## 🚀 설치 (1줄)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sh-ai-x/claude-code-discord-bot-setup/main/install.sh)
```

또는 수동:
```bash
git clone https://github.com/sh-ai-x/claude-code-discord-bot-setup.git ~/claude-code-discord-bot-setup
cd ~/claude-code-discord-bot-setup
bash install.sh
```

`install.sh` 가 자동 처리:
1. 의존성 확인 (bun, node, claude, jq)
2. Discord Developer Portal 안내 (token 발급)
3. `~/.claude/channels/discord-<botname>/` 셋업
4. discord plugin install
5. server.ts patch (cache + marketplace)
6. launchd plist 생성 + load
7. 첫 페어링 안내

---

## ➕ Adding a new bot

This repo supports any number of Discord bots via `install.sh [bot-name]`. Existing example: `plannerbot` (medium effort, strategy). New example: `dsbot` (high effort, senior data scientist).

### One-line install

```bash
EFFORT=high bash install.sh dsbot
```

`EFFORT` accepts `medium` (default) or `high`. Other env vars:

- `EFFORT=medium|high` — passed to `--effort` flag and `effortLevel` in settings.json
- `DISALLOWED_TOOLS="ToolA,ToolB"` — passed to `--disallowedTools` flag (default: `AskUserQuestion,ExitPlanMode,TodoWrite,NotebookEdit`)

### Required new-bot files

For a brand-new bot (no existing `templates/soul-<bot>.md`), you need:

| File | Purpose |
|---|---|
| `templates/soul-<bot>.md` | Persona (frontmatter + identity + signatures + rules). Required. |
| `wrappers/bot-claude-wrapper.sh.template` | Already exists; parameterized by `{{BOT}}` / `{{EFFORT}}` / `{{DISALLOWED_TOOLS}}`. |
| `templates/settings.json.template` | Already exists; parameterized by `{{BOT}}` / `{{EFFORT_LEVEL}}`. |

If you want bot-specific CLI flags (not just effort), add `wrappers/<bot>-claude-wrapper.sh` and `install.sh` will use it directly instead of the template.

### Discord Developer Portal (per bot)

1. New Application → name = `<bot>` → Bot tab → Reset Token → copy
2. Privileged Gateway Intents → **Message Content Intent ON**
3. OAuth2 → URL Generator → `bot` + `applications.commands` scopes → invite to server
4. Get bot's snowflake ID (right-click bot → Copy User ID; needs Developer Mode)
5. Get user's own snowflake ID
6. Get channel IDs the bot should respond in

### State dir contents (per bot, after install)

```
~/.claude/channels/discord-<bot>/
├── .env              # DISCORD_BOT_TOKEN (chmod 600, user creates)
├── soul.md           # copied from templates/soul-<bot>.md (or soul-plannerbot.md fallback)
└── access.json       # user edits: allowFrom, mentionPatterns, ackReaction
```

### Cross-bot collaboration

Multiple bots in the same channel auto-mention each other via `meta.channel_bots` (injected by the discord plugin patch). No extra config needed beyond putting them in the same channels.

---

## 🤖 봇 관리 (`/bot` skill)

설치된 모든 Discord 봇을 한 곳에서 관리하는 Claude Code 슬래시 커맨드. 봇을 추가/제거/재시작/상태 확인하는 4가지 action + 자동 목록.

### Slash command 사용법

| 명령 | 동작 |
|---|---|
| `/bot` | 설치된 봇 목록 (plannerbot, dsbot, ...) |
| `/bot <name>` | 그 봇의 status (action 생략 시 기본) |
| `/bot <name> start` | `launchctl load` — 봇 시작 |
| `/bot <name> stop` | `launchctl unload` — 봇 정지 |
| `/bot <name> restart` | `launchctl kickstart -k` — 강제 재시작 |
| `/bot <name> status` | 6-line health check (아래) |

### Terminal 직접 호출

`/bot` 슬래시 커맨드 외에 bash helper 도 PATH 에서 직접 호출 가능:

```bash
bot                              # 봇 목록
bot plannerbot                   # plannerbot status
bot plannerbot restart           # 강제 재시작
bot dsbot start                  # dsbot 시작
bot nonexistent_xyz status       # exit 3, stderr: "not installed"
```

### status 출력 예시 (실제 dsbot)

```
dsbot
  launchd:   15869 0
  claude:    15882  --effort high
  bun:       <not running>
  gateway:   2 ESTABLISHED TCP (Discord via claude PID 15882)
  api:       HTTP 200 in 0.265s
```

5개 health signal:
- `launchd:` — plist PID + exit code (`not loaded` if stopped)
- `claude:` — claude process PID + effort level (`<not running>` if dead)
- `bun:` — bun server.ts PID (현재 환경에서는 `<not running>` 정상 — claude 안에서 inline 됨)
- `gateway:` — Discord gateway ESTABLISHED TCP count
- `api:` — `discord.com/api/v10/users/@me` HTTP status (토큰 검증)

### Exit codes

| Code | 의미 |
|---|---|
| 0 | success |
| 2 | unknown action (start/stop/restart/status 외) |
| 3 | bot not installed (plist 없음) |

### 파일 위치

| 파일 | 경로 |
|---|---|
| `SKILL.md` (slash command 정의) | `~/.claude/skills/bot/SKILL.md` |
| `bin/bot` (bash helper) | `~/.claude/skills/bot/bin/bot` |
| `tests/test_bot.sh` | `~/.claude/skills/bot/tests/test_bot.sh` |

### 테스트 실행

```bash
bash ~/.claude/skills/bot/tests/test_bot.sh
# 15 assertions, 5 tests, 모두 PASS (exit 0)
```

### Discovery — 새 봇 자동 인식

`bin/bot` 은 `~/Library/LaunchAgents/com.user.*-claude.plist` 를 glob 으로 스캔. `install.sh` 로 새 봇을 설치하면 (`EFFORT=high bash install.sh mybot`) `/bot` 목록에 자동 등장 — 별도 등록 작업 불필요.

### launchctl 직접 호출 (fallback)

`/bot` 이 launchctl 명령을 wrapping 한 것 — power user 는 여전히 직접 호출 가능:

```bash
launchctl list | grep <bot>                                              # 상태
launchctl load ~/Library/LaunchAgents/com.user.<bot>-claude.plist        # 시작
launchctl unload ~/Library/LaunchAgents/com.user.<bot>-claude.plist      # 중지
launchctl kickstart -k gui/501/com.user.<bot>-claude                      # 강제 재시작
```

---

## 🔧 수동 셋업 (단계별)

### 0. Discord 봇 생성

https://discord.com/developers/applications:
1. New Application → 이름
2. Bot 탭 → Reset Token → 토큰 복사
3. **Privileged Gateway Intents → Message Content Intent ON** (이거 OFF 면 채널 무반응)
4. OAuth2 → URL Generator:
   - Scopes: `bot`, `applications.commands`
   - Permissions: Send/Read Messages, Read History, Add Reactions, Attach Files, Embed Links
5. URL 로 본인 서버에 봇 초대

### 1. 환경 셋업

```bash
# bun
curl -fsSL https://bun.sh/install | bash

# plugin install (Claude Code 안)
/plugin install discord@claude-plugins-official
/reload-plugins
```

### 2. 봇 디렉토리

```bash
BOT=plannerbot
mkdir -p ~/.claude/channels/discord-$BOT && chmod 700 ~/.claude/channels/discord-$BOT

cat > ~/.claude/channels/discord-$BOT/.env <<EOF
DISCORD_BOT_TOKEN=<your-token>
EOF
chmod 600 ~/.claude/channels/discord-$BOT/.env

# soul.md 복사
cp templates/soul-plannerbot.md ~/.claude/channels/discord-$BOT/soul.md
```

### 3. discord plugin server.ts patch

```bash
PLUGIN_DIR="$HOME/.claude/plugins/cache/claude-plugins-official/discord/0.0.4"
cp patches/server.ts "$PLUGIN_DIR/server.ts"
# marketplace 도 동기화
cp patches/server.ts "$HOME/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/discord/server.ts"
```

### 4. `.mcp.json` 패치

```bash
cat > "$PLUGIN_DIR/.mcp.json" <<EOF
{
  "mcpServers": {
    "discord": {
      "command": "/Users/sanghee/.bun/bin/bun",
      "args": ["--install=fallback", "$PLUGIN_DIR/server.ts"]
    }
  }
}
EOF
```

### 5. launchd plist

```bash
cp launchd/com.user.plannerbot-claude.plist ~/Library/LaunchAgents/
# botname / WD / state_dir 환경에 맞게 sed 로 치환 후 load
launchctl load ~/Library/LaunchAgents/com.user.plannerbot-claude.plist
```

### 6. 페어링

1. 봇 DM → `안녕` → pairing code
2. 본체 claude 세션 (9485) 에서:
   ```
   /discord:access pair <code>
   ```
3. 이후 DM 자동 도달

---

## 📁 파일 구조

```
.
├── README.md                          # 본 문서
├── install.sh                         # 1-line installer (EFFORT env var)
├── templates/
│   ├── soul-plannerbot.md             # soul.md template (기획팀장 + cross-bot)
│   ├── soul-dsbot.md                  # soul.md template (시니어 DS generalist)
│   ├── settings.json.template         # parameterized settings.json
│   └── access.json.example            # access.json 예시 (user 편집)
├── patches/
│   └── server.ts                      # discord plugin server.ts (봇-봇 + channel_bots)
├── launchd/
│   └── com.user.plannerbot-claude.plist  # launchd plist template (sed 로 botname 치환)
├── wrappers/
│   ├── plannerbot-claude-wrapper.sh   # bot-specific wrapper (legacy, 보존)
│   └── bot-claude-wrapper.sh.template # parameterized wrapper (install.sh 가 사용)
├── tests/                             # install.sh / template 회귀 테스트
│   ├── templates/                     # 3개 template 회귀 테스트
│   ├── install/                       # install.sh 회귀 테스트
│   └── docs/                          # README / harness.md 회귀 테스트
└── docs/
    ├── troubleshooting.md             # 디버깅 가이드
    ├── architecture.md                # 아키텍처 상세
    ├── harness.md                     # 다봇 자율 하네스 (plannerbot=medium, dsbot=high)
    └── superpowers/                   # spec/plan/ledger (brainstorming 산출물)
        ├── specs/                     # feature designs
        ├── plans/                     # implementation plans
        └── sdd/                       # SDD progress ledger
```

**User-level (`~/.claude/skills/bot/`)** — `/bot` skill:

```
~/.claude/skills/bot/
├── SKILL.md           # slash command 정의 (auto-discovered)
├── bin/
│   └── bot            # bash helper: list | <name> [start|stop|restart|status]
└── tests/
    └── test_bot.sh    # 15 assertions, 5 tests (bash 직접 실행)
```

---

## 🛠 관리 명령

```bash
# 상태
launchctl list | grep planner
ps aux | grep -E '[c]laude.*--channels|[b]un.*server'

# 중지
launchctl unload ~/Library/LaunchAgents/com.user.plannerbot-claude.plist

# 시작
launchctl load ~/Library/LaunchAgents/com.user.plannerbot-claude.plist

# 로그
tail -f /tmp/plannerbot-claude-stderr.log
tail -f /tmp/plannerbot-claude-stdout.log
```

---

## 🔍 트러블슈팅

| 증상 | 원인 | 대응 |
|---|---|---|
| 봇 offline | server.ts stdin EOF → shutdown | `script -q /dev/null` pty wrapper 사용 |
| claude launchd 즉시 종료 | `--print` 모드 fallback (pty 없음) | `script` 로 pty 할당 |
| 토큰 valid 한데 채널 무반응 | Message Content Intent OFF | Developer Portal → Bot → ON |
| 봇-봇 멘션 무반응 | `server.ts:806` 봇 차단 | 본 repo `patches/server.ts` 적용 |
| 다중 bun process → 즉시 offline | 같은 토큰 동시 연결 → Discord kick | `pkill -9 -f server.ts` 후 단일 인스턴스만 |
| `claude mcp list` `✘ Failed to connect` (하지만 봇 online) | MCP health check artifact | Discord 에서 실제 응답 테스트 |

자세한 내용: [docs/troubleshooting.md](docs/troubleshooting.md)
