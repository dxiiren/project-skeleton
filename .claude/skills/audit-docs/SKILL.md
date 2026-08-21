---
name: audit-docs
description: "Use when the developer says '/audit-docs', 'audit the docs', 'are the docs up to standard', 'review my spec', 'check the requirements', or before any build starts from a written spec - runs layered adversarial audits (whole-set cross-check, then per-document deep dives) with fresh agents that never see the author's reasoning, verifies every claimed fix in the actual text, and records the trail in audits/ so the fix history cannot drift from what the documents say."
model: opus
---

# audit-docs - Adversarial layered audit of a document set

A specification is not done when it is written. It is done when an adversary who never saw the
author's reasoning has tried to break it and failed. This skill runs that adversary - in
layers, with a fix loop that assumes its own fixes introduce new defects.

Use it on any set of documents that a build will depend on: a requirements pipeline, an
architecture set, a runbook collection, a migration plan.

## Trigger

- `/audit-docs` - "audit the docs" - "are the docs up to standard" - "review my spec"
- Automatically at the end of `/define-requirements`, before any code exists.
- After any substantive documentation change that a build relies on.

## The law this enforces

1. **Fresh eyes only.** An auditor must NOT be the author and must not receive the author's
   reasoning - only the documents, the domain context, and what earlier rounds already fixed.
   Reviewing your own text finds typos, not contradictions.
2. **Findings must be provable.** Every finding names a file and section, states the defect,
   and prescribes a one-line fix. "This feels underspecified" is not a finding.
3. **A fix pass is a change, and changes get audited.** Never stop after applying fixes. The
   re-verify round exists because fixes reliably introduce fresh contradictions (in the run
   this skill came from, a fix pass introduced one new blocker and seven contradictions).
4. **Claimed resolutions are verified in the text**, not trusted from a log. Audit the audit.
5. **Report what was NOT verified.** A clean verdict with an unstated gap is a lie with good
   posture.

## The four layers

Pick the depth the situation deserves; layers 1-2 are the minimum before a build.

| Layer | What it does | When |
| --- | --- | --- |
| 1. Cross-set | ONE agent reads every document: contradictions between files, traceability gaps, arithmetic, internal logic, stale references | always |
| 2. Re-verify | The SAME agent re-reads after the fix pass: is each finding actually resolved in the text, and did the fixes introduce new defects | always (fixes cause regressions) |
| 3. Targeted confirm | The same agent checks ONLY the round-2 fixes | when round 2 found blockers |
| 4. Per-document | ONE agent per file, each with a document-specific lens, hunting NEW defects at full depth | before a build, or when the developer asks for thoroughness |

Layer 4 is where the deepest defects surface, because each agent reads one file completely
instead of sampling many. Run all its agents in a single message, each with an explicit model.

## Procedure

### A. Establish the target and the baseline

List the documents in scope. Read any existing audit log so the new round hunts NEW defects
rather than re-reporting resolved ones. Note the domain context each auditor needs (what the
product is, the stack, the platform, the constraints) - an auditor without it reports noise.

### B. Dispatch

Give every auditor: the file(s) to read, the domain context, **what earlier rounds already
fixed**, the audit dimensions for its lens, and the exact output format. Prompt templates and
the per-document lenses: [`references/audit-protocol.md`](references/audit-protocol.md).

Always set `model: opus` or `sonnet` explicitly. Auditors are read-only - they never edit.

### C. Triage and fix

- **BLOCKER** - the spec is wrong or unbuildable as written. Fix now.
- **MAJOR** - a real defect that will cost a build cycle. Fix now.
- **MINOR** - imprecision, staleness, formatting. Fix if cheap, else record the decision.

Apply fixes exactly as prescribed unless the prescription is itself wrong - in which case say
so plainly and fix it your way, in one line. Where a finding touches a decision the developer
owns (a metric, a schedule, a scope boundary), ask before changing it; everything technical is
yours to fix.

### D. Re-verify - mandatory

Send the same agent back over the revised text: confirm each finding is genuinely resolved
(cite the section that resolves it), and hunt for defects the fix pass introduced. Repeat until
a round returns only minors, then apply those and stop.

### E. Record the trail

Write `audits/{date}-{topic}.md`: verdict per round, every finding with its resolution, the
counts (which must reconcile with the rows actually listed), and the honest caveats - what was
applied without independent re-verification, what a round did not sample. Add a revision row to
the document set's tracker/README, and state the standing rule: **substantive changes re-run an
audit before a build depends on them.**

### F. Report

Lead with the verdict and the sharpest finding, not the process. Name the caveats. If the set
is genuinely clean, say so plainly and say what "clean" was measured against.

## Verdict vocabulary

- **CLEAN / SHIP** - nothing above MINOR survived verification.
- **PASS-WITH-FIXES** - real findings, all localized, no redesign implied.
- **FIX-FIRST / FAIL** - at least one blocker: the set cannot be built from as-is.

Findings are reported as: `[SEVERITY] file §section - the defect - prescribed fix.`

## Anti-patterns

- Auditing your own work in the same context that wrote it.
- Telling the auditor what the author intended - it primes them out of the finding.
- Accepting "resolved" from a log without opening the file.
- Stopping after the fix pass because the fixes "were simple".
- A count chain in the log that does not reconcile with the listed rows.
- Rewriting a dated snapshot to match a later decision instead of marking it superseded.
- Reporting a clean verdict while a whole layer was skipped, unsaid.
- Letting auditors edit files - findings and fixes stay separate roles.

## References

- [`references/audit-protocol.md`](references/audit-protocol.md) - the auditor prompt
  templates, the per-document lenses, the audit dimensions, and the audit-log format.

## Evolution Log

- Distilled from the dxiiren-trading requirements audit (2026-08-21): four layers over eleven
  documents. Round 1 returned FAIL on a full-looking spec - six blockers including an inverted
  formula, a sizing rule with no defined anchor (a 2.5x risk error), a state machine that could
  not compute its own headline statistic, and a success metric that could pass while the
  product failed. Round 2 proved rule 3: the fix pass itself introduced a new blocker and seven
  contradictions. Layer 4 then found eight more blockers that the whole-set rounds had missed,
  because a per-file agent reads what a cross-set agent samples. The meta-audit of the audit log
  caught the log over-claiming its own count chain - hence rules 4 and 5.
