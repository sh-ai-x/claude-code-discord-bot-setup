#!/bin/bash
# gh-autoswitch-on-start.sh
# Claude Code SessionStart hook: ensures gh CLI is on the right user account
# for the current git repo's remote URL.
#
# Reads ~/.config/gh-autoswitch/accounts.conf (github_owner=gh_cli_account)
# and runs `gh auth switch --user <account>` if current account differs.

set -e

CONF="$HOME/.config/gh-autoswitch/accounts.conf"
CURRENT="$(gh auth status --show-token 2>/dev/null | awk '/Active account: true/ {print $NF}' | tr -d '()')"

# If we're not in a git repo, nothing to do
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
[ -z "$REMOTE_URL" ] && exit 0

# Extract owner from SSH or HTTPS remote URL
OWNER="$(echo "$REMOTE_URL" | sed -E 's#^[a-zA-Z]+://[^/]+/([^/]+)/[^/]+(\.git)?$#\1#; s#^[^@]+@[^:]+:([^/]+)/[^/]+(\.git)?$#\1#')"
[ -z "$OWNER" ] && exit 0

# Look up mapping
if [ -f "$CONF" ]; then
  TARGET="$(grep -E "^${OWNER}=" "$CONF" | head -1 | cut -d'=' -f2)"
fi

if [ -z "${TARGET:-}" ]; then
  echo "[gh-autoswitch-on-start] no mapping for owner '$OWNER' in $CONF"
  exit 0
fi

if [ "$CURRENT" != "$TARGET" ]; then
  echo "[gh-autoswitch-on-start] switching $CURRENT → $TARGET (owner=$OWNER)"
  gh auth switch --user "$TARGET" >/dev/null
else
  echo "[gh-autoswitch-on-start] already on $CURRENT (owner=$OWNER)"
fi