---
name: pre-pr-review
description: Use when the developer says 'pre-pr review', 'review my branch', 'audit my work', or 'self review' — self-reviews the current branch's diff against this project's stack checklist before opening a PR, then saves a report to .claude/workspace/reports/pr/.
model: opus
---

# Pre-PR Review (Self-Audit)

Self-review your feature-branch diff **before** opening a PR. [GROUND: one sentence on
what this project is and therefore what the review protects (e.g. "a static report page —
catch structure/a11y/content problems", "a plain-Java CLI — catch input-handling and
output-format regressions"). If the repo has no hook/CI safety net, say so: this review is
the only gate.]

## Trigger

- `"pre-pr review"` / `"self review"`
- `"review my branch"` / `"review my work"` / `"review my code"`
- `"audit my work"` / `"audit my branch"`

## Step 1 — Branch & base

```bash
git branch --show-current
```

If on `main`: **STOP** — "You're on `main`; switch to your feature branch first."

```bash
git fetch origin main
git diff origin/main...HEAD --name-only
```

If no files changed: **STOP** — "No changes vs `main`."

Scope the review to reviewable source: [GROUND: this repo's source globs (e.g. `*.html`,
`src/**/*.vue`, `*.java`, `app/**/*.php`)]. **Exclude** `.claude/` and `.docs/`
(docs-only changes get a light read for accuracy, not this checklist). If only excluded
files changed: **STOP** — "No reviewable source changed."

Report: "Branch `{name}` changed {N} source files. Running review."

## Step 2 — Fetch the diff

```bash
git diff origin/main...HEAD -- [GROUND: the source globs from Step 1]
```

For context-dependent checks read the **full file**, not just the hunk.

## Step 3 — Run the checklist

Verify each finding against the actual code before reporting it.

[GROUND: write a 6–9 row checklist for THIS stack, in this exact table shape. Each row:
a numbered check, a default label (issue / suggestion / nitpick), and what to look for,
citing this repo's real files/conventions. Cover at minimum: correctness/structure for
the stack's primary artifact · error/input handling · naming+conventions consistency ·
new-dependency scrutiny · content/doc accuracy against the code · no debug leftovers
(TODO without follow-up, print/console debugging, leftover kit placeholder tokens).
Battle-tested examples to model on: the static stack checked HTML well-formedness,
a11y color-only signals, print layout, external deps, and content accuracy; the Java CLI
stack checked Scanner read-order vs sample-input sync, exception paths, and output-format
stability.]

| #   | Check | Label | What to look for |
| --- | ----- | ----- | ---------------- |
| 1   | [GROUND] | issue | [GROUND] |

## Step 4 — Boot check

If runnable source changed, boot-verify per `.docs/05-reference/conventions.md`:

```bash
[GROUND: this stack's boot-verify commands, e.g.
just start
curl.exe -s -o NUL -w "%{http_code}" <the app URL>
just stop
— or for CLI stacks: just build / just run (exit 0, no stack trace)]
```

Note the result in the report.

## Step 5 — Finding labels & caps

- **issue** (blocking) — fix before opening the PR.
- **suggestion** (non-blocking) — recommended.
- **nitpick** (non-blocking) — minor/optional.

Every finding must carry: the label, the `file:line`, and **WHY** it matters (not just what).
Issues: uncapped. Suggestions + nitpicks: cap at 15 total; note "{X} more non-blocking findings
omitted" if over.

## Step 6 — Present

```
## Pre-PR Review: {branch}
Branch: {branch} -> main   |   Files: {N}
Boot check: {result / skipped}

### Issues (fix before PR)
1. [path:line] Finding — why it matters

### Suggestions
2. [path:line] Finding

### Nitpicks
3. [path:line] Finding

---
{Total} findings: {issues} issues, {suggestions} suggestions, {nitpicks} nitpicks
```

Zero findings → "No issues found — branch looks clean. Ready to open the PR."

## Step 7 — Save the report

Path: `.claude/workspace/reports/pr/{branch}-{YYYY-MM-DD}.md` (replace `/` in the branch name
with `-`; overwrite on a same-day re-run). Frontmatter then the same body as the terminal
output:

```yaml
---
branch: { branch }
base: main
date: { YYYY-MM-DD }
files_changed: { N }
issues: { count }
suggestions: { count }
nitpicks: { count }
---
```

Confirm: "Report saved to `{path}`".

## Tone

Self-improvement, not a verdict from a lead. "Consider extracting…", not "You must fix…". Never
directive, never judgmental.

## Evolution Log

- Shipped with the project-skeleton kit: flow (branch gate → diff → checklist → boot check →
  labeled findings → saved report) proven across the stamped dxiiren repos. `/ground-project`
  writes the stack checklist and boot check for this repo.
