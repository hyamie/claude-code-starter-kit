#!/bin/bash
# Claude Code status line — repo:branch | context bar | token count | warning icon
#
# The bar is coloured by ABSOLUTE token count, not percent, because attention
# quality degrades at roughly fixed token counts regardless of how big your
# window is. 300k tokens is a degraded session whether the window is 200k or 1M.
#
# Requires: jq

input=$(cat)

CWD=$(echo "$input" | jq -r '.cwd // ""')

# ─── THE ONE KNOB ────────────────────────────────────────────────────────────
# Your context window, in tokens. Pinned rather than auto-detected because
# Claude Code under-reports it early in a session (it says 200k until you
# actually cross 200k), which makes an auto-detected bar flip its denominator
# mid-session.
#
#   1000000  = 1M context   (default)
#    200000  = standard context
#
# If you are NOT on a 1M-context plan, CHANGE THIS TO 200000. Leaving it at 1M
# on a 200k plan makes the bar read ~15% when you are really at 75% and about
# to auto-compact, which hides the exact wall this thing exists to warn you about.
CTX_SIZE=1000000
# ─────────────────────────────────────────────────────────────────────────────

# Current usage. Summing the three sub-fields is more accurate than the
# used_percentage field, which is computed against the under-reported window.
TOKENS_USED=$(echo "$input" | jq -r '.context_window.current_usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)')
[[ "$TOKENS_USED" =~ ^[0-9]+$ ]] || TOKENS_USED=0

PCT=$(( TOKENS_USED * 100 / CTX_SIZE ))
[ "$PCT" -gt 100 ] && PCT=100
TOKENS_K=$(( TOKENS_USED / 1000 ))
CTX_K=$(( CTX_SIZE / 1000 ))

# Cache for the context-size-warning hook (single echo, near-zero overhead).
#
# This lives under $HOME, NOT /tmp, and that is a security decision rather than a
# style one. The filename is derived from your project path, so in /tmp it would
# be fully predictable by any other user on the machine — they could pre-create
# it as a symlink to something you own (~/.bashrc, ~/.ssh/authorized_keys) and
# this `echo >` would happily follow the link and overwrite that file. Shared dev
# boxes, CI runners and multi-user containers all hit that. Under $HOME the
# directory is already yours and the attack has nowhere to stand.
#
# Must match the CACHE_DIR/path form in hooks/context-size-warning.sh.
CACHE_DIR="${HOME}/.claude/.cache/starter-kit"
if [ -n "$CWD" ] && mkdir -p "$CACHE_DIR" 2>/dev/null; then
  chmod 700 "$CACHE_DIR" 2>/dev/null
  # Slashes become dashes, so the result cannot contain a path separator and
  # cannot traverse out of CACHE_DIR even if cwd contains '..' segments.
  PROJECT_HASH="${CWD//\//-}"
  echo "$PCT $TOKENS_K $CTX_K" > "${CACHE_DIR}/ctx${PROJECT_HASH}" 2>/dev/null
fi

# Zone thresholds (absolute tokens)
ZONE_GREEN=100000    # 0-100k    full quality
ZONE_ORANGE=200000   # 100k-200k attention dilution starting
ZONE_RED=400000      # 200k-400k noticeable degradation
                     # 400k+     severely degraded, save and restart

GREEN='\033[32m'
ORANGE='\033[38;5;208m'
RED='\033[31m'
CYAN='\033[36m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

WARN=""
if [ "$TOKENS_USED" -ge "$ZONE_RED" ]; then
  WARN=" \xf0\x9f\x92\x80${RED}${BOLD} SAVE${RESET}"
elif [ "$TOKENS_USED" -ge "$ZONE_ORANGE" ]; then
  WARN=" \xf0\x9f\x94\xa5"
elif [ "$TOKENS_USED" -ge "$ZONE_GREEN" ]; then
  WARN=" \xe2\x9a\xa0"
fi

# 20-char bar. Each block is coloured by the zone its position falls in, so the
# bar shows you the gradient you are travelling through, not just where you are.
BAR_WIDTH=20
FILLED=$(( PCT * BAR_WIDTH / 100 ))
EMPTY=$(( BAR_WIDTH - FILLED ))
TOKENS_PER_BAR=$(( CTX_SIZE / BAR_WIDTH ))

BAR=""
for ((i=1; i<=FILLED; i++)); do
  if [ "$i" -eq "$FILLED" ]; then
    # The leading block takes the CURRENT zone colour. Without this, block
    # boundaries are 50k apart on a 1M window, so 125k would render all-green.
    if [ "$TOKENS_USED" -lt "$ZONE_GREEN" ]; then
      BAR+="${GREEN}\xe2\x96\x88${RESET}"
    elif [ "$TOKENS_USED" -lt "$ZONE_ORANGE" ]; then
      BAR+="${ORANGE}\xe2\x96\x88${RESET}"
    else
      BAR+="${RED}\xe2\x96\x88${RESET}"
    fi
  else
    BAR_TOKENS=$(( i * TOKENS_PER_BAR ))
    if [ "$BAR_TOKENS" -le "$ZONE_GREEN" ]; then
      BAR+="${GREEN}\xe2\x96\x88${RESET}"
    elif [ "$BAR_TOKENS" -le "$ZONE_ORANGE" ]; then
      BAR+="${ORANGE}\xe2\x96\x88${RESET}"
    else
      BAR+="${RED}\xe2\x96\x88${RESET}"
    fi
  fi
done
for ((i=0; i<EMPTY; i++)); do
  BAR+="${DIM}\xe2\x96\x91${RESET}"
done

if [ "$TOKENS_USED" -lt "$ZONE_GREEN" ]; then
  NUM_COLOR="$GREEN"
elif [ "$TOKENS_USED" -lt "$ZONE_ORANGE" ]; then
  NUM_COLOR="$ORANGE"
else
  NUM_COLOR="$RED"
fi

REPO=""
BRANCH=""
# The -n guard matters: `cd ""` SUCCEEDS in bash and leaves you where you were,
# so without it an empty cwd would report whatever repo this happened to start
# in, rather than correctly reporting nothing.
if [ -n "$CWD" ] && cd "$CWD" 2>/dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
  REPO=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
  BRANCH=$(git branch --show-current 2>/dev/null)
fi

PARTS=""
if [ -n "$REPO" ]; then
  if [ -n "$BRANCH" ]; then
    PARTS="${CYAN}${REPO}${RESET}${DIM}:${RESET}${CYAN}${BRANCH}${RESET}"
  else
    PARTS="${CYAN}${REPO}${RESET}"
  fi
fi

CTX_PART="${BAR} ${NUM_COLOR}${BOLD}${TOKENS_K}k${RESET}${DIM}/${CTX_K}k${RESET}${WARN}"

if [ -n "$PARTS" ]; then
  echo -e "${PARTS} ${DIM}\xe2\x94\x82${RESET} ${CTX_PART}"
else
  echo -e "${CTX_PART}"
fi
