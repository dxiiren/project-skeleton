---
name: commit
description: Use when the developer says 'commit', 'save changes', or 'git commit'. DEFAULT for "commit all" / "just commit" / "commit ... bruh" (any all-in variant) -> go STRAIGHT to `git add -A` + `git commit` - NO per-file staging, NO approval wait, NO grouping/split. Only a scoped "commit only this" uses stage-by-name + approval.
model: sonnet
---

# Commit - Standardized Git Commit

## Trigger

When the developer says any of: "commit", "save changes", "git commit", "commit this".

---

## Fast path - "commit all" / "just commit" (read this FIRST)

When the developer says **"commit all"**, **"just commit"**, **"commit everything"**, or
any impatient variant, they want the whole dirty tree committed NOW - not a curated
release. In this mode:

1. **Do NOT over-analyze.** Do NOT launch a file-grouping subagent, do NOT read every diff,
   do NOT split into tidy per-area commits unless they explicitly ask to scope it. The
   standing rule: _"commit all = literally everything in the tree; only scope when I say
   'commit only this.'"_ The analysis IS the friction being complained about.
2. Run **Step 0** (clear stale lock), then go straight to `git add -A` -> `git commit`
   with ONE sensible Conventional Commits subject for the whole change. (Use `git add -A`
   here, not per-file staging - the one case that anti-pattern is intentionally waived,
   because everything was asked for. Still never commit `.env*`/secrets/`.mcp.json` - do a
   2-second `git status` scan and exclude only those.)

Then jump straight to the **Commit** step below. Skip the grouping/approval dance.

For a scoped or careful commit ("commit only this", "commit the docs part"), ignore this
fast path and follow the full pipeline below.

---

## Step 0 - Pre-flight: clear a STALE index.lock (BLOCKING, run first)

Windows file-handle quirks can orphan a `.git/index.lock`, which then blocks all staging with
`fatal: Unable to create '...index.lock': File exists`. Clear it **only when no git process
is alive** - removing it while a git op is in flight corrupts the write.

```bash
LOCK=$(git rev-parse --git-path index.lock)
if [ -f "$LOCK" ]; then
  if tasklist 2>/dev/null | grep -qE '^git\.exe'; then
    echo "ABORT: a git process is running - do NOT remove $LOCK (would corrupt the in-flight write)"
    exit 1
  fi
  rm -f "$LOCK" && echo "Cleared stale lock: $LOCK"
fi
```

If the `ABORT` line prints, STOP and tell the developer a git process is actually running -
do not force-remove.

## Step 1 - Inspect the tree

Run `git status --porcelain` and read the staged/unstaged diff. From the changed paths
infer a Conventional Commits **type** and **scope**:

| Changed paths                             | scope     |
| ----------------------------------------- | --------- |
| [GROUND: one row per source area of THIS repo (e.g. `src/`, `app/`, the main source files) -> a short scope name] | [GROUND] |
| `justfile`, `setup.ps1`, `.gitignore`     | `tooling` |
| `.docs/`, `README.md`, `*.md`             | `docs`    |
| `.claude/skills/`                         | `skills`  |
| `.claude/` (settings, hooks, memory)      | `claude`  |
| `.mcp.json.stub`                          | `mcp`     |

## Step 2 - Draft the message

`<type>(<scope>): <description>` - imperative mood, lowercase after the colon, no trailing
period, subject <= 72 chars. Add `!` and/or a `BREAKING CHANGE:` footer for breaking
changes. If the type is ambiguous, ASK the developer - never guess.

---

## Gate / Approval - SCOPED commits ONLY ("commit only this")

> These steps apply ONLY to a scoped/curated commit. For **"commit all" / "just commit" /
> any all-in variant, the Fast path at the top WINS** - skip stage-by-name and approval; go
> straight to `git add -A` + `git commit`.

1. **Refine the description** from the actual diff (imperative, concise, no period).
2. **Stage by name** - `git add path/to/file ...`. **Never** `git add -A`/`.` here. Exclude
   `.env*`, secrets/tokens, `.claude/settings.local.json`, `.mcp.json`,
   `.claude/workspace/`, and [GROUND: this repo's git-ignored build/runtime artifacts,
   e.g. `out/`, `dist/`, a generated report file - list them].
3. **Present for approval.** Show the staged files + the draft message and WAIT for an
   explicit "yes" / "go" / "looks good". Do NOT commit without approval.
4. **Commit** via a HEREDOC for clean multi-line formatting. Confirm with
   `git log --oneline -1`.

### git commit safety

- **NEVER pipe `git commit` in an `&&` chain** with a following push/log. Run the commit on
  its own, check `$?` and `git log -1`, THEN push. A chained commit that fails leaves the
  chain in a confusing half-state.
- **Never amend** a previous commit - always a new commit.
- [GROUND: state this repo's hook reality. Kit default: "This repo has no commit hooks
  (no pre-commit framework, no commitizen) - the Conventional Commits format is enforced
  by discipline, not tooling. Get it right anyway." If the project HAS hooks, describe
  them and what blocks a commit.]

### Quick reference

```
<type>(<scope>): <description>
type:  feat, fix, refactor, perf, test, docs, style, build, chore, revert
scope: [GROUND: the scope names from the Step 1 table]
```

---

## Anti-Patterns

- **Never** commit without approval - EXCEPT the developer saying "commit all" / "just
  commit" IS the approval (Fast path); don't re-ask.
- **Never** `git add -A`/`.` on a scoped commit - stage by name. Exception: the "commit all"
  Fast path (still exclude `.env*`/secrets/`.mcp.json`).
- **Never** launch a file-grouping subagent or split into per-area commits on a "commit all"
  - that over-analysis is the #1 friction; just `add -A` + commit.
- **Never** auto-commit after a fix - the developer says "commit" first.
- **Never** pipe `git commit` in an `&&` chain before a push - check `$?` + `git log -1`.
- **Never** add Co-Authored-By lines or "Generated with Claude Code" / session-link footers
  to the message (per CLAUDE.md) - output reads as the owner's own.
- **Never** commit `.env*`, secrets, API keys, `.claude/settings.local.json`, or `.mcp.json`.
- **Never** amend a previous commit - always create a new one.
- **Never** guess the commit type - if ambiguous, ask.
- **Never** remove `index.lock` while a git process is alive (Step 0).

## Evolution Log

- Shipped with the project-skeleton kit: same fast-path / scoped-path split and stale-lock
  preflight proven across the stamped dxiiren repos. `/ground-project` resolves the
  `[GROUND: ...]` rows (scope table, artifact excludes, hook reality) against this repo.
