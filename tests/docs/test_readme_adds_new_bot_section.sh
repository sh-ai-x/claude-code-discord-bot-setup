#!/usr/bin/env bash
set -euo pipefail
README="$(dirname "$0")/../../README.md"

# 1. File exists
[ -f "$README" ] || { echo "FAIL: $README missing"; exit 1; }

# 2. Has "Adding a new bot" or equivalent section
grep -qE '^#+ .*(Adding a new bot|새 봇 추가|새로운 봇)' "$README" || { echo "FAIL: Adding a new bot section missing"; exit 1; }

# 3. Mentions EFFORT env var
grep -qE 'EFFORT=' "$README" || { echo "FAIL: EFFORT env var example missing"; exit 1; }

# 4. Mentions dsbot as the new example
grep -q 'dsbot' "$README" || { echo "FAIL: dsbot example missing"; exit 1; }

# 5. Lists the parameterized template files
grep -q 'wrappers/bot-claude-wrapper.sh.template\|bot-claude-wrapper.sh.template' "$README" || { echo "FAIL: template file reference missing"; exit 1; }

echo "PASS: README.md adding a new bot section"
