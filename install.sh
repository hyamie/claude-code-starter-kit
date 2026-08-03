#!/usr/bin/env bash
# Claude Code starter kit installer.
#
# Installs a status line, four session hooks, and the /continue + /done commands
# into ~/.claude/. Idempotent: safe to re-run. Backs up settings.json first.
#
# Usage:  ./install.sh
#         ./install.sh --dry-run     show what it would do, change nothing

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS="${CLAUDE_DIR}/settings.json"
DRY_RUN=0

[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

say()  { printf '  %s\n' "$*"; }
step() { printf '\n%s\n' "$*"; }

# ─── Preflight ───────────────────────────────────────────────────────────────
step "Checking dependencies"
MISSING=0
for dep in jq git; do
  if command -v "$dep" >/dev/null 2>&1; then
    say "ok   $dep"
  else
    say "MISSING  $dep"
    MISSING=1
  fi
done
if [ "$MISSING" -eq 1 ]; then
  echo ""
  echo "Install the missing dependencies first:"
  echo "  macOS:         brew install jq git"
  echo "  Debian/Ubuntu: sudo apt install jq git"
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  step "DRY RUN — nothing below will actually be written"
fi

# ─── Files ───────────────────────────────────────────────────────────────────
step "Installing files into ${CLAUDE_DIR}"

HOOKS="session-clock.sh session-age-warning.sh context-size-warning.sh session-wrapup.sh"
COMMANDS="continue.md done.md"

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "${CLAUDE_DIR}/hooks" "${CLAUDE_DIR}/commands"
  install -m 0755 "${SRC}/statusline.sh" "${CLAUDE_DIR}/statusline.sh"
  for h in $HOOKS; do
    install -m 0755 "${SRC}/hooks/${h}" "${CLAUDE_DIR}/hooks/${h}"
  done
  for c in $COMMANDS; do
    install -m 0644 "${SRC}/commands/${c}" "${CLAUDE_DIR}/commands/${c}"
  done
fi

say "statusline.sh"
for h in $HOOKS; do say "hooks/${h}"; done
for c in $COMMANDS; do say "commands/${c}"; done

# ─── settings.json ───────────────────────────────────────────────────────────
step "Wiring ${SETTINGS}"

if [ ! -f "$SETTINGS" ]; then
  say "no settings.json — creating one"
  [ "$DRY_RUN" -eq 0 ] && echo '{}' > "$SETTINGS"
fi

if [ "$DRY_RUN" -eq 0 ]; then
  if ! jq . "$SETTINGS" >/dev/null 2>&1; then
    echo ""
    echo "ERROR: ${SETTINGS} is not valid JSON. Fix it before installing."
    exit 1
  fi

  BACKUP="${SETTINGS}.backup-$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS" "$BACKUP"
  say "backup: ${BACKUP}"

  # Report an existing status line before replacing it, so it is recoverable.
  EXISTING_SL=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null)
  if [ -n "$EXISTING_SL" ]; then
    say "replacing existing statusLine: ${EXISTING_SL}"
  fi
fi

apply_jq() {
  # apply_jq <jq-program> [--arg k v ...]
  local prog="$1"; shift
  [ "$DRY_RUN" -eq 1 ] && return 0
  local tmp
  tmp=$(mktemp)
  if jq "$@" "$prog" "$SETTINGS" > "$tmp" 2>/dev/null && jq . "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$SETTINGS"
  else
    rm -f "$tmp"
    echo "ERROR: settings.json edit failed. Restoring backup."
    cp "$BACKUP" "$SETTINGS"
    exit 1
  fi
}

# Status line
apply_jq '.statusLine = {"type": "command", "command": ("bash " + $sl)}' \
  --arg sl "${CLAUDE_DIR}/statusline.sh"
say "statusLine -> bash ${CLAUDE_DIR}/statusline.sh"

# Hooks. Appends only if that exact command is not already wired, so re-running
# the installer does not stack duplicates.
add_hook() {
  local event="$1" cmd="$2"
  apply_jq '
    .hooks //= {}
    | .hooks[$ev] //= []
    | if ([.hooks[$ev][]? | .hooks[]? | .command] | index($cmd))
      then .
      else .hooks[$ev] += [{"hooks": [{"type": "command", "command": $cmd}]}]
      end
  ' --arg ev "$event" --arg cmd "$cmd"
  say "${event} -> $(basename "$cmd")"
}

add_hook SessionStart      "${CLAUDE_DIR}/hooks/session-clock.sh"
add_hook UserPromptSubmit  "${CLAUDE_DIR}/hooks/session-age-warning.sh"
add_hook UserPromptSubmit  "${CLAUDE_DIR}/hooks/context-size-warning.sh"
add_hook SessionEnd        "${CLAUDE_DIR}/hooks/session-wrapup.sh"

# ─── Done ────────────────────────────────────────────────────────────────────
step "Installed."
cat <<'EOF'

  Restart Claude Code to pick up the status line and hooks.

  Then, in any git repo:
    /done       save session state, commit, push
    /continue   restore context next session

  IF YOU ARE NOT ON A 1M-CONTEXT PLAN, open ~/.claude/statusline.sh and change
  CTX_SIZE from 1000000 to 200000. It is the first setting in the file. Leaving
  it wrong makes the context bar under-report how full you are.

  To uninstall: restore the settings.json backup printed above, then delete the
  installed files from ~/.claude/{statusline.sh,hooks,commands} and the state
  directory ~/.claude/.cache/starter-kit.

EOF
