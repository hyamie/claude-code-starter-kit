#!/bin/bash
# UserPromptSubmit hook — warn as context approaches the auto-compaction point.
#
# Auto-compaction is not a fixed token number. It fires at `autoCompactPercentage`
# of your ACTUAL window (Claude Code's default is 75%):
#
#     200k window -> compacts around 150k
#     1M   window -> compacts around 750k
#
# So this derives the trigger point from your real window rather than hardcoding
# a token count. Hardcoding one is a trap: a number measured on a 200k session
# fires constantly on a 1M session that has 600k of clean headroom left.
#
#     WARN   = 80% of the way to compaction
#     URGENT = 90% of the way there
#
# Reads the cache written by statusline.sh, so your window size is configured in
# ONE place (the CTX_SIZE knob in statusline.sh) and both agree by construction.
#
# Requires: jq

# State lives under $HOME, not /tmp. See the note in statusline.sh: these paths
# are predictable, and a predictable path in a world-writable directory is a
# symlink-clobber target for any other user on the machine.
CACHE_DIR="${HOME}/.claude/.cache/starter-kit"
mkdir -p "$CACHE_DIR" 2>/dev/null && chmod 700 "$CACHE_DIR" 2>/dev/null

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJECT_HASH="${PROJECT_DIR//\//-}"
CACHE="${CACHE_DIR}/ctx${PROJECT_HASH}"

# Require a real session_id — no static fallback filename, so a session without
# one simply skips the latch rather than sharing a single well-known path.
SESSION_ID=$(jq -r '.session_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9-' | cut -c1-64)
[ -n "$SESSION_ID" ] || exit 0
LATCH_FILE="${CACHE_DIR}/ctx-warned-${SESSION_ID}"

# Missing cache = the status line has not rendered yet (normal on the first turn
# of a fresh session). Silent. A cache that EXISTS but is malformed is different:
# that is corrupt data, and staying quiet about it would look identical to
# "everything is fine". Say so, once.
[ -f "$CACHE" ] || exit 0

read -r _ TOKENS_K CTX_K < "$CACHE" 2>/dev/null

# 1-7 digits: numeric-only, and length-bounded so a pathological line cannot
# overflow the integer comparisons below.
if ! [[ "$TOKENS_K" =~ ^[0-9]{1,7}$ ]] || ! [[ "$CTX_K" =~ ^[0-9]{1,7}$ ]] || [ "$CTX_K" -lt 1 ]; then
    MALFORMED_LATCH="${CACHE_DIR}/ctx-malformed-${SESSION_ID}"
    if [ ! -f "$MALFORMED_LATCH" ]; then
        : > "$MALFORMED_LATCH"
        echo ""
        echo "  context-size-warning: cache at ${CACHE} is malformed — context warnings are OFF this session."
        echo "  (Check that statusline.sh is installed and running.)"
        echo ""
    fi
    exit 0
fi

[ "$TOKENS_K" -eq 0 ] && exit 0

# Compaction trigger = autoCompactPercentage of the real window. Read the live
# setting so this tracks your config instead of a magic number. Default 75.
COMPACT_PCT=$(jq -r '.autoCompactPercentage // 75' "$HOME/.claude/settings.json" 2>/dev/null)
[[ "$COMPACT_PCT" =~ ^[0-9]{1,3}$ ]] && [ "$COMPACT_PCT" -ge 1 ] && [ "$COMPACT_PCT" -le 100 ] || COMPACT_PCT=75

COMPACT_K=$(( CTX_K * COMPACT_PCT / 100 ))
WARN_K=$(( COMPACT_K * 80 / 100 ))
URGENT_K=$(( COMPACT_K * 90 / 100 ))

# Tier latch (0=none, 1=warn shown, 2=urgent shown). Re-arms below the warn tier,
# so after a compaction drops your token count the next climb warns again.
WARNED_TIER=$(cat "$LATCH_FILE" 2>/dev/null)
case "$WARNED_TIER" in ''|*[!0-9]*) WARNED_TIER=0 ;; esac

if [ "$TOKENS_K" -ge "$URGENT_K" ]; then
    if [ "$WARNED_TIER" -lt 2 ]; then
        echo 2 > "$LATCH_FILE"
        echo ""
        echo "  CONTEXT ${TOKENS_K}k/${CTX_K}k — auto-compaction (~${COMPACT_K}k) is close and will drop context. Run /done now."
        echo ""
    fi
elif [ "$TOKENS_K" -ge "$WARN_K" ]; then
    if [ "$WARNED_TIER" -lt 1 ]; then
        echo 1 > "$LATCH_FILE"
        echo ""
        echo "  CONTEXT ${TOKENS_K}k/${CTX_K}k — approaching auto-compaction (~${COMPACT_K}k). Run /done at the next natural boundary."
        echo ""
    fi
else
    [ "$WARNED_TIER" -ne 0 ] && echo 0 > "$LATCH_FILE"
fi

exit 0
