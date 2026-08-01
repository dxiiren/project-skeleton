# Development Workflow — @@PROJECT_TITLE@@

> **TL;DR** — [GROUND: the day-2 loop in one sentence: the recipes you live in, the
> quality gate before committing, and the commit/PR flow.]

## The daily loop

[GROUND: numbered day-2 steps for this stack, using only `just` recipes — e.g. start the
server / edit / verify (reload or re-run) / quality gate / commit. All commands are just
recipes; never invent an alternative for something a recipe covers.]

## Quality gates

[GROUND: this repo's real gates and their commands — the `/lint-check` layers, tests if
they exist, and what "green" looks like for each.]

## Git conventions

- Conventional Commits; use the `/commit` skill.
- Branch off `main`; open PRs with `/create-pr`; self-review with `/pre-pr-review`.
- NEVER add attribution trailers (`Co-Authored-By`, "Generated with Claude Code",
  session links) to any outward artifact.
- Full rules: [conventions.md](../05-reference/conventions.md).

## Claude Code

Project skills live in `.claude/skills/` (catalog: `.claude/skills/README.md`). Follow
the relevant skill before writing code. MCP servers are wired via `.mcp.json.stub` →
git-ignored `.mcp.json` (`/setup-mcp`, `/test-all-mcp`).

## Related docs

| Doc | Why |
| --- | --- |
| [commands.md](../05-reference/commands.md) | Every recipe in detail |
| [conventions.md](../05-reference/conventions.md) | The family-wide invariants + git rules |
