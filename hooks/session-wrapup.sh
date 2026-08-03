#!/bin/bash
# SessionEnd hook — last-chance reminder if you are walking away dirty.
#
# Deliberately does NOT kill any processes. A SessionEnd hook that sweeps for
# processes by name will happily kill a CONCURRENT session's work, because it
# cannot tell your other terminal's background job apart from your own orphan.
# If you ever need orphan cleanup, make it an explicit command you run on
# purpose, never an automatic sweep that fires unattended.

echo ""
echo "─────────────────────────────────────────────────────────"
echo "  SESSION WRAP-UP"
echo "─────────────────────────────────────────────────────────"

if git rev-parse --git-dir > /dev/null 2>&1; then
    CHANGES=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
    if [ "$CHANGES" -gt 0 ]; then
        echo "  ${CHANGES} uncommitted change(s):"
        git status --short 2>/dev/null | head -10
        echo ""
        echo "  Run /done next time to save session state and commit."
    else
        echo "  All changes committed."
    fi
fi
echo "─────────────────────────────────────────────────────────"

exit 0
