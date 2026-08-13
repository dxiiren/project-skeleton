---
name: sharpen-prompt
description: Use at the START of any request that could be read more than one way, or that says build/fix/investigate/audit/check/update without naming what proof counts as done - rewrites the request into a precise brief (objective, definition of done with live evidence, scope boundaries, execution shape) and states the assumptions made, so the work matches the intent on the first pass instead of the third. Also triggers on 'sharpen this', 'rewrite my prompt', 'what do you think I mean'.
model: opus
---

# sharpen-prompt — Turn a fuzzy ask into a brief that can only be done one way

The cost being avoided is real and measured: requests that got claimed "done" on the wrong
evidence, then needed two or three challenge rounds ("why u dont check for real chatbot",
"if i manually check still have") before the actual work happened. Each round cost a long
tool loop. **Naming the proof up front converts three rounds into one.**

## Trigger

Run this **before starting work**, not after, whenever any of these is true:

- The request could be read two ways and the readings produce **different work**.
- It says build / fix / add / investigate / audit / check / update / verify but never says
  **what proof would count as done**.
- It names a scale word — "all", "every", "the whole", "across the repos" — without a count.
- It is a repeat of something done before (a candidate for codifying, not redoing).
- The developer says "sharpen this", "rewrite my prompt", "what do you think I mean".

**Skip it** for genuinely unambiguous one-liners ("commit", "push", "what's the branch") —
sharpening those is the ceremony this skill is supposed to remove.

## The output — 5 lines, then start

Do **not** turn this into an interrogation. Print the brief, then begin immediately. The
developer reads it as you work and interrupts if a line is wrong. Blocking on confirmation
is a worse failure than a wrong assumption stated out loud.

```
SHARPENED
Objective : <one line - the outcome, not the activity>
Done when : <the specific evidence that will be pasted. Live, not inferred.>
Not doing : <the adjacent thing I am deliberately leaving alone>
Shape     : <inline | subagent fan-out | checkpointed batch>  (why, 4 words)
Assumed   : <the ambiguity I resolved, and which way I resolved it>
```

Then work. If `Assumed` was wrong, one correction beats three challenge rounds.

## Ask ONE question only when

Proceeding under either reading would be **unsafe or would waste the whole task if wrong**.
Then ask exactly one question with the two readings as options — never a list of five.
Everything else: pick the reading a careful colleague would, put it in `Assumed`, proceed.

## Writing the `Done when` line

This is the line that does the work. It must name evidence that can be **pasted**, produced
by exercising the actually-running system.

Good — each is a thing that either exists in the output or does not:

- "the app started via `just start` and the probe URL returning 200, output pasted"
- "a Playwright run showing the new value rendered on screen"
- "the raw API/CLI response showing the change at the source, not just the UI"
- "the empty / zero-row / one-character edge case tested, output pasted"
- "`RESULT: PASS` from `audit.py`, and the count matching disk"
- [GROUND: this project's own strongest proof command — its test runner's summary line,
  its build-and-run pair, or its probe URL. Name the exact line to paste.]

Rejected — none of these prove behaviour:

- "it works" / "tests pass" / "the build is green" / "the container is up"
- "the deployment is present" / "the file is on the host"
- mocked unit tests alone

If the requirement implies a scale ("all endpoints", "every repo"), the `Done when` line
carries the **number**: "all 26 events enumerated, each with pass/fail" — not "the events".

**If evidence cannot be gathered** (VPN down, host unreachable, no credentials), say
`BLOCKED: <reason>` and mark the item UNVERIFIED. Never substitute weaker evidence silently.

## Picking `Shape`

| Request looks like | Shape | Why |
|---|---|---|
| Build / fix a specific thing | inline | one coherent change; verify at the end |
| "Why is X broken" / "find where" / "is it reachable" | **subagent, report-only** | bounded exploration beats a 200-line shell log |
| "Do this for all N items" where N is large | **checkpointed batch** | an interrupted run must cost minutes, not hours |
| Something done 3+ times before | **codify it** | write/extend the skill, then run the skill |

**subagent, report-only** — dispatch with: return only (a) the 3 most likely causes ranked,
(b) exact `file:line` evidence for each, (c) the cheapest experiment that discriminates
between them. Edit nothing. Time-box ~15 tool calls. Independent probes go out as multiple
Agent calls in one message, not one after another.

**checkpointed batch** — before starting, create the progress ledger. After **each** item
append one line: `{item, status, evidence, timestamp}`. On startup read it and skip anything
already done. Run in foreground chunks of ~20 with a one-line summary per chunk, so a dead
session costs one chunk. This exists because a long audit died with its parent process and
had to restart from zero.

**codify it** — if this is the third time, the deliverable is the skill, not the output.
Check `.claude/skills/README.md` first; extend the existing skill rather than writing a
second one that will drift.

## Worked examples

**Vague in:** "add validation to the forms"

```
SHARPENED
Objective : Every user-submittable form rejects invalid input before it reaches storage.
Done when : the full form inventory with a count; the app running and a rejected
            submission shown on screen; the empty-string and max-length cases pasted.
Not doing : not restyling the forms or changing their fields - validation only.
Shape     : checkpointed batch - inventory is large, resumable.
Assumed   : "forms" = user-submittable forms only, not internal/admin config screens.
```

**Vague in:** "why is the page slow"

```
SHARPENED
Objective : Root cause of the slow page load, named with evidence.
Done when : the measured wall-clock number before/after, plus the one command that
            discriminates the top cause from the runner-up.
Not doing : not optimising anything yet - diagnosis first, you choose the fix.
Shape     : subagent, report-only - bounded exploration.
Assumed   : "slow" = user-visible load time, measured in a real browser, not a synthetic
            benchmark. Checking live behaviour before reading docs.
```

## Anti-patterns

- **Never** ask a question you can answer by reading the repo. Read it.
- **Never** print a brief and then wait. Print and proceed.
- **Never** widen scope in the rewrite. Sharpening clarifies the ask; it does not grow it.
  A newly-spotted adjacent problem goes in `Not doing`, mentioned in one sentence.
- **Never** let `Done when` degrade into "tests pass". Name the artefact to be pasted.
- **Never** run this on a trivial request — that is the ceremony this removes.

## Evolution Log

- Created 2026-08-13 from a measured pattern: requests were being claimed done on the
  wrong evidence and needed 2-3 challenge rounds. The four shapes (inline / report-only
  subagent / checkpointed batch / codify) each come from a specific failure: a 200-line
  exploratory shell log with no deliverable, an audit that died with its parent process,
  and a workflow re-done by hand instead of hardened into its skill.
