---
name: continue
description: Pick up where the last session left off, grounded in git reality
---

# Continue Previous Session

Restore context from the last session's saved state, cross-checked against what
git actually says. Run this at the start of a session on a project you have
worked on before.

## Process

### 1. Ground yourself in reality FIRST

**Do this before reading the saved state.** The state file is a snapshot of what
a past session *believed*. Git is what actually happened. When they disagree,
git wins.

```bash
cat CLAUDE.md 2>/dev/null | head -60
git log --oneline -15
git branch --show-current
git status --short
```

Form your own understanding from these:
- What is this project?
- What did recent commits actually change?
- What branch are we on, and is anything uncommitted?

### 2. Read the saved session state

```bash
cat .claude/session-resume.json 2>/dev/null || echo '{"error": "no session state found"}'
```

If there is no state file, fall back to git history alone (step 1 already has it)
and say so plainly: "No saved state — working from git log."

### 3. Check for drift

Work may have happened after the last `/done` — another session, another machine,
or a session that ended without running `/done`. Find out.

```bash
LAST_SAVED=$(git log -1 --format=%H -- .claude/session-resume.json 2>/dev/null)
CURRENT_HEAD=$(git rev-parse HEAD 2>/dev/null)

if [ -n "$LAST_SAVED" ] && [ "$LAST_SAVED" != "$CURRENT_HEAD" ]; then
  echo "DRIFT: commits landed after the last saved state"
  git log --format="commit: %h%ndate: %ci%nmessage: %s%n%b%n---" "${LAST_SAVED}..HEAD"
else
  echo "No drift — saved state matches HEAD."
fi
```

The commit that last touched `session-resume.json` **is** the last `/done` commit.
Don't look for a `last_commit` field in the JSON; it cannot exist (a commit cannot
contain its own SHA).

If there is drift: read those commit messages, fold that work into your
understanding, and tell the user: *"State is from [date], but [N] commits landed
since. Looks like [summary]."*

### 4. Weight the state by age

Compute how old `session_date` is.

- **Under a week:** trust it as current.
- **Over 90 days:** treat the whole file as *historical context, not current truth*.
  Say so explicitly, and lean on git and the files over the stored fields.

### 5. Present the summary

```markdown
## Project State

### What this is
[1-2 sentences from CLAUDE.md]

### Right now (from git)
- Branch: [branch]
- Uncommitted: [count, and what]
- Recent commits: [summarize the last 3-5]

### Last saved session ([date])
- Completed: [list]
- In progress: [list]
- Next steps: [list]
- Blockers: [list, omit if empty]
- **Tried and rejected — DO NOT re-attempt:** [list, omit section if empty]

[Note any place the saved state conflicts with git. Git wins.]

### Recommended next action
[One specific thing, with why]

Ready to go, or something else?
```

**`tried_and_rejected` is the field that earns this command its keep.** It exists
specifically to stop the next session from re-attempting a dead end that a past
session already burned time on. Read it before proposing anything. Do not
re-attempt anything listed there unless the user explicitly overrides.

### 6. Stop and wait

Do not start working. Present the summary and wait for the user to confirm or
redirect.
