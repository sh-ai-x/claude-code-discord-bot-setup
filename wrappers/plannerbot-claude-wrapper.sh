#!/bin/zsh
# launchd 가 claude 를 띄울 때 pty 가 없어서 --print 모드 fallback
# `script` 로 pty 를 만들어서 claude 가 interactive 모드로 동작하게
export PATH="/Users/sanghee/.bun/bin:/Users/sanghee/.nvm/versions/node/v22.20.0/bin:/opt/homebrew/bin:/usr/bin:/bin"
export DISCORD_STATE_DIR="$HOME/.claude/channels/discord-plannerbot"
cd "/Users/sanghee/dev/projects/plannerbot"
# script 가 pty 할당하고 claude 실행
exec /usr/bin/script -q /dev/null /Users/sanghee/.nvm/versions/node/v22.20.0/bin/claude \
  --channels plugin:discord@claude-plugins-official \
  --dangerously-skip-permissions
