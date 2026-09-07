# project-skeleton

Clone-and-go project scaffolder. It stamps any new (or freshly imported) project with the
full dxiiren onboarding kit — an idempotent `setup.ps1`, a `justfile`, a README, a numbered
`.docs/` documentation set, and a `.claude/` kit (14 skills, statusline, memory seed, MCP
stub) — in two steps: a mechanical token fill, then an intelligent grounding pass by Claude.

> This README describes the skeleton itself. Running `.\init.ps1` REPLACES it with the
> scaffolded project's own README (from `README.project.template`) — that is intentional.

## Quick start

### Step 0 — brand-new laptop only (once per machine)

A fresh Windows machine has neither Git (so it cannot clone this repo) nor PowerShell 7
(so it cannot run `pwsh ./setup.ps1`). `initial-setup.ps1` closes that gap. Paste this
into **Windows PowerShell** — the stock one, no clone needed:

```powershell
irm https://raw.githubusercontent.com/dxiiren/project-skeleton/main/initial-setup.ps1 | iex
```

It installs Git, PowerShell 7, Node.js LTS, Claude Code, uv + Python, just and the GitHub
CLI, then prints the next steps. Idempotent — a second run is all-`[OK]`.

To pass arguments, `iex` won't do — use a scriptblock:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/dxiiren/project-skeleton/main/initial-setup.ps1))) -CloneTo C:\code\my-new-app -IncludeExtras
```

| Parameter | Effect |
| --- | --- |
| `-CloneTo <path>` | Clone the skeleton into `<path>` as soon as Git is installed |
| `-Repo <url>` | Clone a fork instead of `dxiiren/project-skeleton` |
| `-GitName` / `-GitEmail` | Set the **global** git identity (skipped if one already exists) |
| `-IncludeExtras` | Also install Visual Studio Code + Windows Terminal |
| `-NoPrompt` | Never ask anything — for unattended runs |
| `-LocalLlmUpstream <url>` | Also install `claude-local`: Claude Code on a self-hosted vLLM model at `<url>` ([tools/claude-local](tools/claude-local/README.md)) |

**Close and reopen PowerShell afterwards** so the new PATH lands. Then continue below.
Machines that already have the toolchain skip step 0 entirely.

### Steps 1–4 — every new project

```powershell
# 1. Clone into your new project's folder name
git clone https://github.com/dxiiren/project-skeleton my-new-app
cd my-new-app

# 2. Mechanical scaffold — pick a stack, fill the tokens, clean up the scaffolding
.\init.ps1
#    (or non-interactive: .\init.ps1 -Name my-new-app -Stack static -Port 8433 -Docroot . -FreshGit)

# 3. One-time project setup (idempotent — installs the stack's toolchain)
pwsh ./setup.ps1

# 4. Intelligent grounding — Claude reads the real code and finishes the kit
claude
/ground-project
```

After step 4 the project has a filled CLAUDE.md/README/.docs, skills grounded in its real
code, the applicable optional skills enabled, a passing skill audit, and a boot-verified
`just start`/`just build` workflow.

### The three setup scripts

| Script | Scope | Runs | Installs |
| --- | --- | --- | --- |
| `initial-setup.ps1` | the **machine** | once per laptop | Git, PowerShell 7, Node LTS, Claude Code, uv + Python, just, gh; `claude-local` on request |
| `init.ps1` | the **project** | once per project | nothing — it scaffolds files and deletes itself |
| `setup.ps1` | the **stack** | per project, re-runnable | that stack's toolchain (PHP, JDK, w64devkit, ...) |

`init.ps1` removes `initial-setup.ps1` along with the rest of the scaffolding, so a
scaffolded project ships exactly one `setup.ps1`.

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
  initial-setup.ps1         # per-MACHINE bootstrap (step 0) — removed at init
  tools/claude-local/       # claude-local: Claude Code on a self-hosted vLLM model (step 0 opt-in) — removed at init
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
copies are deleted afterwards. It scaffolds **all 9 stacks** and covers:

- **Shared scaffold steps** (asserted in full for `static` and `cli-java`):
  `CLAUDE.md`/`README.md` are created from the templates; `GROUNDING.md` and the
  stack's `NOTES.md` move into `.docs/05-reference/`; the scaffolding removes itself
  (`stacks/`, `init.ps1`, `initial-setup.ps1`, `tools/claude-local/`, `gitignore-block.txt`,
  the skeleton's own `tests/`) leaving exactly one root `setup.ps1`; the
  gitignore block is merged; **content** tokens (`WHAT_IT_IS`, ...) survive for
  `/ground-project`, and `conventions.md`'s token table is skipped by the fill.
- **Per-stack token fill** (every stack, driven by the `$stackMatrix` table): the
  stack's `justfile` + `setup.ps1` land at the root with **zero** mechanical tokens,
  and each of that stack's own tokens carries the value actually passed — Port, Title,
  Docroot, MainClass, Src, RepoSlug, and the hardcoded `8.4` / `vs17` PHP pair.
- **Failure paths:** re-running init on an already-scaffolded copy **refuses**
  (exit 1) and leaves the project untouched; a missing required value
  (`cli-java` with no MainClass, `cli-cpp` with no Src) exits 1 before touching
  anything; a missing `stacks/` folder exits 1; `-FreshGit` leaves a `.git` repo on
  branch `main`; a clone with **no** `initial-setup.ps1` (the `irm | iex` route)
  still scaffolds cleanly.
- **`initial-setup.ps1` itself:** it must parse under **Windows PowerShell 5.1** —
  asserted by re-parsing it with the 5.1 engine, since it runs before PowerShell 7
  exists and the suite's own pwsh host would never catch 5.1-invalid syntax. Plus:
  no tokens, it installs `Microsoft.PowerShell`, and it verifies all eight tools.
- **`tools/claude-local/install.ps1`:** installs into caller-supplied dirs (launcher,
  shim, README, a `config.json` holding the upstream, both PATH stubs, one profile
  line even after a re-run) and parses under 5.1, since `initial-setup.ps1` runs it there.

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
5. Add the stack's row to `$stackMatrix` in `tests/init.Tests.ps1` — the arguments to
   scaffold it with, plus one regex per token it owns proving the passed value landed.
   Every stack has a row; a stack without one is untested.
6. Prove it: run `.\init.ps1` against a copy, `just --list`, `pwsh ./setup.ps1`, and the
   stack's boot-verify before pushing — and `just test` must stay green.
