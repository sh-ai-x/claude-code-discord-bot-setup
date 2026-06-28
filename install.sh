#!/usr/bin/env bash
# claude-code-discord-bot-setup installer
# usage: bash install.sh [bot-name] (default: plannerbot)

set -euo pipefail

BOT="${1:-plannerbot}"
WD_DIR="$HOME/dev/projects/$BOT"
STATE_DIR="$HOME/.claude/channels/discord-$BOT"
PLUGIN_CACHE="$HOME/.claude/plugins/cache/claude-plugins-official/discord/0.0.4"
PLUGIN_MARKET="$HOME/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/discord"
PLIST="$HOME/Library/LaunchAgents/com.user.$BOT-claude.plist"

echo "=== install.sh for bot: $BOT ==="

# 1. 의존성
command -v bun >/dev/null || { echo "installing bun..."; curl -fsSL https://bun.sh/install | bash; }
command -v claude >/dev/null || { echo "claude not found. install: npm i -g @anthropic-ai/claude-code"; exit 1; }

# 2. 봇 디렉토리
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
[ -f "$STATE_DIR/.env" ] || { echo "ERROR: $STATE_DIR/.env not found. Create with DISCORD_BOT_TOKEN=<token>"; exit 1; }
chmod 600 "$STATE_DIR/.env"

# 3. soul.md (없으면 템플릿에서 복사)
[ -f "$STATE_DIR/soul.md" ] || cp "$(dirname "$0")/templates/soul-plannerbot.md" "$STATE_DIR/soul.md"

# 4. discord plugin 안내
echo "→ run inside claude: /plugin install discord@claude-plugins-official"
echo "→ then: /reload-plugins"

# 5. server.ts patch
mkdir -p "$PLUGIN_CACHE"
cp "$(dirname "$0")/patches/server.ts" "$PLUGIN_CACHE/server.ts"
[ -d "$PLUGIN_MARKET" ] && cp "$(dirname "$0")/patches/server.ts" "$PLUGIN_MARKET/server.ts"

# 6. .mcp.json
cat > "$PLUGIN_CACHE/.mcp.json" <<EOF
{
  "mcpServers": {
    "discord": {
      "command": "$HOME/.bun/bin/bun",
      "args": ["--install=fallback", "$PLUGIN_CACHE/server.ts"]
    }
  }
}
EOF

# 7. WD
mkdir -p "$WD_DIR"

# 8. launchd plist (sed 로 botname / WD / state_dir 치환)
sed -e "s|plannerbot|$BOT|g" \
    -e "s|/Users/sanghee/dev/projects/plannerbot|$WD_DIR|g" \
    -e "s|/Users/sanghee/.claude/channels/discord-plannerbot|$STATE_DIR|g" \
    "$(dirname "$0")/launchd/com.user.plannerbot-claude.plist" > "$PLIST"

# 9. wrapper
cp "$(dirname "$0")/wrappers/plannerbot-claude-wrapper.sh" "/tmp/$BOT-claude-wrapper.sh"
sed -i '' "s|plannerbot|$BOT|g" "/tmp/$BOT-claude-wrapper.sh"
chmod +x "/tmp/$BOT-claude-wrapper.sh"

# 10. plist 의 wrapper 경로 갱신
sed -i '' "s|/tmp/plannerbot-claude-wrapper.sh|/tmp/$BOT-claude-wrapper.sh|" "$PLIST"

# 11. load
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo ""
echo "=== 설치 완료 ==="
echo "봇: $BOT"
echo "STATE_DIR: $STATE_DIR"
echo "WD: $WD_DIR"
echo "launchd plist: $PLIST"
echo ""
echo "다음 단계:"
echo "1. Discord 앱에서 봇 DM → '안녕' → 페어링 코드"
echo "2. claude 본체 세션에서: /discord:access pair <code>"
echo "3. 봇 online 확인: launchctl list | grep $BOT"
