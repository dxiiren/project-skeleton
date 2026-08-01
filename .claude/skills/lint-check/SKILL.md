---
name: lint-check
description: Use when the developer says 'lint check', 'run lint', 'check lint', 'run the quality suite', or 'lint everything' — runs the quality layers this project has (its stack gate, a leftover-placeholder grep, a debug-leftover grep) and reports pass/fail per layer.
model: sonnet
---

# lint-check — Quality layers (stack gate · placeholders · leftovers)

Run the honest quality layers for this repo and report pass/fail per layer. Run each
independently so one failure doesn't hide the others.

## Trigger

When the developer says any of: "lint check", "run lint", "check lint",
"run the quality suite", "lint everything".

---

## What to Do

### 1 — Stack gate

[GROUND: this repo's real quality gate(s), one fenced command block each with its pass
criterion. Use what actually exists — e.g. `npm run lint` / `just lint` (Pint) /
`javac -Xlint:all -d out *.java` (pass = exit 0 AND zero warnings) / a full
`just build` smoke. If the repo has NO lint/test toolchain (static/plain stacks), model
this layer on the toolchain-less pattern: a stdlib parse of the primary artifact — e.g.
Python's html.parser over index.html — pass = clean parse, exit 0. Do NOT introduce a
new toolchain just to have a linter.]

### 2 — Leftover template placeholders

The onboarding kit stamps files from templates whose fill-in tokens are delimited by
doubled at-signs. The `@[@]` character class below matches that delimiter in files
without this skill file matching its own check:

```bash
grep -rnI "@[@]" --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git .
```

Pass = the only hits are the token table in `.docs/05-reference/conventions.md`
(documentation — expected). Any other hit is an unfilled kit placeholder token — fix it
at the source.

### 3 — Debug / draft leftovers

```bash
grep -rn "TODO\|FIXME\|XXX\|console\.log\|debugger\|lorem ipsum" [GROUND: the source paths/globs to scan]
```

Pass = zero hits (grep exits 1). A hit is not automatically fatal — judge it: a
deliberate TODO with a follow-up is fine; a stray debug print shipped to the user is not.

---

## Reporting back

Report a per-layer table, then an overall verdict:

```
LAYER         TOOL                       STATUS
stack gate    [GROUND: tool name]        PASS | FAIL (N errors)
placeholders  grep "@[@]"                PASS | FAIL (N hits)
leftovers     grep TODO/debug            PASS | FAIL (N hits, judged)
OVERALL: PASS | FAIL
```

- **stack gate** failures are fixed at the root cause in the source — never by weakening
  or suppressing the check.
- **placeholders** failures mean an unfilled template token from the onboarding kit —
  fill it with the real value (or run `/ground-project` if the scaffold was never
  grounded).
- **leftovers** hits require judgment — report each with its line and a verdict.

---

## Notes

- Run from the **repo root** — the paths above are root-relative.
- Do NOT introduce a new lint toolchain just to make this skill bigger — the layers
  mirror what the project actually has.
- [GROUND: how visual/behavioral regressions are verified outside this skill, e.g.
  "reload the app URL after `just start`" or "run `just run` and eyeball the output".]

## Evolution Log

- Shipped with the project-skeleton kit: the three-layer shape (stack gate +
  placeholder grep + leftover grep) proven across the stamped dxiiren repos, including
  the toolchain-less variant. `/ground-project` writes layer 1 and the scan paths for
  this repo.
