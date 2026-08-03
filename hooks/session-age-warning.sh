#!/bin/bash
# UserPromptSubmit hook — nudge you to checkpoint once a session gets long.
#
# Long sessions drift: context gets compacted, early decisions fall out of the
# window, and you start re-litigating things you already settled. This warns at
# 2h and again at 3h so you stop at a boundary you chose instead of one the
# compactor chose for you.
#
# Reads the clock stamped by hooks/session-clock.sh.
# Requires: jq

SESSION_ID=$(jq -r '.session_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9-' | cut -c1-64)
[ -n "$SESSION_ID" ] || exit 0

# State lives under $HOME, not /tmp — see the note in statusline.sh.
CACHE_DIR="${HOME}/.claude/.cache/starter-kit"
SESSION_TIMESTAMP_FILE="${CACHE_DIR}/session-start-${SESSION_ID}"
LATCH_FILE="${CACHE_DIR}/age-warned-${SESSION_ID}"

WARN_THRESHOLD=7200      # 2 hours
URGENT_THRESHOLD=10800   # 3 hours

# No stamp means session-clock.sh has not run yet. Nothing to measure.
[ -f "$SESSION_TIMESTAMP_FILE" ] || exit 0

START_TIME=$(cat "$SESSION_TIMESTAMP_FILE" 2>/dev/null)
# Must be plain digits before it reaches $(( )). The stamp lives in world-writable
# /tmp, and bash arithmetic evaluates array-subscript command substitution, so a
# crafted value like 'a[$(cmd)]' would execute cmd. Reject anything non-numeric.
case "$START_TIME" in
    ''|*[!0-9]*) exit 0 ;;
esac

NOW=$(date +%s)
ELAPSED=$((NOW - START_TIME))
HOURS=$((ELAPSED / 3600))
MINUTES=$(((ELAPSED % 3600) / 60))

# Latch so this fires once per tier, not on every single prompt.
WARNED_TIER=$(cat "$LATCH_FILE" 2>/dev/null)
case "$WARNED_TIER" in ''|*[!0-9]*) WARNED_TIER=0 ;; esac

if [ $ELAPSED -gt $URGENT_THRESHOLD ] && [ "$WARNED_TIER" -lt 2 ]; then
    echo 2 > "$LATCH_FILE"
    cat <<EOF

─────────────────────────────────────────────────────────
  SESSION DURATION: ${HOURS}h ${MINUTES}m  (urgent)
─────────────────────────────────────────────────────────
  Context drift and compaction are likely happening now.

  1. Get to a commit-worthy stopping point
  2. Run /done to save session state
  3. Restart Claude, run /continue
─────────────────────────────────────────────────────────

EOF
elif [ $ELAPSED -gt $WARN_THRESHOLD ] && [ "$WARNED_TIER" -lt 1 ]; then
    echo 1 > "$LATCH_FILE"
    cat <<EOF

  SESSION DURATION: ${HOURS}h ${MINUTES}m
  Good checkpoint to /done and restart?

EOF
fi

exit 0
