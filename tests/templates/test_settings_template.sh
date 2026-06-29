#!/usr/bin/env bash
# Verify templates/settings.json.template is a valid template that produces valid JSON.
set -euo pipefail
TEMPLATE="$(dirname "$0")/../../templates/settings.json.template"

# 1. File exists
[ -f "$TEMPLATE" ] || { echo "FAIL: $TEMPLATE missing"; exit 1; }

# 2. Has the EFFORT_LEVEL placeholder ({{BOT}} is for output path, not JSON content)
grep -q '{{EFFORT_LEVEL}}' "$TEMPLATE" || { echo "FAIL: {{EFFORT_LEVEL}} placeholder missing"; exit 1; }

# 3. Sed substitution produces valid JSON for dsbot
TMP_OUT="$(mktemp)"
sed -e "s|{{BOT}}|dsbot|g" -e "s|{{EFFORT_LEVEL}}|high|g" "$TEMPLATE" > "$TMP_OUT"
jq empty "$TMP_OUT" || { echo "FAIL: substituted output is not valid JSON"; cat "$TMP_OUT"; exit 1; }

# 4. Substituted JSON has the expected structure
jq -e '.effortLevel == "high"' "$TMP_OUT" >/dev/null
jq -e '.permissions.deny | index("AskUserQuestion")' "$TMP_OUT" >/dev/null
jq -e '.permissions.deny | index("ExitPlanMode")' "$TMP_OUT" >/dev/null

# 5. Default substitution (medium) also valid
sed -e "s|{{BOT}}|plannerbot|g" -e "s|{{EFFORT_LEVEL}}|medium|g" "$TEMPLATE" > "$TMP_OUT"
jq -e '.effortLevel == "medium"' "$TMP_OUT" >/dev/null

rm -f "$TMP_OUT"
echo "PASS: settings.json.template"