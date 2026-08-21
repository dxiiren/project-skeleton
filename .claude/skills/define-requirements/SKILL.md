---
name: define-requirements
description: "Use at the START of a new project or a major new capability - when the developer says '/define-requirements', 'new project', 'write the spec', 'do discovery', 'BRD/PRD/FSD/TDD', 'requirements pipeline', or describes something they want built when no spec exists yet. Interrogates round by round while background research agents work in parallel, then writes the five staged documents (Discovery -> BRD -> PRD -> FSD -> TDD) into .docs/00-requirements/ with dated research appendices, and hands off to /audit-docs before any code is written."
model: opus
---

# define-requirements - From a fuzzy idea to a build-ready spec

Turn "I want to build X" into a **five-document pipeline a builder cannot misread**:
Discovery -> BRD -> PRD -> FSD -> TDD, plus dated research appendices and an audit trail.

The output is not documentation for its own sake. It is the artifact that makes an autonomous
build possible: `/define-goal` points its work-list at these docs, and the FSD/TDD are what a
fresh instance reads at 3am when nobody is awake to answer a question. **Every ambiguity left
here becomes a wrong decision made unsupervised later.**

## Trigger

- `/define-requirements` - "define requirements" - "write the spec" - "do discovery"
- "new project" - "I want to build {X}" with no spec in the repo
- "BRD" / "PRD" / "FSD" / "TDD" / "requirements pipeline"

## What you produce

```text
.docs/00-requirements/
  README.md              # tracker: stage table, product statement, success bar, revision history, audit pointer
  01-discovery.md        # raw material: pains, goals, constraints, decisions, MoSCoW draft
  02-brd.md              # the WHY: problem, objectives, success metrics, scope, budget, timeline, risks, assumptions
  03-prd.md              # the WHAT: persona, locked decisions, MoSCoW final, user stories + acceptance criteria
  04-fsd.md              # how it BEHAVES: screens, pipelines, field specs, business rules, state machines, error states
  05-tdd.md              # how it is BUILT: architecture, stack, schema, components, security/NFR, tests, build plan, decisions
  research/              # dated snapshots from the background agents (competitors, APIs, domain, integrations)
  audits/                # the audit trail (written by /audit-docs)
```

## The five-stage law

Each stage answers exactly one question. A stage may **refine** what came before; it may never
**contradict** it. When a later stage overrides an earlier decision, the earlier document gets
an inline `[superseded - see X]` note the same day - never a silent divergence.

| Stage | Question | Owner voice | Fails when |
| --- | --- | --- | --- |
| Discovery | what is really needed? | the stakeholder | it records answers nobody was asked for |
| BRD | why does this exist? | the sponsor | success is unmeasurable, or the metric is wrong |
| PRD | what gets built? | the product owner | acceptance criteria are untestable adjectives |
| FSD | how does it behave? | the analyst + QA | an edge case has no defined outcome |
| TDD | how is it built? | the engineer | the schema cannot store what the FSD requires |

## Golden rules (each one paid for by a real defect)

1. **Never write a stage from half-answers.** Interrogate in rounds until that stage's own
   questions are closed. A document written from guesses reads authoritative and is wrong.
2. **Research runs in parallel with interrogation.** Launch the background agents in ONE
   message before the first question round - they research while the developer answers.
   Always set `model: opus` or `sonnet` explicitly on every agent.
3. **One fact, one home.** Every number - a threshold, a window, a cap, a formula - is
   authoritative in exactly ONE document. Everywhere else cites it. Two homes means two truths
   the moment either changes.
4. **Machine-checkable beats prose.** A "confirmation condition" is a grammar with typed
   parameters, not a sentence. Statuses are an enum written once. Thresholds are formulas with
   units and a rounding rule. If QA cannot write a test from it, it is not specified.
5. **Prove the success metric arithmetically.** State the metric, then compute the outcome it
   implies under the system's own mechanics. A bar that can be met while the goal fails is
   worse than no bar. (Real catch: a "50% win rate" target that arithmetically equalled zero
   profit under the documented trade lifecycle.)
6. **Snapshots stay snapshots.** Research appendices are dated and never rewritten to match
   later decisions - they get a supersession pointer at the top instead, so nobody builds the
   architecture that was rejected.
7. **Audit before build.** Run `/audit-docs` when the pipeline is drafted, fix, then re-verify.
   Fix passes introduce their own contradictions - assume it.

## Procedure

### A. Kickoff - classify in one screen

Ask with `AskUserQuestion` (max 4 questions per round; the first option carries your
recommendation and is labelled "(Recommended)"):

