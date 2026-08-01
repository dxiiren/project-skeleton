# TL;DR — every doc in 30 seconds

> One section per document. Read this page first; follow a link only when you need the
> detail.

## [project-overview.md](01-overview/project-overview.md)

[GROUND: 2-3 plain-English sentences: what @@PROJECT_TITLE@@ is, what it does, its shape
(stack, build/serve model). Written in your own words after reading the code.]

---

## [getting-started.md](02-setup/getting-started.md)

Run `pwsh ./setup.ps1` once (idempotent), reopen PowerShell, then
[GROUND: the first-boot commands for this stack, e.g. `just bootstrap` + `just start`,
or `just build` + `just run`].

---

## [workflow.md](03-development/workflow.md)

[GROUND: the day-2 loop in 2 sentences: which recipes you live in, the quality gate(s),
and the commit/PR skills to use.]

---

## [deployment.md](04-deployment/deployment.md)

[GROUND: one honest sentence — e.g. "This project runs locally only; there is no CI/CD
and no deployment target." — or the real deploy story.]

---

## [commands.md](05-reference/commands.md)

Run `just` with no arguments to list every recipe. [GROUND: name the 3-4 recipes used
daily.]

---

## [project-layout.md](05-reference/project-layout.md)

[GROUND: one sentence naming the 2-3 places code actually lives.]

---

## [conventions.md](05-reference/conventions.md)

The project-family contract this repo was scaffolded under: invariants (log tags, justfile
rules, docs structure), the token system, per-stack boot-verify, and git rules.

---

## [stack-notes.md](05-reference/stack-notes.md)

Field-proven gotchas for this project's stack — read before touching setup.ps1 or the
justfile.

---

## [common-issues.md](06-troubleshooting/common-issues.md)

[GROUND: one sentence: the most common symptom + its one-line fix. Written AFTER
boot-verify.]

---

## [faq.md](07-faq/faq.md)

[GROUND: one sentence describing what recurring questions it answers.]
