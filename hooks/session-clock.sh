#!/bin/bash
# SessionStart hook.
#
# Two jobs:
#   1. Stamp this session's start time so session-age-warning.sh has a clock.
#   2. Print a short orientation banner, including a nudge to run /continue when
#      a saved session state exists.
#
# Requires: jq

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# State lives under $HOME, not /tmp — see the note in statusline.sh. In short: a
# predictable filename in a world-writable directory lets another local user
# pre-plant it as a symlink and redirect this write onto a file you own.
CACHE_DIR="${HOME}/.claude/.cache/starter-kit"
mkdir -p "$CACHE_DIR" 2>/dev/null && chmod 700 "$CACHE_DIR" 2>/dev/null

HOOK_INPUT=$(cat 2>/dev/null)
SESSION_ID=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9-' | cut -c1-64)
SOURCE=$(printf '%s' "$HOOK_INPUT" | jq -r '.source // "startup"' 2>/dev/null)

# Record session start time.
#   startup/clear : always (re)stamp, this is a genuine new session clock.
#   resume/compact: do NOT reset an existing stamp, or a long session could dodge
#                   the age warning forever by re-firing SessionStart. But DO
#                   recreate a missing one, so a reboot or a cleared cache
#                   mid-session does not permanently disable the warning.
if [ -n "$SESSION_ID" ]; then
    TS_FILE="${CACHE_DIR}/session-start-${SESSION_ID}"
    if [ "$SOURCE" = "startup" ] || [ "$SOURCE" = "clear" ] || [ ! -f "$TS_FILE" ]; then
        date +%s > "$TS_FILE"
    fi
fi

# Prune stale state. These files are a few bytes each, but without this the cache
# dir grows one entry per session forever. 7 days is far longer than any session,
# so this can never delete state that is still in use.
find "$CACHE_DIR" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null

# Anything interpolated into the banner below is sanitised with this first.
# Two reasons, and the second is the serious one:
#   1. Directory names, and the contents of a committed session-resume.json, are
#      not under your control when you clone someone else's repo.
#   2. This output goes straight to your terminal at session start, before you
#      have typed anything. Raw ANSI/OSC escape sequences in that text are a real
#      injection vector — they can rewrite what your terminal displays, and the
#      same text is also fed into the model's context unprompted.
# Stripping to printable characters closes both.
sanitise() { printf '%s' "$1" | tr -d '\000-\037\177' | tr -cd '[:print:]' | cut -c1-160; }

# ─── Orientation banner ──────────────────────────────────────────────────────
echo "─────────────────────────────────────────────────────────"
echo "  $(date '+%A, %B %-d, %Y — %-I:%M %p')"

if [ -n "$PROJECT_DIR" ] && cd "$PROJECT_DIR" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
    REPO=$(sanitise "$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")")
    BRANCH=$(sanitise "$(git branch --show-current 2>/dev/null)")
    DIRTY=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
    echo "  ${REPO} on ${BRANCH:-detached} — ${DIRTY} uncommitted"
fi

STATE="$PROJECT_DIR/.claude/session-resume.json"
if [ -f "$STATE" ]; then
    LAST_DATE=$(sanitise "$(jq -r '.session_date // "unknown"' "$STATE" 2>/dev/null)")
    NEXT=$(sanitise "$(jq -r '.next_steps[0] // empty' "$STATE" 2>/dev/null)")
    echo ""
    echo "  Saved session from ${LAST_DATE:-unknown}"
    [ -n "$NEXT" ] && echo "  Next: ${NEXT}"
    echo "  Run /continue to pick up where you left off."
fi
echo "─────────────────────────────────────────────────────────"

exit 0
