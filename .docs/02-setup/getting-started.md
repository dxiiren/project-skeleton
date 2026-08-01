# Getting Started — @@PROJECT_TITLE@@

> **TL;DR** — `pwsh ./setup.ps1` once (idempotent), reopen PowerShell, then
> [GROUND: the first-boot recipe chain for this stack].

## Prerequisites

PowerShell + winget (stock Windows 10/11). Everything else is installed by `setup.ps1`.

## One-time machine setup

```powershell
pwsh ./setup.ps1
```

Idempotent — safe to re-run; a second run must be all-`[OK]`. Then CLOSE AND REOPEN
PowerShell so PATH updates land.

[GROUND: list what setup.ps1 installs for THIS stack (from its numbered steps), and any
manual follow-up (e.g. `gh auth login`, filling the GitHub PAT in `.mcp.json`).]

## First boot

```powershell
[GROUND: the exact first-boot commands and what success looks like, e.g.
just bootstrap   # deps + .env + sqlite + migrate + assets
just start       # serves http://127.0.0.1:@@PORT@@
— or for a CLI stack: just build / just run.]
```

[GROUND: how to verify it worked (the probe/URL/output to expect) and how to stop.]

## Related docs

| Doc | Why |
| --- | --- |
| [workflow.md](../03-development/workflow.md) | The day-2 development loop |
| [common-issues.md](../06-troubleshooting/common-issues.md) | When a step fails |
