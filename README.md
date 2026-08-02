# project-skeleton

Clone-and-go project scaffolder. It stamps any new (or freshly imported) project with the
full dxiiren onboarding kit — an idempotent `setup.ps1`, a `justfile`, a README, a numbered
`.docs/` documentation set, and a `.claude/` kit (11 skills, statusline, memory seed, MCP
stub) — in two steps: a mechanical token fill, then an intelligent grounding pass by Claude.

> This README describes the skeleton itself. Running `.\init.ps1` REPLACES it with the
> scaffolded project's own README (from `README.project.template`) — that is intentional.

## Quick start

```powershell
# 1. Clone into your new project's folder name
git clone https://github.com/dxiiren/project-skeleton my-new-app
cd my-new-app

# 2. Mechanical scaffold — pick a stack, fill the tokens, clean up the scaffolding
.\init.ps1
#    (or non-interactive: .\init.ps1 -Name my-new-app -Stack static -Port 8433 -Docroot . -FreshGit)

# 3. One-time machine setup (idempotent — installs the stack's toolchain)
pwsh ./setup.ps1

# 4. Intelligent grounding — Claude reads the real code and finishes the kit
claude
/ground-project
```

After step 4 the project has a filled CLAUDE.md/README/.docs, skills grounded in its real
code, the applicable optional skills enabled, a passing skill audit, and a boot-verified
`just start`/`just build` workflow.

## Stacks

| Stack | Serves / builds | Extra inputs init.ps1 asks for |
| --- | --- | --- |
| `php-laravel` | `artisan serve` on the assigned port; sqlite locally | Port |
| `php-plain` | `php -S` built-in server | Port, Docroot |
| `node-vite` | Vite dev server (`--strictPort`; use `localhost` URLs) | Port |
| `node-nuxt` | Nuxt dev server (no strictPort; preview reads `PORT` env) | Port |
| `static` | Python `http.server` via uv | Port, Docroot |
| `cli-java` | `javac`/`java` build-run (no server) | MainClass |
| `cli-cpp` | w64devkit g++ build-run (no server) | Src (source files) |
| `cli-jupyter` | Jupyter Lab / headless nbconvert via uv | Port |
| `vbnet` | MSBuild + WinForms exe (no server) | MainClass (project name), Src (solution file) |

## What's inside

```
project-skeleton/
  init.ps1                  # the scaffolder (step 2 above) — deletes itself when done
  justfile                  # skeleton DEV recipes (just test) — replaced by the stack's at init
  tests/init.Tests.ps1      # Pester suite locking init.ps1's behavior — removed at init
  GROUNDING.md              # conventions bible -> becomes .docs/05-reference/conventions.md
  CLAUDE.md.template        # -> CLAUDE.md at init
  README.project.template   # -> README.md at init (replaces this file)
  .mcp.json.stub            # committed MCP placeholders (context7/playwright/github)
  gitignore-block.txt       # merged into .gitignore at init, then deleted
  stacks/<stack>/           # per-stack setup.ps1 + justfile + NOTES.md (tokenized, validated)
  .docs/                    # numbered documentation template tree (placeholders)
  .claude/
    settings.json           # shared settings incl. statusline wiring
    hooks/statusline.py     # git-aware statusline
    memory/MEMORY.md        # project-memory seed
    skills/                 # 10 core skills + ground-project (catalog: skills/README.md)
    skills-optional/        # opt-in skills ground-project enables when prerequisites exist
```

Token conventions, invariants, and the per-stack boot-verify bar live in
[`GROUNDING.md`](GROUNDING.md).

## Testing

The scaffold behavior is locked by a Pester suite:

```powershell
just test
# equivalent: pwsh -Command "Invoke-Pester -Path tests"  (Pester 5+, see below)
```

`tests/init.Tests.ps1` copies the whole skeleton into a fresh `%TEMP%` folder per
Describe and runs `init.ps1` there — the working tree is never scaffolded, and temp
copies are deleted afterwards. It covers two full scaffolds (`static` with
Port/Docroot, `cli-java` with MainClass) plus the negative path:

- `justfile` + `setup.ps1` land at the root with **zero** mechanical tokens; Port,
  Title, Docroot and MainClass values are actually wired in.
- `CLAUDE.md`/`README.md` are created from the templates; `GROUNDING.md` and the
  stack's `NOTES.md` move into `.docs/05-reference/`.
- The scaffolding removes itself: `stacks/`, `init.ps1`, `gitignore-block.txt`, and
  the skeleton's own `tests/` suite.
- The gitignore block is merged; **content** tokens (`WHAT_IT_IS`, ...) survive for
  `/ground-project`, and `conventions.md`'s token table is skipped by the fill.
- Re-running init on an already-scaffolded copy **refuses** (exit 1) and leaves the
  project untouched.

Requirement: Pester 5+ visible to `pwsh` (the Windows-inbox Pester 3 can't run it):

```powershell
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck
```

Change `init.ps1` or a stack's files → run `just test` before pushing; if you change
what init observably does, update the suite in the same commit.

## Adding a stack

1. Create `stacks/<name>/` with a `setup.ps1`, a `justfile`, and a `NOTES.md`, following
   the invariants in `GROUNDING.md` (log tags, EAP guard, justfile rules, project-scoped
   stop). Tokenize project facts with the mechanical tokens from the token table.
2. Base `setup.ps1` on the closest existing stack (the node one is the smallest base) and
   insert the stack's toolchain step; keep the helpers verbatim and renumber cleanly.
3. Add the stack's row to the boot-verify table in `GROUNDING.md` and to the table above.
4. If the stack needs an input beyond Name/Port, map it onto an existing token
   (`MAIN_CLASS` / `SRC` / `DOCROOT` — see the vbnet mapping in `stacks/vbnet/NOTES.md`)
   and add the stack to the matching prompt list in `init.ps1`.
5. Prove it: run `.\init.ps1` against a copy, `just --list`, `pwsh ./setup.ps1`, and the
   stack's boot-verify before pushing — and `just test` must stay green (add a Describe
   for the new stack if it introduces a new input/token mapping).
