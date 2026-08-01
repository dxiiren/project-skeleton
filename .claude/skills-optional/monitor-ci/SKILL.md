---
name: monitor-ci
description: Use when the developer says 'monitor ci', 'watch ci', 'watch the action', 'watch the PR build', 'is the CI passing', or after pushing a commit / opening a PR and wanting to follow the GitHub Actions run to completion — watches the CI workflow for the current branch/PR, prints each job's state, and surfaces the failing job's log.
model: sonnet
---

# monitor-ci — Watch the GitHub Actions run to completion

Follow the CI workflow end-to-end for the current branch or PR on
`github.com/dxiiren/@@REPO_SLUG@@`. [GROUND: name the workflow file(s) and their jobs,
e.g. "`.github/workflows/ci.yml` has two jobs: `quality` (Lint · Typecheck · Test · Build)
and `e2e` (Playwright)".] Report which passed, and for any failure surface the offending
job's log.

## Trigger

When the developer says any of:

- "monitor ci" / "/monitor-ci" / "watch ci" / "watch the action(s)"
- "watch the PR build" / "watch it through"
- "is the CI passing" / "did the build pass" (after a push/PR)
- right after `/commit` push or `/create-pr`, to follow the run

---

## What to Do

Use the **`gh` CLI** (or the GitHub MCP Actions tools if `gh` is unavailable — fall
back silently). All commands run from the repo root.

### 1 — Find the run for the current branch

```bash
gh run list --branch "$(git branch --show-current)" --limit 5
```

This lists recent runs with their **run ID**, status, and workflow name. Grab the
newest run ID for the CI workflow (the one triggered by your latest push/PR).

### 2 — Watch it to completion

```bash
gh run watch <run-id> --exit-status
```

`gh run watch` streams live status and blocks until the run is terminal; it prints
each job's progress and **exits non-zero if the run failed** (`--exit-status`), which
is your pass/fail signal. If you didn't capture the ID, `gh run watch` with no ID
prompts for the most recent run — pass the ID explicitly to avoid ambiguity.

> Prefer running the watch with the Bash tool's `run_in_background: true` so it keeps
> polling across turns and re-invokes you when the run is terminal — don't hand-roll a
> foreground poll loop.

### 3 — Inspect on completion

Snapshot the final per-job result:

```bash
gh run view <run-id>
```

For any **failed** job, pull its log and surface the cause:

```bash
gh run view <run-id> --log-failed          # only the failed steps' log
gh run view <run-id> --job <job-id> --log  # a specific job's full log
```

[GROUND: per-job grep hints for THIS workflow's failure modes, e.g. "quality failures →
look for the ESLint `error` lines / the typecheck TS errors / a test-runner FAIL line;
e2e failures → the failing spec name".]

---

## Reporting back

After the watch returns, report:

1. **Result** — overall pass/fail, and per job.
2. **On failure** — name the failing job + step, and paste the key error line(s) from
   `--log-failed`. Point at the root cause, don't just say "CI failed".
3. **Next step** — [GROUND: map failure kinds to this repo's fix skills/commands, e.g.
   "typecheck failure → `/fix-typecheck`; lint/format → `/lint-check`; a test failure →
   read the failing spec and fix the root cause (don't water down assertions)".]

---

## Notes / gotchas

- **`gh` must be authenticated** — `gh auth status`. If not, tell the developer to run
  `gh auth login`, or fall back to the GitHub MCP Actions tools.
- **PR vs branch runs** — a PR triggers the workflow on the PR's head branch, so
  `gh run list --branch <branch>` finds it. To target by PR, `gh pr checks <pr-number>`
  gives a compact pass/fail summary of all checks for that PR.
- [GROUND: any non-Actions checks that show up on PRs here (e.g. a deploy provider's
  check) — name them, or delete this bullet.]
- **Don't foreground-poll** — `gh run watch` in the background is the one long-running
  task here; let it self-terminate rather than looping manually.
