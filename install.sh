#!/usr/bin/env bash
# install.sh — set up a Discord bot managed via tmux + launchd (boot-time tmux wrapper)
#
# usage: bash install.sh <bot>     (default: plannerbot)
# env:   EFFORT=medium|high        (default: medium)
#        DISALLOWED_TOOLS="..."    (default: AskUserQuestion,ExitPlanMode,TodoWrite,NotebookEdit)
set -euo pipefail

BOT="${1:-plannerbot}"
EFFORT="${EFFORT:-medium}"
DISALLOWED_TOOLS="${DISALLOWED_TOOLS:-AskUserQuestion,ExitPlanMode,TodoWrite,NotebookEdit}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
WD="$HOME/dev/projects/$BOT"
STATE="$HOME/.claude/channels/discord-$BOT"
PLUGIN="$HOME/.claude/plugins/cache/claude-plugins-official/discord/0.0.4"
PLIST="$HOME/Library/LaunchAgents/com.user.$BOT-tmux-claude.plist"

echo "=== install: $BOT (effort=$EFFORT) ==="

command -v bun >/dev/null || { echo "installing bun..."; curl -fsSL https://bun.sh/install | bash; }
command -v claude >/dev/null || { echo "ERROR: claude CLI not in PATH"; exit 1; }

mkdir -p "$STATE" && chmod 700 "$STATE"
[ -f "$STATE/.env" ] || { echo "ERROR: missing $STATE/.env (create with DISCORD_BOT_TOKEN=...)"; exit 1; }
chmod 600 "$STATE/.env"

# soul.md — per-bot template, fallback to plannerbot
SOUL="$ROOT/templates/soul-$BOT.md"
[ -f "$SOUL" ] || SOUL="$ROOT/templates/soul-plannerbot.md"
[ -f "$STATE/soul.md" ] || cp "$SOUL" "$STATE/soul.md"

echo "→ inside claude, run: /plugin install discord@claude-plugins-official && /reload-plugins"

mkdir -p "$PLUGIN"
cp "$ROOT/patches/server.ts" "$PLUGIN/server.ts"
[ -d "$HOME/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/discord" ] && \
  cp "$ROOT/patches/server.ts" "$HOME/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/discord/server.ts"

cat > "$PLUGIN/.mcp.json" <<EOF
{
  "mcpServers": {
    "discord": {
      "command": "$HOME/.bun/bin/bun",
      "args": ["--install=fallback", "$PLUGIN/server.ts"]
    }
  }
}
EOF

mkdir -p "$WD"

# launchd → tmux plist (auto-resurrects tmux session on boot)
sed -e "s|{{BOT}}|$BOT|g" \
    -e "s|{{HOME}}|$HOME|g" \
    "$ROOT/launchd/com.user.tmplbot-tmux-claude.plist" > "$PLIST"

# wrapper
sed -e "s|{{BOT}}|$BOT|g" \
    -e "s|{{EFFORT}}|$EFFORT|g" \
    -e "s|{{DISALLOWED_TOOLS}}|$DISALLOWED_TOOLS|g" \
    -e "s|$HOME/dev/projects/plannerbot|$WD|g" \
    -e "s|$HOME/.claude/channels/discord-plannerbot|$STATE|g" \
    "$ROOT/wrappers/bot-claude-wrapper.sh.template" > "/tmp/$BOT-claude-wrapper.sh"
chmod +x "/tmp/$BOT-claude-wrapper.sh"

# settings.json — includes enabledPlugins so --channels flag actually loads the plugin
sed -e "s|{{BOT}}|$BOT|g" \
    -e "s|{{EFFORT_LEVEL}}|$EFFORT|g" \
    "$ROOT/templates/settings.json.template" > "/tmp/$BOT-settings.json"

# Start the bot in tmux (recommended path). launchd plist will resurrect on boot.
if command -v tmux >/dev/null && [ -f "$HOME/.local/bin/bot" ]; then
    "$HOME/.local/bin/bot" "$BOT" start
else
    # Fallback: launchd plist runs wrapper directly (legacy path; stdin may EOF)
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
fi

echo ""
echo "=== installed ==="
echo "state: $STATE"
echo "wd:    $WD"
echo "plist: $PLIST"
echo ""
echo "Next:"
echo "1. DM the bot '안녕' → pairing code"
echo "2. /discord:access pair <code>"
echo "3. bot $BOT status"