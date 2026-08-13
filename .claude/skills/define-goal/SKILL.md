---
name: define-goal
description: "Use when the developer says '/define-goal', 'define a goal', 'write a goal file', 'set up an autonomous goal', or 'make a goal for /goal to run' - interactively interrogates the developer round by round until the objective is 100 percent unambiguous (never writing early), then writes a stop-proof {topic}-goal.md (checkable stop condition, fully enumerated work-list with terminal statuses, guardrails, resume protocol) into .claude/checklist/{topic}/ that the built-in /goal command runs autonomously in a fresh Fable instance."
model: opus
---

# define-goal - Author a stop-proof goal for autonomous `/goal` runs

Turn a fuzzy intention into a **stop-proof `{topic}-goal.md`** - a spec so tight that a fresh
instance running the built-in **`/goal`** command works through it to genuine completion and
**cannot be talked into finishing early**.

This skill is the **authoring half** of a two-part workflow:

1. **`/define-goal`** (this skill, interactive) -> interrogates you until the goal is airtight, then
   writes `{topic}-goal.md`.
2. **`/goal`** (built-in Claude Code command, autonomous - usually a fresh **Fable** instance) ->
   _"set a completion condition and keep working across turns until it's met."_ It **re-reads the
   goal file on every Stop-evaluation**, so the file's own text is what decides whether it may stop.

The whole point is the file. A vague file lets the agent quit with work undone (see the failure
story in "The stop-proof law"). This skill exists so every goal is stop-proof **by construction**.

## Trigger

- `/define-goal` or `/define-goal {topic}`
- "define a goal" - "write a goal file" - "set up an autonomous goal"
- "make a goal for /goal to run" - "I want to run something overnight"

## What you produce

One file: `.claude/checklist/{topic}/{topic}-goal.md`, built from the exact template in
[`references/goal-template.md`](references/goal-template.md). Then you print the `/goal` invocation
that runs it. You do **not** run the goal yourself - that happens in a separate instance.

The running goal writes a **companion** beside it: `.claude/checklist/{topic}/{topic}-state.jsonl`,
one line per iteration. That file - not the conversation - is what a fresh instance resumes from
after a crash, so the goal file must define what each line records and what counts as movement.
You author the goal file; `/goal` creates the ledger on its first iteration.

## The golden rule

**Do NOT write the file until the developer has EXPLICITLY confirmed the assembled spec is 100%
correct and complete.** The interrogation loop is the whole value - a goal written from half-formed
answers is a goal that fails at 3am. Keep asking. Only "confirmed" / "100%" / "that's it" / "ship
it" ends the questionnaire.

This skill does **not** use plan mode - the confirm-until-100% conversation _is_ the review gate.

## Procedure

### A. Kickoff (one screen)

Ask the developer for the one-line goal, then classify - use `AskUserQuestion` for the choices:

- **Goal type** - unattended sweep - audit - migration/refactor sweep - bugfix batch - research -
  other. (Picks the question bank in `references/interrogation-guide.md`.)
- **Attended or unattended?** Unattended (overnight, nobody answers questions) demands stricter
  guardrails and gate-overrides; attended can defer some decisions to you live.
- **Which instance runs it?** Usually a fresh Fable instance via `/goal`. Note the model so the goal
  file's effort/verbosity expectations match.

### B. Interrogate - extract the stop-proof essentials

Work the themes below one at a time (`AskUserQuestion` for discrete choices, free-form for
specifics). Do not batch them into one wall of questions - one theme per round, react to each
answer, drill in where an answer is vague. The per-type probes and the answer->section map live in
[`references/interrogation-guide.md`](references/interrogation-guide.md).

1. **Mission & success** - the single objective in 1-2 sentences; what "success" concretely
   delivers. If you can't state success as something checkable, keep asking.
2. **Work list & discovery** - is the work a **known enumerable list**, or must the agent
   **discover it via a sweep first**? What is one unit of work? Rough count? (This becomes the
   per-row status table, or a "Goal-0 discovery sweep" that populates it.)
