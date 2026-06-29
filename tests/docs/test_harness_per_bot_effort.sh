#!/usr/bin/env bash
set -euo pipefail
HARNESS="$(dirname "$0")/../../docs/harness.md"

# 1. File exists
[ -f "$HARNESS" ] || { echo "FAIL: $HARNESS missing"; exit 1; }

# 2. Notes that dsbot uses high effort (or generalist DS context)
grep -qE 'dsbot.*high|dsbot.*senior' "$HARNESS" || { echo "FAIL: dsbot high-effort note missing"; exit 1; }

# 3. Mentions EFFORT env var as the per-bot switch
grep -q 'EFFORT' "$HARNESS" || { echo "FAIL: EFFORT env var reference missing"; exit 1; }

# 4. Distinguishes plannerbot (medium) from dsbot (high)
grep -qE 'plannerbot.*medium|medium.*plannerbot' "$HARNESS" || { echo "FAIL: plannerbot medium reference missing"; exit 1; }

echo "PASS: harness.md per-bot effort"
