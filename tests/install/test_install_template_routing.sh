#!/usr/bin/env bash
# Verify install.sh has the right env vars, template routing, and shellcheck clean.
set -euo pipefail
INSTALL="$(dirname "$0")/../../install.sh"

# 1. install.sh exists
[ -f "$INSTALL" ] || { echo "FAIL: $INSTALL missing"; exit 1; }

# 2. Has EFFORT env var with medium default
grep -qE 'EFFORT="\$\{EFFORT:-medium\}"' "$INSTALL" || { echo "FAIL: EFFORT env var with medium default missing"; exit 1; }

# 3. Has DISALLOWED_TOOLS env var with the right default
grep -q 'DISALLOWED_TOOLS="${DISALLOWED_TOOLS:-AskUserQuestion,ExitPlanMode,TodoWrite,NotebookEdit}"' "$INSTALL" || { echo "FAIL: DISALLOWED_TOOLS env var with default missing"; exit 1; }

# 4. References the parameterized wrapper template
grep -q 'bot-claude-wrapper.sh.template' "$INSTALL" || { echo "FAIL: install.sh does not reference bot-claude-wrapper.sh.template"; exit 1; }

# 5. References the parameterized settings template
grep -q 'settings.json.template' "$INSTALL" || { echo "FAIL: install.sh does not reference settings.json.template"; exit 1; }

# 6. Per-bot soul template selection
grep -qE 'templates/soul-\$BOT\.md' "$INSTALL" || { echo "FAIL: per-bot soul template selection missing"; exit 1; }

# 7. Bot-specific wrapper fallback (prefers <bot>-claude-wrapper.sh)
grep -qE 'wrappers/\$BOT-claude-wrapper\.sh' "$INSTALL" || { echo "FAIL: bot-specific wrapper fallback missing"; exit 1; }

# 8. Shellcheck clean (if shellcheck available)
if command -v shellcheck >/dev/null; then
  shellcheck "$INSTALL" || { echo "FAIL: shellcheck errors in install.sh"; exit 1; }
fi

# 9. bash -n syntax check
bash -n "$INSTALL" || { echo "FAIL: bash syntax errors in install.sh"; exit 1; }

echo "PASS: install.sh template routing"