# Owner working style — playbooks and conflict log

> The invariants live in the root `CLAUDE.md`. This page holds the longer detail behind them. It is
> project-agnostic and public-safe: no hosts, accounts, tickets or personal data.

## Contents

1. [Bug-hunt playbook](#1-bug-hunt-playbook)
2. [Fleet and monitoring detail](#2-fleet-and-monitoring-detail)
3. [Build-quality playbook](#3-build-quality-playbook)
4. [Merge and CI hygiene](#4-merge-and-ci-hygiene)
5. [Safety extras](#5-safety-extras)
6. [Reports and docs](#6-reports-and-docs)
7. [OS and tooling traps](#7-os-and-tooling-traps)
8. [Conflict log](#8-conflict-log)

## 1. Bug-hunt playbook

Learned the hard way: one hunt ran about 50 rounds without reaching zero and burned a lot of tokens.

1. **Agree the stop rule before round 1**, in writing: e.g. "zero high or medium, lows logged". No stop rule,
   no hunt.
2. **Hard cap of 3 rounds** per hunt. Round 4 needs the owner's go and a reason.
3. **Changed areas only.** Run a hunt after a large feature or monthly, not continuously.
4. **Close classes, not instances.** One bug = find its class, fix the class, add a permanent test.
5. **After two failed rounds on the same component, redesign it** (fail-closed allowlist) instead of patching.
6. **No low-severity churn.** Log lows; do not loop on them.
7. One owner per file; parallel agents never edit the same file. Verifier checks the EXACT final sha live.
8. Read production behaviour (logs, live pages) as evidence, not just the code.

## 2. Fleet and monitoring detail

- Watchdog checks per agent: its own worktree, scratch dir, dev-server/engine ports, pushed branch. Flag
  SILENT after 5 min of no files for short tasks; 20 min of silent transcript for long ones. A check on a
  scratch folder alone misses dead agents.
- Machine health beside file checks: CPU, free RAM (keep a floor, e.g. 2.5 GB), orphan or stuck processes.
  Stuck helper processes starved gates for days once. Run the repo's process-doctor recipe before a full gate.
- Shared test/suite lock: the deploy candidate's gate takes it first; side jobs (benchmarks, tooling) never
  take it while a deploy candidate is pending. Check the holder before quoting any ETA.
- Never batch parallel work so one slow item blocks the rest. Count progress from stamps only the owning
  agent writes, not from file mtimes or counts another process can inflate.
- A fan-out agent's result is FINAL only when its completion notification arrives.
- Unattended runs (owner asleep): before leaving, prove each stage advanced; never pipe a
  process-launching command into a `while read` loop; put a hard stop and clock time on the run.
- Report numbers from the CURRENT code or sheet, never a stale run; spot-check every heuristic; give agents
  a hard "done = X, then merge" stop.
- Decide model/tier by task for skills: sonnet floor, deep reasoning only where needed; subagents are
  always sonnet (see root `CLAUDE.md`). No haiku.
- Small models skip tools often: resolve deterministic intent in code, not by strengthening the prompt.
- Headless mode (`claude -p`) is for mechanical batch jobs: scope `--allowedTools`, always `| tee` a log,
  forbid `push` in the prompt, hand it a FILE of work items so the run is resumable and countable.

## 3. Build-quality playbook

- Risky work gets a one-page design first: the rule, what must never happen, the attack/edge list.
- Tests come from that list: property tests for many input shapes; growth-ratio timing tests for every regex
  or loop over user or model text; the permanent leak/viewer tests stay in the suite.
- Fast checks every change: pre-commit hook, quick test subset; one full run at the end.
- Merge only when the merged tree equals the gated tree. Run the process-doctor recipe first: a starved
  machine makes a gate lie about time.
- Deploy small and often: ship any batch strictly better than production and fix forward. Never let batches
  pile up waiting for perfection.
- Local Playwright runs use the measured worker ceiling (record the number the same day you measure it).
- If a regression is hard to place, bisect in a throwaway worktree.

## 4. Merge and CI hygiene

- Before checking a CI job is correct, ask whether it needs to run at all. Merge on the REQUIRED checks;
  never wait on optional jobs.
- A change CI does not really test (laptop tooling, `.claude/`, docs, log levels, CI workflow files) gets no
  CI wait: cancel its runs and merge with `[skip ci]`.
- Never merge a base branch into (or re-run) every open PR at once if integration suites share one test-DB
  lock. Land everything bound for the base first, then update PRs once; a watchdog that cancels runs needs
  a grace period.
- Process patterns in CI scripts that run via `sh -c` wrappers self-match: write `pkill`/`pgrep` patterns in
  bracketed form (`com[.]example[.]Main`).
- Deployment environments must be self-contained: no volume mounts or paths that reference another
  environment's directory. Pull the new image BEFORE extracting config from it.
- Resolve a duplicate/merge collision by comparing the commits' intent (owner, purpose, real consumer), not
  by whichever side makes the current test pass.
- Work branches: fix once on a `fix/*` branch; never implement the same fix twice on two branches.
- Batch related fixes into ONE PR per repo (CI runner capacity is scarce). Branch-cleanup reports: one table,
  DELETE-first; an open PR is an absolute keep.

## 5. Safety extras

- UI automation on the owner's machine: target a window handle (set text / posted command), never global
  keystrokes or fixed-coordinate clicks; never `java.awt.Robot` clicks or desktop screen grabs (they land in
  whatever the owner has open and record his editor and secrets).
- Remote/container probes: always `timeout 25` and a known path; never glob or `find` over `/`; an orphaned
  probe pinned a server at 100% CPU for hours.
- Never run bulk surveys (hundreds of calls) through a production bridge or API; it slowed the terminal and
  health checks timed out.
- Test lockout protections (fail2ban, rate limits, firewall) with a short ban or a whitelist first, from the
  owner's own IP.
- Settings written outside the app (from a shell) are invisible to the running app until restart or a page
  save; prove the live value, not the row.
- Never kill a port's owner blind; Docker Desktop proxies app ports. Never `docker prune` on the owner's
  laptop; remove only what you created, by exact name. A hook blocking a command is a reason to split or
  rethink it, never to bypass it.
- A task that "needs a real window" is usually automatable headlessly (spawn, observe, terminate it
  yourself).
- When the owner deletes files in his own workspace folder, ask before restoring them.

## 6. Reports and docs

- Per-status breakdowns, not only totals. If there is no screen or evidence for a row, say so; never show a
  plausible-but-wrong one. Status and evidence columns derive from ONE source.
- Ticket/PR references carry their URL: markdown link in `.md`; raw URL in `.txt`/email (numbered list, two
  lines per item, no space-padded tables, which break in proportional fonts and on mobile).
- Management or exec documents: facts only, exactly the thing asked for, no recommendation, hedging, or
  cliche framing. Emails: match the owner's sent-mail voice; read his Sent folder first.
- Every `.md` is action-first with tables/mermaid over prose and long prose collapsed in `<details>`.
- Training decks: settle the audience first; Who/What/When/Where/Why/How per concept; add pictures.
  Split `[COPY]` (rendered verbatim) from `[BUILD]` (never rendered) in deck prompts. Diagrams are native
  editable shapes, not flat images; verify the file opens in the real application.
- A deliverable-looking file (zip, evidence pack) must not exist in the deliverable folder before its gate
  passes; prove build scripts in scratch.
- "Update everything" = the spec (rev bump + deviations entry), dependent citations, and every rendered or
  exported copy of a changed doc (diagram `.png`, `.docx`, sheets, ledger).
- Record experiments and investigations in `.docs/` with method and result; chat and scratch folders are
  not a record. Machine setup ships as a one-command recipe plus docs.
- Show a text mock-up before building a developer-tool UI; the owner decides in one message.
- Never write reports as published Artifacts for this owner; local `.html` or `.md` files in the repo.

## 7. OS and tooling traps

- Windows PowerShell 5.1 has no `&&` and `2>&1` paints stderr red (use `2>$null`); justfile recipes need
  `[windows]`/`[unix]` splits. Setup scripts print both `pwsh` and `powershell -ExecutionPolicy Bypass`
  run lines.
- Shell scripts must be LF before shipping to Linux; ship from the git index, not the Windows working tree.
  Moving files between branches on Windows can drop the exec bit; compare modes, not just blob ids.
- Claude Code: a `PostToolUse` hook that exits 0 cannot talk to the model (output dropped); use it for side
  effects, or use `SessionStart`/a skill. Anchor hook commands to the git root.
- A browser blocks some ports (e.g. 6000, X11). After `git pull` adds dev dependencies, reinstall before
  type-checking.
- Long backtests/batches: run from your own background shell (not WMI), split to fit the background-task
  cap, and judge liveness by the whole process tree's CPU. Never launch the served app from a shell the
  harness can reap. For heavy batch compute, consider a memory-capped container on a spare server.
- Playwright MCP writes page snapshots into the working directory; a snapshot after a login form stores
  the password in cleartext. Mask or delete.
- Prefer non-global installs (`npx`); ask before any machine-wide install.
- Distinguish what a build script COULD do from what the CI job config DOES; read the job config before
  claiming a profile is active. Verify a build contains a change by searching for string literals from the
  diff, not file timestamps.
- Every command you hand the owner is run by you first, exact string.
- Use `curl.exe` (not the PowerShell alias) and mind a local CA with no CRL.

## 8. Conflict log

Rules that disagreed across the owner's projects, and how each was resolved (newest dated rule wins).

- **Subagent model.** Opus-only (early) -> "opus or sonnet by task" (2026-09-26) -> sonnet only, never Opus,
  never Fable (2026-10-04). Resolved: sonnet always, set explicitly on each call; an agent file's own
  `model:` does not override.
- **Cost.** An earlier note said cost is not a concern; superseded 2026-10-14 (the owner is on flat
  subscriptions). Resolved: cost matters; the cost guard applies.
- **"Fix every known issue unasked" vs "stay inside the literal ask".** Newer rule (cost guard,
  2026-10-10) wins where they collide: fix findings inside the ask; stop and ask once when a long gate
  fails for environment/data reasons or the work grows beyond the ask.
- **Commit author email.** One project hard-coded a personal address, another said "pick by remote".
  Resolved: decide from `git remote get-url origin` (work Gitea -> the work address kept in the owner's
  user-level config; anything else, GitHub included -> no `-c user.email`). No address is stored here
  because this skeleton is public.
- **Commit/deploy asks.** "Never auto-commit; wait for 'commit'" vs "an approved plan that lists commit,
  merge and deploy is the go" vs "a shared-env deploy needs an OK every time". Resolved: no commit without an
  ask or an approved plan that includes it; an approved plan covers its listed steps; shared-environment
  deploys need an explicit OK unless the repo's own docs say the recipe deploys on merge.
- **Restarting the owner's server.** "Act, do not ask, on reversible fixes" vs "never restart his dev server
  yourself". Resolved: your own processes, act; his dev server, ask unless the repo docs say otherwise, and
  ask in the same message in which you report you broke it.
- **Workflow engine.** Evaluated and rejected (2026-07-01, 2.4x cost, no quality gain) vs "workflows allowed"
  (2026-09-26). Resolved: inline subagents by default; the engine only for 15+ independent items that each
  need reasoning.
- **Main-session work.** "Use subagents liberally" vs "the main session answers the owner": heavy or waiting
  work -> subagent; quick read-only checks (seconds) and at most ~3 light calls stay in the main session.
- **Dates.** Report headings d-m-y (owner-facing), ISO in code/logs/provenance. Times to the owner in MYT.
- **Public vs private.** Anything that names the owner's employer or private infrastructure stays out of
  public repos (this one included); the work-address and host details live only in user-level or private
  config.

## 9. Sources

Distilled from the owner's user-level `CLAUDE.md`, the project `CLAUDE.md` files of his repositories
(templates, API/web/Java/PHP/video projects), and the feedback and user memories saved across those
projects. Project facts, hosts, accounts, tickets and personal data were left out on purpose.
