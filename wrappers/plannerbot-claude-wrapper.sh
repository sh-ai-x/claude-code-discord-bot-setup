#!/bin/zsh
# plannerbot 한정 강한 자율 하네스:
#   - --effort medium (속도 우선)
#   - --settings /tmp/plannerbot-settings.json (effort + permissions.deny)
#   - --disallowedTools "AskUserQuestion,ExitPlanMode" (사용자 묻지 않음)
#   - --dangerously-skip-permissions (이미 적용)
#   - script -q /dev/null → pty (claude interactive 모드)
export PATH="/Users/sanghee/.bun/bin:/Users/sanghee/.nvm/versions/node/v22.20.0/bin:/opt/homebrew/bin:/usr/bin:/bin"
export DISCORD_STATE_DIR="/Users/sanghee/.claude/channels/discord-plannerbot"
cd "/Users/sanghee/dev/projects/plannerbot"
exec /usr/bin/script -q /dev/null /Users/sanghee/.nvm/versions/node/v22.20.0/bin/claude \
  --channels plugin:discord@claude-plugins-official \
  --dangerously-skip-permissions \
  --effort medium \
  --settings /tmp/plannerbot-settings.json \
  --disallowedTools "AskUserQuestion,ExitPlanMode,TodoWrite,NotebookEdit"