- **Domain** - what the thing actually is, in the developer's terms.
- **Product type** - its shape (tool / service / platform / automation / analysis).
- **Users** - just the developer, a small group, or paying customers (this drives auth,
  billing, support and ops scope more than any other answer).
- **Ambition** - weekend MVP / solid v1 / serious product / still exploring.

React to the answers before the next round. Never open with a wall of questions.

### B. Fan out research - immediately, in the background

Spawn the agents in a single message, each with an explicit model, each returning **raw
structured findings** (tables, bullets, URLs) rather than prose. The four that earn their keep
on almost every project:

1. **Competitor / prior-art landscape** - what exists, what it costs, what users complain
   about, and the gap a bespoke build can exploit.
2. **Data / API feasibility** - the concrete sources, their real current limits, and what the
   likely stack can actually reach. Verify pricing and free tiers; blog-era numbers are stale.
3. **Domain knowledge** - the vocabulary, formulas, conventions and known failure modes of the
   field. This is where the FSD's definitions come from.
4. **Integration / tooling reality** - libraries, MCP servers, SDKs: maturity, maintenance
   status, and the traps (platform requirements, single-owner constraints, auth flows).

Write each result verbatim to `research/0N-{topic}.md` with a dated provenance header. Prompt
templates: [`references/interrogation-guide.md`](references/interrogation-guide.md).

### C. Interrogate - one theme per round

Keep asking until the current stage's questions are closed. Themes, in order:

- **Pain and goal** - what is broken today; what "good" looks like concretely.
- **Trigger, inputs, outputs** - when the system acts, on what, producing which artifact.
- **Authority and scope** - who decides (the human, the system, a fixed rule set), and what is
  explicitly out of scope.
- **Success, budget, timeline** - the pass/fail bar, the running-cost ceiling, the date.
- **Behavior edges** (before the FSD) - tie-breaks, expiry, ambiguity, concurrency, failure
  modes, what happens when a dependency is down.
- **Build reality** (before the TDD) - runtime, storage, hosting, what the developer already
  knows, what must be reused from an existing repo.

Answers may arrive mid-round or contradict an earlier one. Absorb it, restate the delta in one
line, continue - never silently drop a changed decision.

### D. Write the stage - then decide whether it is closed

Write each document from [`references/stage-templates.md`](references/stage-templates.md). A
stage is finished only when:

- [ ] Every section is filled, or explicitly marked not-applicable with one line of why.
- [ ] Its open questions are enumerated and routed to a named later stage.
- [ ] Every number it introduces has a unit and exactly one home.
- [ ] It links previous/next and carries a status header.
- [ ] Anything over ~100 lines carries a table of contents.

Update the tracker README after each stage. **You** decide when a stage is closed - do not ask
the developer to approve prose they have not read; ask them the questions whose answers you
still need.

### E. Audit - before anyone writes code

Run `/audit-docs` over the finished pipeline. Apply its findings, then re-verify - a fix pass
routinely introduces new contradictions. Record the trail under `audits/` and bump the revision
history in the tracker README.

### F. Hand off

State plainly: what exists, what the success bar is, what is deliberately unresolved. Then
offer the two real next actions - commit the pipeline (`/commit`), or turn it into an
autonomous build (`/define-goal`, whose work-list should mirror the TDD's build plan).

## Anti-patterns

- Writing the BRD before the research lands - the "why" ends up justifying a guess.
- Asking the developer to review a document instead of asking the question you actually need.
- A metric with no arithmetic behind it ("be profitable", "be fast", "high confidence").
- Prose where an enum belongs: three documents, three spellings of one status, and a builder
  who invents a fourth.
- Restating a threshold in a second document "for convenience" - now they drift.
- Rewriting a research appendix to match a later decision, erasing the evidence trail.
- Declaring the pipeline done without an independent audit, or accepting the audit's own
  "resolved" claims without checking the text.
- Marking a stage complete while its open questions have no downstream owner.

## References

- [`references/interrogation-guide.md`](references/interrogation-guide.md) - question banks per
  theme, research-agent prompt templates, and how to run rounds without stalling.
- [`references/stage-templates.md`](references/stage-templates.md) - the required shape of each
  of the five documents, the tracker README, and a research appendix.

## Evolution Log

- Distilled from the dxiiren-trading pipeline (2026-08-21): a full Discovery-to-TDD spec built
  in one session with four parallel research agents and four audit layers. What that run
  proved: interrogation rounds and research fan-out are cheap; the expensive defects are
  arithmetic (a success metric that could pass while the product failed), anchor ambiguity (a
  formula whose reference price was never pinned - a 2.5x risk error), and lifecycle holes (a
  state machine that could never compute its own headline statistic). All three were caught by
  audit layers, not by drafting - hence rule 7.
