---
name: done
description: Verify, save session state, commit, and close out the session
effort: medium
---

# End Session

Save what happened so the next session starts informed instead of guessing. Run this
before you close a session, and any time a hook nags you about context or duration.

The output of this command is `.claude/session-resume.json`. `/continue` reads it.

> Note if you edit this file: the slash-command processor consumes bare
> positional-argument placeholders (a dollar sign followed by a single digit 1-9)
> before the bash ever runs, so any that appear here get silently deleted. That
> rules out shell function arguments and field references like an awk print of the
> second column. Use named variables in braces, and back-references in `sed`, instead.

## Process

### 1. Verify

Only run checks if the project HAS them AND there is real work to verify. A
state-only commit (nothing dirty but `session-resume.json`) skips this — tests
don't depend on the state file, so running them is latency for zero signal.

```bash
WORK_DIRTY=$(git status --porcelain | sed 's/^...//' | grep -v '^\.claude/session-resume\.json$' | grep -v '^$' | wc -l)

if [ "$WORK_DIRTY" -eq 0 ]; then
  echo "  state-only — skipping verify"
elif [ -f .claude/verify.sh ]; then
  bash .claude/verify.sh
elif [ -f package.json ] && grep -qE '"(test|lint|typecheck|build)"' package.json; then
  grep -q '"lint"' package.json && npm run lint
  grep -q '"typecheck"' package.json && npm run typecheck
  grep -q '"test"' package.json && npm test
elif [ -f pytest.ini ] || [ -f setup.py ] || [ -f pyproject.toml ]; then
  pytest
elif [ -f Cargo.toml ]; then
  cargo test && cargo clippy -- -D warnings
elif [ -f go.mod ]; then
  go test ./... && go vet ./...
else
  # NOT silent. Zero probe matches is ambiguous: it means EITHER "this repo
  # correctly has no checks" OR "this repo has a real suite that is named or
  # located outside the probe list" — and the probe cannot tell those apart.
  # Printing nothing here reads as a pass, which is how a repo sits untested
  # for months while this command looks green every time.
  echo "  no verify targets found — VERIFICATION DID NOT RUN"
  echo "  (probed: .claude/verify.sh, package.json scripts, pytest.ini/setup.py/pyproject.toml, Cargo.toml, go.mod)"
  echo "  If this repo does have checks, wire them into .claude/verify.sh."
fi
```

If no checks were found, say so out loud in the summary. Do **not** write
"verified" into the state file on the strength of a zero-match, and do not treat
it as a pass.

**If verification FAILS: stop and fix it before continuing.** Do not save state
describing broken work as done.

### 2. Write session state

**Always `Read` `.claude/session-resume.json` first if it exists** — a real Read
call, even if you think you know what's in it. The Write tool refuses to write
files it has not read.

Then use the Write tool to create or update it:

```json
{
  "timestamp": "ISO-8601",
  "session_date": "YYYY-MM-DD",
  "verification_status": "passed | skipped | did-not-run",
  "completed": ["what actually got done"],
  "in_progress": ["what is half-finished, and where it stands"],
  "next_steps": ["what to do next, most important first"],
  "blockers": ["anything stuck, and what it is waiting on"],
  "tried_and_rejected": ["approach that was abandoned — plus a one-line why not"],
  "notes": ["context that is not obvious from the diff"],
  "branch": "branch-name"
}
```

**`tried_and_rejected` is the highest-value field in the file.** If you tried an
approach this session and abandoned it — wrong API, dead-end refactor, a design
that fell apart on contact with reality — record it with a one-line "why not."
Next session reads it first and won't burn an hour rediscovering the same dead
end. Empty `[]` if nothing was abandoned.

**Do not add a `last_commit` field.** `/continue` derives the session commit from
`git log` on this file. Embedding a commit's SHA inside its own content is
impossible: writing the SHA changes the tree, which changes the SHA.

Before committing, scan this session's work for newly-added TODO/FIXME markers and
mention any in `notes` — cheap signal for work that got explicitly punted:

```bash
LAST_SESSION_SHA=$(git log -1 --format=%H -- .claude/session-resume.json 2>/dev/null)
if [ -n "$LAST_SESSION_SHA" ]; then
  git diff "${LAST_SESSION_SHA}..HEAD" -- . ':(exclude).claude/session-resume.json' \
    | grep -E '^\+[^+]' \
    | grep -iE '(TODO|FIXME):' \
    | sed 's/^+//' | head -20
fi
```

Validate the JSON parses before it goes anywhere near a commit:

```bash
jq . .claude/session-resume.json >/dev/null || { echo "BROKEN JSON — fix before committing"; exit 1; }
```

**Before you commit, reread what you wrote for anything that shouldn't be in git:**
API keys, tokens, passwords, customer names, personal data. This file gets committed
and pushed. Anything you put in it is permanent history.

### 3. Commit

Two paths. Pick by looking at `git status --short`.

**State-only** (only `.claude/session-resume.json` is dirty):

```bash
git add .claude/session-resume.json
git commit -m "chore: save session state — <one-line summary of the session>"
```

**Work + state** (real work files are dirty too):

```bash
git status --short
git diff --stat
git add [specific work files] .claude/session-resume.json
git commit -m "[conventional commit message describing the work]"
```

Stage **specific files**, never `git add .` — that is how secrets and junk get
committed by accident. Decide the commit message yourself in conventional-commit
format (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`).

### 4. Push

```bash
git push || {
  git fetch origin && git rebase "origin/$(git branch --show-current)" && git push
} || {
  git rebase --abort 2>/dev/null
  echo "  push failed — could not rebase automatically. Commit stays local; do NOT force-push."
}
```

The retry handles the common case where something else pushed to the branch first.
**Never force-push.** On a rebase conflict, abort, say so, and leave the commit local.

If the repo has no remote, the push fails harmlessly — the commit is still saved.

### 5. Summary

Two lines. That's it.

```
Commit: <SHA> — <one-line summary>
Resume: /continue next session
```
