# project-skeleton justfile — SKELETON DEV recipes (never ships: init.ps1 step 1
# overwrites this file with the chosen stack's justfile).
#
# GUARD MARKER: init.ps1 treats "root justfile with no @@ tokens" as the
# already-scaffolded signal and refuses to run. The literal @@ in this comment is
# what keeps init runnable on a fresh clone — do not remove it.

set shell := ["powershell.exe", "-NoProfile", "-Command"]

# List available recipes
default:
    @just --list

# ─── Guards ───────────────────────────────────────────────

# Pester 5+ must be visible to pwsh (PowerShell 7) — the Windows-inbox Pester 3 can't
# run this suite, and modules installed for powershell.exe are invisible to pwsh.
[private]
_require-pester:
    @if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { Write-Error "pwsh (PowerShell 7) not found on PATH."; exit 1 }; pwsh -NoProfile -Command 'if (-not (Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -ge 5 })) { Write-Host ''[FAIL] Pester 5+ not found in pwsh.'' -ForegroundColor Red; Write-Host ''  -> Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck'' -ForegroundColor DarkGray; exit 1 }'

# ─── Tests ───────────────────────────────────────────────

# Each Describe copies the skeleton to a fresh %TEMP% folder and runs init.ps1 there —
# the working tree is never scaffolded, and temp copies are cleaned up afterwards.
# Run the Pester suite (tests/init.Tests.ps1): a full scaffold of every stack in stacks/,
# the re-run guard, and the failure paths (-FreshGit, missing value, missing stacks/).
test: _require-pester
    pwsh -NoProfile -Command '$c = New-PesterConfiguration; $c.Run.Path = ''tests''; $c.Run.Exit = $true; $c.Output.Verbosity = ''Detailed''; Invoke-Pester -Configuration $c'

# ─── Tools ───────────────────────────────────────────────

# Launch Claude Code with all permissions — Sonnet (latest)
claudex:
    claude --dangerously-skip-permissions --model sonnet

# Launch Claude Code with all permissions — Opus (latest)
claudeo:
    claude --dangerously-skip-permissions --model opus

# Launch Claude Code with all permissions — Haiku (latest)
claudeh:
    claude --dangerously-skip-permissions --model haiku
