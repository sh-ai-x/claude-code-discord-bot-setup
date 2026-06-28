# Claude Code + Discord Bot — Autonomous Setup (plannerbot)

> **Mac (Darwin) + launchd 기반 영구 봇 운영 가이드**.
> 1줄 명령으로 부팅 시 자동 시작 + crash 자동 재시작 + 다봇 협업 (`@plannerbot` 멘션 + 봇-봇 핸드오프).

---

## 📋 결과 요약

| 항목 | 상태 |
|---|---|
| `~/.claude/channels/discord-plannerbot/` (700) | ✅ 봇 디렉토리 |
| `.env` (chmod 600, `DISCORD_BOT_TOKEN`) | ✅ |
| `soul.md` (기획팀장 + cross-bot 멘션 규율) | ✅ |
| `access.json` (7 채널 등록, `ackReaction=👀`) | ✅ |
| discord plugin (`claude-plugins-official/discord`) | ✅ enabled |
| cache + marketplace `server.ts` patch | ✅ 봇-봇 멘션 + `channel_bots` 자동 주입 |
| `.mcp.json` launch command fix | ✅ `bun --install=fallback server.ts` |
| launchd plist (`com.user.plannerbot-claude`) | ✅ RunAtLoad + KeepAlive |
| `script` pty wrapper | ✅ claude interactive 모드 |
| 봇 online + DM/스레드/봇-봇 멘션 응답 | ✅ |

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
├── install.sh                         # 1-line installer
├── templates/
│   └── soul-plannerbot.md             # soul.md template (기획팀장 + cross-bot)
├── patches/
│   └── server.ts                      # discord plugin server.ts (봇-봇 + channel_bots)
├── launchd/
│   └── com.user.plannerbot-claude.plist  # launchd plist
├── wrappers/
│   └── plannerbot-claude-wrapper.sh   # script pty wrapper
└── docs/
    ├── troubleshooting.md             # 디버깅 가이드
    └── architecture.md                # 아키텍처 상세
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
