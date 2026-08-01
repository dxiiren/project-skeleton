---
name: update-or-create-docs
description: Use when creating OR updating any .docs/ document — enforces style consistency and ensures .docs/README.md and .docs/tldr.md are always updated as a set.
model: sonnet
---

# Update or Create Docs -- Documentation Consistency Enforcer

## Trigger

Invoke whenever creating a NEW `.docs/` document, updating an EXISTING one, or the user says
"document X", "write a doc for X", "add to docs", "update the docs".

---

## Rule: The Sibling Update (NON-NEGOTIABLE)

Every time a `.docs/` document is created or meaningfully updated, these MUST be updated in
the same pass:

| File | What to update |
|------|---------------|
| `.docs/README.md` | Add/update the row in the correct section table |
| `.docs/tldr.md` | Add/update the 30-second summary section |

### Mechanical gate -- run the sync checker

Before reporting done, verify the sibling rule with the dedicated script:

```bash
uv run --no-project python .claude/skills/update-or-create-docs/check-sibling-sync.py
```

- It reads git state (staged + unstaged + untracked) under `.docs/`. If any `.docs/` doc
  changed but the two siblings did not both change, it prints the missing siblings and
  exits 1.
- `SYNC OK` + exit 0 = the rule is satisfied.

> The script is the single source of truth for the gate. Don't reimplement it inline; if
> it's wrong, fix `check-sibling-sync.py`.

---

## Writing Style (the reasoning part -- stays with the model)

### Step 1: Read a sibling doc first (style check)

Before writing a new doc, read ONE existing doc in the same numbered section
(`01-overview/` ... `07-faq/`). Check: TL;DR callout? `---` rules between sections?
heading depth? Related-docs table at the end?

### Step 2: Style rules (from `.docs/05-reference/conventions.md`)

- **Every doc opens with a `> **TL;DR** ...` blockquote** and ends with a **Related docs**
  table.
- **No badges, no emoji, tables over prose, second-person imperative.**
- **Explicit over implicit.** State the mechanism, not just the outcome — every link in the
  chain stated (not "X collects metrics" but "X runs as ..., reads ..., and returns ...").
- Content depth scales with the change — structure never does.

### Step 3: Create or update

- **New:** structure as (1) what it is + why it exists, (2) how it works end-to-end,
  (3) specifics (commands/ports/paths), (4) local dev, (5) how to extend.
- **Updating:** read the full current doc first; update only affected sections; then
  re-check the README.md description + tldr.md summary accuracy.

### Steps 4-5: Update the siblings

- **README.md** -- one-line row: `| [filename.md](XX-section/filename.md) | what it covers,
  who reads it |` in the right `## NN-folder` section.
- **tldr.md** -- a 30-second section: title link, 1-2 sentence plain-English summary,
  optional key flow/command block, <=5 key-facts bullets ending with `---`. Summarise in
  your own words, never copy-paste. Keep sections in the numbered-folder order.

---

## Evolution Log

- Shipped with the project-skeleton kit, adapted from a larger team repo's three-file rule:
  the environment-urls sibling (team-infra specific) was dropped; the two-sibling gate
  (README.md + tldr.md) + the committed sync-check script pattern kept intact.
