---
name: verify-before-claim
description: Use before saying a change is done, fixed, working or verified - spawns a FRESH adversarial verifier subagent that receives only the requirement and the changed-file list, and must prove the change works with live evidence. Also triggers on 'verify this', 'prove it', 'are you sure it works'.
model: opus
---

# verify-before-claim — adversarial proof before the claim

Before you tell the developer a change is done, hand it to a **fresh verifier that does
not know what you did**. You cannot verify your own work: you already believe it. The
verifier gets the requirement and the changed-file list — nothing else — and must break
it with live evidence or report PASS with the commands that prove it.

The agent definition lives at `.claude/agents/verifier.md`.

## Trigger

- You are about to say **"done"**, **"fixed"**, **"working"**, **"verified"**,
  **"that should do it"**, or ship any equivalent claim.
- The developer says: `"verify this"`, `"prove it"`, `"are you sure it works"`,
  `"did you actually test that"`.

Run it **before** the claim, not after the developer pushes back.

---

## 1 — Stop before the claim

The moment you are about to assert the change works, stop and run this protocol instead.

Do NOT skip it because the change is small, because the build went green, or because the
diff obviously does the right thing. Those are the three conditions under which the
shipped defects in step 5 shipped.

Skip it only when nothing was exercised at all — a docs-only edit with no behaviour
touched. Say plainly that you skipped it and why.

## 2 — Assemble the two inputs, and withhold everything else

The verifier's prompt contains **exactly two things**:

1. **The original requirement**, in the developer's own words. Quote it. Do not
   paraphrase it into your understanding of it, and do not narrow it to the part you
   worked on.
2. **The changed-file list**:

   ```bash
   git status --porcelain
   git diff --name-only
   ```

   (After a commit, use `git diff --name-only HEAD~1` or `git diff --name-only main...HEAD`
   for the branch's full set.)

**Deliberately withhold:** what you changed, which approach you picked, why you picked
it, what you already tested, and your own confidence. Any of it turns the verifier into a
reviewer of your story instead of a prober of the system. If the verifier asks, refuse
and tell it to verify the system.

## 3 — Spawn a FRESH verifier subagent

Spawn `verifier` as a **subagent** — a fresh context, not a section of your own reasoning.
Verifying inside your own context inherits your assumptions and defeats the whole point.

Prompt shape:

```
REQUIREMENT (verbatim from the developer):
<the quoted requirement>

CHANGED FILES:
<the file list from step 2>

You are not told what was done or why. Prove it is broken.
```

One verifier per requirement. If the developer asked for several independent things,
spawn one per thing so a PASS on one cannot cover a FAIL on another.

## 4 — Hand it this project's live-evidence bar

The verifier's toolbelt here is `Read`, `Grep`, `Glob`, `Bash`, and the `mcp__playwright__*`
browser tools. There are no infrastructure servers to lean on — every probe is a local
command or a real browser run.

Include in the prompt how this project is started and exercised:

[GROUND: the command that starts this project's app and the readiness check that proves
it is up — e.g. `just start`, then poll `curl.exe -s -o NUL -w "%{http_code}" <app URL>`
every 2 s up to 120 s. For a CLI / notebook stack with no server, give the build + run
pair instead (e.g. `just build` then `just run`, piping the committed sample input) and
state that there is no URL to probe.]

[GROUND: this project's local app URL exactly as the conventions doc fixes it for this
stack (`http://localhost:<assigned port>` for node stacks, `http://127.0.0.1:<assigned
port>` for php/static stacks), plus the specific routes or pages that exercise the
changed behaviour.]

[GROUND: the stop command and the orphaned-process check — e.g. `just stop`, then confirm
no process with this repo's path survives. Omit for stacks with no server.]

[GROUND: how to reach this project's data store if it has one (e.g. a `sqlite3` command
against the local DB file, or the framework's own console). If there is none, say "no
data store" so it is not reported as UNVERIFIED.]

[GROUND: this repo's source globs, so the verifier's sweep for missed call paths covers
the real tree and skips `node_modules` / `vendor` / build output.]

The bar it must hold: real HTTP calls, real browser runs against the real app, real data
queries, real host commands. **Mocked unit tests alone are an automatic FAIL, and a
passing build is not behaviour.**

## 5 — Name the four failure modes it must sweep

State them in the prompt so no run quietly omits one. These have all shipped before:

| # | Failure mode | What the verifier must do |
| --- | --- | --- |
| 1 | Partial coverage | Grep the whole tree for the pattern the change addressed — prove no second call path, sibling file, or alternate entry point is still on the old behaviour |
| 2 | Over-application | Feed boundary values (empty, one character, shortest legal value, already-transformed input) and read back what actually came out |
| 3 | "Deployment present" read as "behaviour verified" | Drive the real user-facing path; the new string existing in the build output proves nothing |
| 4 | Happy path only | Exercise empty / zero rows / exactly one row / maximum, plus the error path |

Each must be reported explicitly — PASS, FAIL, or UNVERIFIED — even when clean.

## 6 — Take the verdict at face value

The verifier returns one of **PASS / FAIL / PARTIAL** plus a numbered evidence log where
every line is a command actually run and its actual output.

- **PASS** — you may now make the claim. Report the verdict and the evidence log
  **verbatim** alongside it. Never claim more than the log proves.
- **FAIL / PARTIAL** — you are not done. Fix the root cause, then re-run this protocol
  from step 2 with a **new** verifier. Do not argue the finding away, do not re-prompt the
  same verifier for a softer read, and do not report "done with a caveat".
- Any **UNVERIFIED** line stays UNVERIFIED in your report to the developer, with the
  blocker named. Never quietly upgrade it.

If the verifier could not run anything at all, say so in one line and mark the whole
change UNVERIFIED. That is the honest outcome, not a failure of the protocol.

---

## Anti-patterns

- **Never** tell the verifier what you changed or why — that is the one input that
  invalidates the run.
- **Never** verify in your own context. Fresh subagent, every time.
- **Never** accept a green build, a clean lint run, a passing type-check, or "the file is
  deployed" as the evidence. None of those is behaviour.
- **Never** soften or re-word a FAIL when relaying it. Report the defect first, then what
  works.
- **Never** re-run the same verifier hoping for a better verdict. Fix the code, spawn a
  new one.
- **Never** claim done while an UNVERIFIED line stands.

## Evolution Log

- Shipped with the project-skeleton kit: the withhold-the-implementation shape (fresh
  verifier, two inputs only, live-evidence bar, four named failure modes, numbered
  evidence log) — every one of the four modes is a defect that shipped past a self-review
  first. `/ground-project` writes the start / probe / stop / data-store / source-glob
  facts for this repo.
