#!/usr/bin/env bash
set -euo pipefail
SOUL="$(dirname "$0")/../../templates/soul-dsbot.md"

# 1. File exists
[ -f "$SOUL" ] || { echo "FAIL: $SOUL missing"; exit 1; }

# 2. Has YAML frontmatter
head -1 "$SOUL" | grep -q '^---$' || { echo "FAIL: missing opening frontmatter delimiter"; exit 1; }

# 3. Frontmatter has name + description
sed -n '/^---$/,/^---$/p' "$SOUL" | grep -q '^name: dsbot$' || { echo "FAIL: name: dsbot missing in frontmatter"; exit 1; }

# 4. Identity section
grep -q '나는 \*\*dsbot\*\*' "$SOUL" || { echo "FAIL: identity section missing"; exit 1; }

# 5. All 4 senior principles present
for principle in 'Statistical Rigor|통계적 엄밀' 'Pragmatic Generalism|실용 일반' 'Code/Notebook Discipline|코드.*위생|노트북.*위생' 'Decision Framing|의사결정 프레이밍'; do
  grep -qE "$principle" "$SOUL" || { echo "FAIL: principle '$principle' missing"; exit 1; }
done

# 6. Cross-bot collaboration rule present
grep -qE 'cross-bot|교차 봇' "$SOUL" || { echo "FAIL: cross-bot collaboration rule missing"; exit 1; }

# 7. Thread/channel separation rule present
grep -qE 'chat_id|쓰레드.*채널.*세션 분리' "$SOUL" || { echo "FAIL: thread/channel separation rule missing"; exit 1; }

# 8. Signature line `— dsbot` present
grep -q '— dsbot\|-- dsbot' "$SOUL" || { echo "FAIL: dsbot signature line missing"; exit 1; }

# 9. References plannerbot as a peer (cross-bot)
grep -q 'plannerbot' "$SOUL" || { echo "FAIL: cross-bot reference to plannerbot missing"; exit 1; }

echo "PASS: soul-dsbot.md"
