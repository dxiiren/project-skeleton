# Skills Catalog — `@@REPO_SLUG@@`

Project development skills for @@PROJECT_TITLE@@. Each lives in its own directory with a
`SKILL.md`. **Follow the relevant skill before writing code.** Run `/audit-skills` to verify
every skill here is registered and that `CLAUDE.md` references only existing skills.

Model tiers: `sonnet` (floor) · `opus` (deep reasoning / generation).

> Freshly scaffolded? Run [ground-project](ground-project/SKILL.md) first — it resolves the
> `[GROUND: ...]` markers in the skills below against this project's real code and enables
> the applicable optional skills.

## Scaffolding

| Skill                                       | What it does                                                                                                                                       | Model |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| [ground-project](ground-project/SKILL.md)   | One-time grounding pass after `init.ps1`: fills content tokens, grounds skills in the real code, enables optional skills, audits, and boot-verifies. | opus  |

## Toolchain

| Skill                             | What it does                                                                                                             | Model  |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ------ |
| [setup-just](setup-just/SKILL.md) | Install the `just` command runner, fix the Windows winget PATH gap, and verify this repo's recipes list and run.         | sonnet |

## Git

| Skill                           | What it does                                                                                                                                                             | Model  |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------ |
| [commit](commit/SKILL.md)       | Conventional-Commits stage + message flow (stale-lock preflight, `git add -A` fast path, scoped stage-by-name). Never auto-commits, never amends, no attribution footer. | sonnet |
| [create-pr](create-pr/SKILL.md) | Push the current branch and open a **GitHub** PR into `main` via `gh` / GitHub MCP, with a clean Summary/Changes/Testing body and no attribution footer.                 | opus   |

## Quality & Review

| Skill                                               | What it does                                                                                                                    | Model  |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------ |
| [verify-before-claim](verify-before-claim/SKILL.md) | Spawn a fresh adversarial verifier subagent that must prove the change works with live evidence before anything is called done. | opus   |
| [pre-pr-review](pre-pr-review/SKILL.md)             | Self-review the branch diff against this project's stack checklist + a boot check; report to `workspace/reports/pr/`.           | opus   |
| [lint-check](lint-check/SKILL.md)                   | Run this project's quality layers (stack gate, kit-placeholder grep, debug-leftover grep); report pass/fail per layer.          | sonnet |

## MCP tooling

| Skill                                 | What it does                                                                                                  | Model  |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ------ |
| [setup-mcp](setup-mcp/SKILL.md)       | Registry-driven MCP setup / onboarding (reads `setup-mcp/registry.json`; wires stub + secret + enable tiers). | opus   |
| [test-all-mcp](test-all-mcp/SKILL.md) | Live per-server smoke-test sweep → PASS/FAIL/SKIP table (prompts in `test-all-mcp/checks/`).                  | sonnet |

## Maintenance

| Skill                                 | What it does                                                                                                     | Model  |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------ |
| [audit-skills](audit-skills/SKILL.md) | Verify every skill has a valid, registered `SKILL.md` (no BOM, valid model, no hardcoded secret) via `audit.py`. | sonnet |

## Planning & handoff

| Skill                                       | What it does                                                                                                        | Model  |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ------ |
| [define-goal](define-goal/SKILL.md)         | Interrogate until a goal is unambiguous, then write a stop-proof `{topic}-goal.md` for the built-in `/goal` runner. | opus   |
| [claude-transfer](claude-transfer/SKILL.md) | Pointer-based session-handoff brief to `workspace/reports/transfers/claude/`.                                       | sonnet |
| [llm-transfer](llm-transfer/SKILL.md)       | Self-contained master prompt for an external LLM → `workspace/reports/transfers/{tool}/`.                           | sonnet |

## Optional skills (in `.claude/skills-optional/` — not active)

`/ground-project` moves a skill from `skills-optional/` into `skills/` (and adds its row
above) when its prerequisite exists in this project. Unused ones stay in `skills-optional/`
as inert reference — they are not loaded and not audited.

| Skill (in skills-optional/) | Enable when |
| --- | --- |
| monitor-ci | CI workflow files exist (`.github/workflows/` or equivalent) |
| generate-playwright-tests | a Playwright dependency/config exists |
| fix-typecheck | a typecheck script or `tsconfig.json` exists |
| fix-phpstan | phpstan/larastan in `composer.json` |
| update-or-create-docs | always recommended once `.docs/` has real content |