3. **Definition of Done** - for ONE item, what proves it done (the per-item DoD checklist)? What are
   the allowed **terminal statuses** (e.g. `DONE` / `GAP` / `BLOCKED`)? What is the single global
   **STOP CONDITION**?
4. **Guardrails & locked decisions** - may it `git commit` / `push` / stage? May it open a PR /
   comment on GitHub, or touch any external service? Any destructive ops? What decisions are
   **locked** (do-not-relitigate)? Any **environment bootstrap** ([GROUND: this repo's bring-up +
   sanity gate, e.g. "`just start` on the assigned port" or "`just build` + `just run` both exit
   0", plus the `/lint-check` gate if relevant])?
5. **Real-blocker definition** - what counts as a _genuine_ blocker (a code fact: [GROUND: 2-3
   stack-appropriate examples - e.g. a structural error a parser proves at a line, a missing
   referenced asset/class, a hard infra failure it can't fix]) versus a banned excuse ("it's
   late", "complex", "needs a focused session")? Code-ground it.
6. **Resources** - reference files/paths, skills to follow (`/skill-name`), and where work artifacts
   - reports go.

7. **Durability & budget** — mandatory for unattended runs, worth asking on every goal. What is the
   **hard budget**: max iterations AND max wall-clock? What counts as **measurable movement** on a
   criterion, so the stall detector can tell real progress from thrashing? Who reads the **morning
   briefing**, and where does it land? These three answers fill the goal file's `Durable state
   ledger`, `Stall detection` and `Morning briefing` sections. The template ships those headings, so
   an un-interrogated goal produces them **empty** — headings with nothing behind them, which is
   worse than absent because it reads as covered. A goal with no budget has no ceiling except the
   stall detector, and a loop making tiny movement never trips it.
8. **Concurrency** — can the work-list items run **at the same time**, or must they be serial? Ask
   what would collide: two items touching the same file · a single shared server/port/DB · one
   item's output feeding another. Serial is a fine answer, but it must be a *decision* with a named
   reason, not an omission. If parallel: what batch size, and what is each subagent forbidden from
   touching? **Coupled to the ledger:** parallel items complete out of order, so the goal file MUST
   record an `item` per ledger line and resume by SET, not by "the last line". If you cannot
   guarantee that, the answer is serial.

### C. Reflect & confirm loop (the questionnaire that doesn't stop early)

Echo the **entire** assembled spec back as a structured summary (every template section, filled).
Then ask, verbatim intent:

> "Here's the complete goal as I understand it. Is this **100% correct and complete**? Point at
> anything ambiguous, missing, wrong, or under-specified - or say 'confirmed' and I'll write it."

If the developer corrects anything -> revise -> **re-present the whole thing** -> ask again. Loop
until an explicit confirmation. Never shortcut this because the goal "seems clear enough".

### D. Write & hand off

1. Confirm (or accept an override of) the path: default `.claude/checklist/{topic}/{topic}-goal.md`.
   `{topic}` is a short kebab-case slug of the mission - not "goal", not this skill's name.
2. Write the file from `references/goal-template.md`, filling **every** section (omit a section only
   when it truly doesn't apply, and say so in one line rather than leaving it blank). Save as
   **UTF-8 without a BOM**.
3. Print the handoff block - terse, one-liners (no narration paragraphs):

   ```text
   Wrote .claude/checklist/{topic}/{topic}-goal.md
   Run it in a fresh instance (Fable):
     /goal Work through @.claude/checklist/{topic}/{topic}-goal.md until the STOP CONDITION at the
     top is met. Follow every rule in it; update statuses + Run Log after each item.
   ```

## The stop-proof law (why the template is shaped the way it is)

Five pillars, distilled from a real overnight failure and its fix:

1. **An explicit, checkable STOP CONDITION.** One bold line the `/goal` evaluator can test by
   re-reading the file - "NOT complete until EVERY row has a TERMINAL status."
2. **A fully enumerated work-list with per-row statuses.** Unknown-size work gets a **Goal-0
   discovery sweep** that enumerates the list _before_ execution, plus a copy-paste Task Template.
3. **Ban "deferred" / summary-while-`TODO`.** "deferred" / "next session" / "focused session" /
   "later" are **banned as a status**, and no completion-flavoured summary may be written while any
   row is still non-terminal - a premature summary is exactly what reads as _done_.
4. **A code-grounded "real blocker".** A blocker counts only if it's a fact in the code or a hard
   infra failure - never a feeling. Everything else is worked, not skipped.
5. **A resume protocol.** Statuses/checkboxes in the file are the single source of truth (not the
   agent's memory); on every restart or context compaction, re-read the file and continue from the
   first non-terminal row; set `IN-PROGRESS` the moment an item starts.

> **The failure this prevents (13-6-2026).** An overnight `/goal` run _stopped with ~55 work rows
> still `TODO`_ - because it wrote a "Night Summary" and tagged the rest "deferred to focused
> sessions", which the `/goal` evaluator read as **complete**. The cure became these five pillars.
> Every goal this skill writes bakes them in so the same failure cannot recur.

## Anti-patterns (do not ship a goal that does any of these)

- Writing the file **before** an explicit 100% confirmation.
- A STOP CONDITION that isn't checkable ("do a good job", "finish the work") - the evaluator can't
  test it, so the agent self-certifies done.
- A work-list with **no per-row statuses**, or unknown-size work with **no discovery sweep** to
  enumerate it.
- Allowing "deferred" / "next session" as a status, or permitting a summary while rows are open.
- A blocker defined by vibes instead of a code fact.
- No resume protocol -> a compaction mid-run silently loses the place and the agent re-guesses.
- **Shipping the durability sections empty.** The template carries `Durable state ledger`, `Stall
  detection` and `Morning briefing` headings; if theme 7 was never interrogated they arrive with
  nothing behind them. Empty headings are worse than absent ones — they read as covered.
- **No hard budget** (max iterations AND max wall-clock). Stall detection only fires on *zero*
  movement, so a run making tiny movement per iteration never trips it and runs until morning.- Naming the file `goal.md` or `{skill}-goal.md` instead of a topic slug.

## References

- [`references/goal-template.md`](references/goal-template.md) - the exact output shape (fill every
  section) + field guidance + a worked example + the handoff block.
- [`references/interrogation-guide.md`](references/interrogation-guide.md) - per-goal-type question
  banks, the confirm-loop wording, and the answer->template-section map.

## Evolution Log


- **2026-08-13 — RESUME PROVEN, and the durability sections were interrogation-less.** Added the
  `Hard budget`, `Durable state ledger`, `Stall detection`, `Morning briefing` and `Concurrency`
  template sections **plus** the probes that fill them (theme 7/8 here, universal probes 9-12 in
  `interrogation-guide.md`). The template had carried three of those headings for a while with
  nothing interrogating for their content, so every goal shipped them **empty** — which reads as
  covered and is worse than absent.
  **Kill-resume is now evidenced, not asserted** (it had produced zero ledger lines ever). Proof, on
  the third attempt: headless run A spawned, `SIGKILL`-ed at ledger=8 (last item
  `audit-workflow-comments`), then a COLD run B given only the same prompt appended lines 9-14 with
  **zero duplicates**, iterations `0..13` distinct, and a **118-second gap at line 9** proving a real
  interruption. The first two attempts failed on the human-in-the-loop step, never the mechanism —
  run 1's evidence was deleted by an early cleanup, run 2's kill missed the window. Driving it with
  `claude -p ... &` + the captured PID worked first try.
  **Resume is now SET-based, not cursor-based.** Every ledger line must carry an `item`; resume =
  work-list minus every `item` seen. A cursor ("continue from the last line") silently skips work the
  moment anything runs concurrently, so `Concurrency` and the ledger change had to land together.
  **Still unverified:** `/goal`'s own Stop-evaluator (the proof used headless `claude -p`, which
  exercises the ledger protocol but not the Stop loop), and the set-based resume under genuinely
  concurrent execution.

- Shipped with the project-skeleton kit: same interrogation -> confirm-until-100% -> stop-proof
  file design and the five stop-proof pillars proven across the stamped dxiiren repos.
  `/ground-project` resolves the `[GROUND: ...]` bootstrap/evidence examples against this repo.
