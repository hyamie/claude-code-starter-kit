# Claude Code Starter Kit

A status line, four hooks, and two commands that together enforce one habit:
**every session ends with a saved handoff, and every session starts by reading it.**

That is the whole idea. Claude has no memory between sessions. If you do not write
down what happened, the next session starts from zero and you spend the first
twenty minutes re-explaining your own project to it.

## Install

```bash
git clone https://github.com/hyamie/claude-code-starter-kit.git
cd claude-code-starter-kit
./install.sh
```

Then restart Claude Code.

Requires `jq` and `git`. Re-running the installer is safe: it backs up your
`settings.json`, and it will not create duplicate hook entries.

Preview without changing anything: `./install.sh --dry-run`

### One setting you might need to change

`statusline.sh` assumes a **1M-token context window**. If you are not on a 1M plan,
open `~/.claude/statusline.sh` and change the first setting:

```bash
CTX_SIZE=1000000    # change to 200000 if you are not on a 1M context window
```

Getting this wrong is not cosmetic. On a 200k plan left at 1M, the bar shows ~15%
when you are actually at 75% and about to get auto-compacted, which hides the exact
thing it exists to warn you about.

## What you get

### The status line

```
my-project:main │ ████████░░░░░░░░░░░░ 187k/1000k 🔥
```

Repo, branch, a context bar, your token count, and a warning icon.

The bar is coloured by **absolute tokens**, not percentage. This is deliberate.
Claude's attention degrades at roughly fixed token counts no matter how large the
window is — 300k tokens is a diluted session whether your window is 200k or 1M. A
pure percentage bar would show a 1M session as "19% full, plenty of room" while
quality is already dropping.

| Zone | Tokens | What it means |
|---|---|---|
| green | 0-100k | full quality |
| orange | 100k-200k | attention starting to dilute |
| red | 200k-400k | noticeably degraded |
| 💀 SAVE | 400k+ | save and restart |

### The hooks

| Hook | Event | What it does |
|---|---|---|
| `session-clock.sh` | SessionStart | Stamps the session clock. Prints a short banner, and tells you to run `/continue` if saved state exists. |
| `session-age-warning.sh` | UserPromptSubmit | Nudges at 2h, harder at 3h. Long sessions drift. |
| `context-size-warning.sh` | UserPromptSubmit | Warns as you approach auto-compaction, computed from your real window rather than a hardcoded number. |
| `session-wrapup.sh` | SessionEnd | If you are walking away with uncommitted changes, says so. |

Every warning fires **once per tier**, not on every prompt. They nag exactly
enough to be useful and then shut up.

### The commands

**`/done`** — verify, write `.claude/session-resume.json`, commit, push. Run it
before closing a session, and any time a hook tells you to.

**`/continue`** — read git first, then the saved state, reconcile the two, and
present where you actually are. Run it when you sit back down.

## The workflow

```
   sit down  ->  /continue  ->  work  ->  hook nags  ->  /done  ->  restart
        ^                                                             |
        +-------------------------------------------------------------+
```

Restarting a session is not a failure. It is the point. A fresh session with a good
handoff beats a six-hour session that has been compacted three times, every time.

## The session state file

`/done` writes `.claude/session-resume.json` into your project and commits it. It
travels with the repo, so it works across machines.

```json
{
  "session_date": "2026-01-15",
  "completed": ["what actually got done"],
  "in_progress": ["what is half-finished"],
  "next_steps": ["what to do next"],
  "blockers": ["what is stuck, and on what"],
  "tried_and_rejected": ["the approach we abandoned — and why not"],
  "notes": ["context not obvious from the diff"],
  "branch": "main"
}
```

**`tried_and_rejected` is the field that earns this whole setup its keep.** Without
it, every new session cheerfully re-attempts the dead end the last session already
burned an hour on. It has no way to know. This is how you tell it.

Treat that file as public: it gets committed and pushed. Never put keys, tokens, or
customer data in it.

## Notes

- `/continue` trusts **git over the state file** when they disagree. The state file
  is what a past session believed; git is what happened.
- `/done` never writes a `last_commit` field. A commit cannot contain its own SHA —
  writing it changes the tree, which changes the SHA. `/continue` derives it from
  `git log` on the state file instead.
- Nothing here kills processes. A `SessionEnd` hook that sweeps for processes by
  name cannot tell your other terminal's work from its own orphans, and will
  eventually kill something you cared about.

## Security notes

Worth knowing, since these hooks run automatically on every session and prompt.

**State lives in `~/.claude/.cache/starter-kit/`, not `/tmp`.** That is deliberate.
The filenames are derived from your project path, so in a world-writable directory
they would be predictable, and another local user could pre-create one as a symlink
pointing at a file you own. The write would follow the link and overwrite it. Under
`$HOME` (mode 700) there is nowhere for that to stand. Matters on shared dev boxes,
CI runners, and multi-user containers. Stale entries are pruned after 7 days.

**The session banner sanitises everything it prints.** `session-clock.sh` echoes
your directory name, branch, and a line from `.claude/session-resume.json`. That
state file is committed, so when you clone someone else's repo its contents are
attacker-controlled, and this output reaches your terminal before you have typed
anything. Raw escape sequences there could rewrite your terminal display and would
also enter the model's context unprompted. Everything is stripped to printable
characters and truncated first.

**Nothing here kills processes, phones home, or fetches anything.** No network
calls, no telemetry, no remote code. It is five bash scripts and two markdown files.

**Treat `.claude/session-resume.json` as public.** `/done` commits and pushes it.
Never put keys, tokens, or customer data in it.

## Uninstall

Restore the `settings.json` backup the installer printed, then:

```bash
rm ~/.claude/statusline.sh
rm ~/.claude/hooks/{session-clock,session-age-warning,context-size-warning,session-wrapup}.sh
rm ~/.claude/commands/{continue,done}.md
rm -rf ~/.claude/.cache/starter-kit
```
