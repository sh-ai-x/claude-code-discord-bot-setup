#!/usr/bin/env bash
set -euo pipefail
TEMPLATE="$(dirname "$0")/../../wrappers/bot-claude-wrapper.sh.template"

# 1. File exists
[ -f "$TEMPLATE" ] || { echo "FAIL: $TEMPLATE missing"; exit 1; }

# 2. All required placeholders present
for p in '{{BOT}}' '{{EFFORT}}' '{{DISALLOWED_TOOLS}}'; do
  grep -q "$p" "$TEMPLATE" || { echo "FAIL: placeholder $p missing"; exit 1; }
done

# 3. Shellcheck clean (if shellcheck available; skip silently if not)
if command -v shellcheck >/dev/null; then
  TMP_OUT="$(mktemp)"
  sed -e "s|{{BOT}}|dsbot|g" \
      -e "s|{{EFFORT}}|high|g" \
      -e "s|{{DISALLOWED_TOOLS}}|AskUserQuestion,ExitPlanMode,TodoWrite,NotebookEdit|g" \
      "$TEMPLATE" > "$TMP_OUT"
  shellcheck "$TMP_OUT" || { echo "FAIL: shellcheck errors"; rm -f "$TMP_OUT"; exit 1; }
  rm -f "$TMP_OUT"
fi

# 4. bash -n (syntax check) on substituted output
TMP_OUT="$(mktemp)"
sed -e "s|{{BOT}}|dsbot|g" \
    -e "s|{{EFFORT}}|high|g" \
    -e "s|{{DISALLOWED_TOOLS}}|AskUserQuestion,ExitPlanMode,TodoWrite,NotebookEdit|g" \
    "$TEMPLATE" > "$TMP_OUT"
bash -n "$TMP_OUT" || { echo "FAIL: substituted output has bash syntax errors"; rm -f "$TMP_OUT"; exit 1; }
rm -f "$TMP_OUT"

# 5. Substituted content has expected dsbot-specific values
TMP_OUT="$(mktemp)"
sed -e "s|{{BOT}}|dsbot|g" \
    -e "s|{{EFFORT}}|high|g" \
    -e "s|{{DISALLOWED_TOOLS}}|AskUserQuestion,ExitPlanMode,TodoWrite,NotebookEdit|g" \
    "$TEMPLATE" > "$TMP_OUT"
grep -q 'discord-dsbot' "$TMP_OUT" || { echo "FAIL: discord-dsbot path missing"; exit 1; }
grep -q 'dev/projects/dsbot' "$TMP_OUT" || { echo "FAIL: dev/projects/dsbot path missing"; exit 1; }
grep -q -- '--effort high' "$TMP_OUT" || { echo "FAIL: --effort high missing"; exit 1; }
grep -q 'dsbot-settings.json' "$TMP_OUT" || { echo "FAIL: dsbot-settings.json missing"; exit 1; }
rm -f "$TMP_OUT"

echo "PASS: bot-claude-wrapper.sh.template"
