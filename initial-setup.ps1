#!/usr/bin/env pwsh

# project-skeleton initial-setup.ps1 -- MACHINE bootstrap (run once per laptop)
#
# For a BRAND-NEW Windows machine that has nothing but PowerShell. It installs the
# toolchain every project in this family assumes already exists -- Git, PowerShell 7,
# Node.js LTS, Claude Code, uv + Python, just, GitHub CLI -- and can clone the skeleton
# for you. Safe to re-run (idempotent) -- installed tools are reported and skipped.
#
# This is the step BEFORE init.ps1. It solves the chicken-and-egg problem: you cannot
# `git clone` the skeleton without Git, and you cannot `pwsh ./setup.ps1` without pwsh.
#
#   initial-setup.ps1  -> the MACHINE (once per laptop; this file)
#   init.ps1           -> the PROJECT (once per project; mechanical scaffold)
#   setup.ps1          -> the STACK   (per project; installs that stack's toolchain)
#
# Usage -- no clone yet, straight from the web (Windows PowerShell 5.1 is fine):
#   irm https://raw.githubusercontent.com/dxiiren/project-skeleton/main/initial-setup.ps1 | iex
#
# Usage -- same, but with arguments (iex cannot take parameters; use a scriptblock):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/dxiiren/project-skeleton/main/initial-setup.ps1))) -CloneTo C:\code\my-app
#
# Usage -- from a clone:
#   .\initial-setup.ps1
#   powershell -ExecutionPolicy Bypass -File .\initial-setup.ps1
#
# Parameters:
#   -CloneTo <path>   Clone the skeleton into <path> once Git is installed
#   -Repo <url>       Repo to clone (default: dxiiren/project-skeleton; set it for a fork)
#   -GitName <name>   Set the GLOBAL git user.name  (skipped if one is already configured)
#   -GitEmail <mail>  Set the GLOBAL git user.email (skipped if one is already configured)
#   -IncludeExtras    Also install Visual Studio Code + Windows Terminal
#   -NoPrompt         Never ask anything (for unattended runs)

[CmdletBinding()]
param(
    [string]$CloneTo,
    [string]$Repo = 'https://github.com/dxiiren/project-skeleton.git',
    [string]$GitName,
    [string]$GitEmail,
    [switch]$IncludeExtras,
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# Windows PowerShell 5.1 on an un-patched machine can still default to TLS 1.0, which
# every download below refuses. No-op on PowerShell 7.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

function Test-Command($Name) {
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Refresh-Path {
    # Reload PATH from registry so newly installed tools are found in this session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Install-Winget($PackageId, $DisplayName) {
    Write-Host "[INSTALL] Installing $DisplayName via winget ($PackageId)..." -ForegroundColor Yellow
    $savedEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & winget install --id $PackageId --exact --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Host
    $code = $LASTEXITCODE
    $ErrorActionPreference = $savedEAP
    Refresh-Path
    # winget returns 0 on fresh install, -1978335189 (0x8A15002B) when already installed -- both are fine
    return ($code -eq 0 -or $code -eq -1978335189)
}

function Add-UserPath($Dir) {
    if (-not (Test-Path $Dir)) { return }
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$Dir*") {
        [System.Environment]::SetEnvironmentVariable("Path", "$userPath;$Dir", "User")
        Write-Host "[INFO] Added $Dir to User PATH" -ForegroundColor Yellow
    }
    Refresh-Path
}

# Install a package that is NOT required for the kit to work: a failure is a [WARN],
# never a stop. Used for the -IncludeExtras tools.
function Install-Optional($PackageId, $DisplayName, $Probe) {
    Refresh-Path
    if ($Probe -and (Test-Command $Probe)) {
        Write-Host "[OK] $DisplayName already installed" -ForegroundColor Green
        return
    }
    if (-not $script:hasWinget) {
        Write-Host "[WARN] $DisplayName skipped -- winget unavailable." -ForegroundColor Yellow
        return
    }
    if (Install-Winget $PackageId $DisplayName) {
        Write-Host "[OK] $DisplayName installed" -ForegroundColor Green
    } else {
        Write-Host "[WARN] $DisplayName install failed via winget -- not required, continuing." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "project-skeleton initial setup" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "One-time MACHINE bootstrap: Git, PowerShell 7, Node, Claude Code, uv, just, gh." -ForegroundColor DarkGray
Write-Host ""

# ---------- 0. Prerequisites check ----------
Refresh-Path
Write-Host "[INFO] PowerShell $($PSVersionTable.PSVersion) on $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Cyan

$isAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }
if (-not $isAdmin) {
    Write-Host "[INFO] Not running as Administrator -- expect UAC prompts during installs." -ForegroundColor Cyan
    Write-Host "       Approve them, or re-run this script from an elevated PowerShell." -ForegroundColor DarkGray
}

$script:hasWinget = Test-Command "winget"
if (-not $script:hasWinget) {
    Write-Host "[WARN] winget not found -- most installs below cannot run." -ForegroundColor Yellow
    Write-Host "       Install 'App Installer' from the Microsoft Store, then re-run this script:" -ForegroundColor DarkGray
    Write-Host "       https://aka.ms/getwinget" -ForegroundColor DarkGray
    Write-Host "       (Windows 10 pre-1809 has no winget at all -- install Git and Node by hand.)" -ForegroundColor DarkGray
}

# ---------- 1. Git ----------
Refresh-Path
if (Test-Command "git") {
    Write-Host "[OK] Git already installed: $(git --version)" -ForegroundColor Green
} elseif ($script:hasWinget) {
    if (Install-Winget "Git.Git" "Git") {
        Refresh-Path
        if (Test-Command "git") {
            Write-Host "[OK] Git installed: $(git --version)" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Git installed but not on PATH. Close and reopen PowerShell, then re-run." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "[FAIL] Git install failed via winget" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[FAIL] Git missing and winget unavailable. Install from https://git-scm.com/download/win" -ForegroundColor Red
    exit 1
}

# ---------- 2. PowerShell 7 (pwsh) ----------
# Every project in this family is driven with `pwsh ./setup.ps1`, and the justfile guards
# shell out to pwsh -- but a fresh laptop only ships Windows PowerShell 5.1.
Refresh-Path
if (Test-Command "pwsh") {
    Write-Host "[OK] PowerShell 7 already installed: $(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')" -ForegroundColor Green
} elseif ($script:hasWinget) {
    if (Install-Winget "Microsoft.PowerShell" "PowerShell 7") {
        Refresh-Path
        if (-not (Test-Command "pwsh")) {
            # The installer writes the Machine PATH; register the default location for
            # this user too, so a session that misses that write still finds pwsh.
            Add-UserPath "$env:ProgramFiles\PowerShell\7"
        }
        if (Test-Command "pwsh") {
            Write-Host "[OK] PowerShell 7 installed: $(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')" -ForegroundColor Green
        } else {
            Write-Host "[WARN] PowerShell 7 installed but not on PATH. Close and reopen PowerShell." -ForegroundColor Yellow
        }
    } else {
        Write-Host "[FAIL] PowerShell 7 install failed via winget" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[FAIL] PowerShell 7 missing and winget unavailable. Install from https://aka.ms/powershell" -ForegroundColor Red
    exit 1
}

# ---------- 3. Node.js (LTS) ----------
Refresh-Path
if (Test-Command "node") {
    Write-Host "[OK] Node.js already installed: $(node -v)" -ForegroundColor Green
} elseif ($script:hasWinget) {
    if (Install-Winget "OpenJS.NodeJS.LTS" "Node.js (LTS)") {
        Refresh-Path
        if (Test-Command "node") {
            Write-Host "[OK] Node.js installed: $(node -v)" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Node.js installed but not on PATH. Close and reopen PowerShell, then re-run." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "[FAIL] Node.js install failed via winget" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[FAIL] Node.js missing and winget unavailable. Install from https://nodejs.org/" -ForegroundColor Red
    exit 1
}

# ---------- 4. Claude Code CLI ----------
Refresh-Path
if (Test-Command "claude") {
    $claudeVer = & claude --version 2>&1 | Select-Object -First 1
    Write-Host "[OK] Claude Code already installed: $claudeVer" -ForegroundColor Green
} else {
    Write-Host "[INSTALL] Installing Claude Code via npm (this takes a minute)..." -ForegroundColor Yellow
    $savedEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # Captured for the same reason as the clone below: npm's notices go to stderr and
    # PowerShell 5.1 paints them red. Printed only if the install actually failed.
    $npmLog = & npm install -g "@anthropic-ai/claude-code" 2>&1
    $ErrorActionPreference = $savedEAP
    Refresh-Path
    if (Test-Command "claude") {
        $claudeVer = & claude --version 2>&1 | Select-Object -First 1
        Write-Host "[OK] Claude Code installed: $claudeVer" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Claude Code install failed -- npm said:" -ForegroundColor Yellow
        foreach ($line in $npmLog) { Write-Host "       $line" -ForegroundColor DarkGray }
    }
}

# ---------- 5. uv (Python package manager / tool runner) ----------
Refresh-Path
if (Test-Command "uv") {
    $uvVer = & uv --version 2>&1 | Select-Object -First 1
    Write-Host "[OK] uv already installed: $uvVer" -ForegroundColor Green
} else {
    Write-Host "[INSTALL] Installing uv..." -ForegroundColor Yellow
    $savedEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    $ErrorActionPreference = $savedEAP
    Refresh-Path
    if (-not (Test-Command "uv")) {
        # uv installs to %USERPROFILE%\.local\bin and edits the User PATH -- pick that up
        # explicitly for sessions that started before the write.
        Add-UserPath "$env:USERPROFILE\.local\bin"
    }
    if (-not (Test-Command "uv")) {
        Write-Host "[FAIL] uv installed but not found on PATH. Close and reopen PowerShell, then re-run this script." -ForegroundColor Red
        exit 1
    }
    $uvVer = & uv --version 2>&1 | Select-Object -First 1
    Write-Host "[OK] uv installed: $uvVer" -ForegroundColor Green
}

# Ensure uv's tool bin directory is registered in PATH
$uvToolBin = & uv tool dir --bin 2>&1 | Select-Object -First 1
if ($uvToolBin) { Add-UserPath $uvToolBin }

# ---------- 6. Python (used by .claude tooling, e.g. the statusline + skill scripts) ----------
Write-Host "[INFO] Ensuring Python is available via uv..." -ForegroundColor Cyan
$savedEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& uv python install 2>&1 | Out-Null
$ErrorActionPreference = $savedEAP
$pyPath = & uv python find 2>&1 | Select-Object -First 1
if ($pyPath) {
    Write-Host "[OK] Python managed by uv: $pyPath" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Failed to install Python via uv" -ForegroundColor Red
    exit 1
}

# ---------- 7. just (task runner) ----------
Refresh-Path
if (Test-Command "just") {
    $justVer = & just --version 2>&1 | Select-Object -First 1
    Write-Host "[OK] just already installed: $justVer" -ForegroundColor Green
} else {
    Write-Host "[INSTALL] Installing just..." -ForegroundColor Yellow
    $savedEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $justLog = & uv tool install rust-just 2>&1
    $ErrorActionPreference = $savedEAP
    Refresh-Path
    if (Test-Command "just") {
        $justVer = & just --version 2>&1 | Select-Object -First 1
        Write-Host "[OK] just installed: $justVer" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] just installed but not found on PATH -- uv said:" -ForegroundColor Red
        foreach ($line in $justLog) { Write-Host "       $line" -ForegroundColor DarkGray }
        exit 1
    }
}

# ---------- 8. GitHub CLI ----------
# Used by the /create-pr and /commit skills. Run `gh auth login` once interactively.
Refresh-Path
if (Test-Command "gh") {
    Write-Host "[OK] GitHub CLI already installed: $(gh --version 2>&1 | Select-Object -First 1)" -ForegroundColor Green
} elseif ($script:hasWinget) {
    if (Install-Winget "GitHub.cli" "GitHub CLI") {
        Refresh-Path
        if (Test-Command "gh") {
            Write-Host "[OK] GitHub CLI installed: $(gh --version 2>&1 | Select-Object -First 1)" -ForegroundColor Green
            Write-Host "     Next: run 'gh auth login' once to authenticate." -ForegroundColor DarkGray
        } else {
            Write-Host "[WARN] GitHub CLI installed but not on PATH. Close and reopen PowerShell." -ForegroundColor Yellow
        }
    } else {
        Write-Host "[WARN] GitHub CLI install failed via winget" -ForegroundColor Yellow
    }
} else {
    Write-Host "[WARN] GitHub CLI skipped -- winget unavailable. Install from https://cli.github.com/" -ForegroundColor Yellow
}

# ---------- 9. Optional extras ----------
if ($IncludeExtras) {
    Write-Host ""
    Write-Host "Installing optional extras (-IncludeExtras)..." -ForegroundColor Cyan
    Install-Optional "Microsoft.VisualStudioCode" "Visual Studio Code" "code"
    Install-Optional "Microsoft.WindowsTerminal"  "Windows Terminal"   "wt"
}

# ---------- 10. Global git identity ----------
# Repo-local identity still wins (the conventions doc sets it per project) -- this only
# stops the very first commit on a fresh machine from failing with "please tell me who
# you are". Never overwrites an identity that is already configured.
Refresh-Path
$savedEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$currentName  = (& git config --global user.name  2>$null | Select-Object -First 1)
$currentEmail = (& git config --global user.email 2>$null | Select-Object -First 1)
$ErrorActionPreference = $savedEAP

if ($currentName -and $currentEmail) {
    Write-Host "[OK] Global git identity already set: $currentName <$currentEmail>" -ForegroundColor Green
} else {
    if (-not $GitName -and -not $NoPrompt -and [System.Environment]::UserInteractive) {
        $GitName = Read-Host "Global git user.name (blank to skip)"
    }
    if (-not $GitEmail -and -not $NoPrompt -and [System.Environment]::UserInteractive) {
        $GitEmail = Read-Host "Global git user.email (blank to skip)"
    }
    if ($GitName -and $GitEmail) {
        $savedEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & git config --global user.name  $GitName  2>&1 | Out-Null
        & git config --global user.email $GitEmail 2>&1 | Out-Null
        $ErrorActionPreference = $savedEAP
        Write-Host "[OK] Global git identity set: $GitName <$GitEmail>" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Global git identity not set -- configure it before your first commit:" -ForegroundColor Cyan
        Write-Host "       git config --global user.name 'Your Name'" -ForegroundColor DarkGray
        Write-Host "       git config --global user.email 'you@example.com'" -ForegroundColor DarkGray
    }
}

# ---------- 11. Clone the skeleton (optional) ----------
$cloned = $null
if ($CloneTo) {
    Write-Host ""
    Write-Host "Cloning the skeleton..." -ForegroundColor Cyan
    if ((Test-Path $CloneTo) -and (Get-ChildItem -Path $CloneTo -Force -ErrorAction SilentlyContinue)) {
        Write-Host "[WARN] $CloneTo already exists and is not empty -- skipping the clone." -ForegroundColor Yellow
    } else {
        $savedEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        # CAPTURED, not piped to Out-Host: git writes its progress to stderr, and
        # Windows PowerShell 5.1 renders any stderr line from a native command as a red
        # NativeCommandError -- which would make a SUCCESSFUL clone look like a failure.
        # Collect it instead and print it only when the exit code says it went wrong.
        $cloneLog = & git clone --quiet $Repo $CloneTo 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $savedEAP
        if ($code -eq 0) {
            $cloned = (Resolve-Path $CloneTo).Path
            Write-Host "[OK] Cloned $Repo -> $cloned" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] git clone failed (exit $code) -- clone it yourself:" -ForegroundColor Red
            foreach ($line in $cloneLog) { Write-Host "       $line" -ForegroundColor DarkGray }
            Write-Host "       git clone $Repo $CloneTo" -ForegroundColor DarkGray
        }
    }
}

# ---------- Final verification ----------
Refresh-Path
Write-Host ""
Write-Host "Verifying installations..." -ForegroundColor Cyan
$missing = @()
foreach ($tool in @('git','pwsh','node','npm','claude','uv','just','gh')) {
    if (Test-Command $tool) {
        Write-Host "  [OK] $tool" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $tool" -ForegroundColor Red
        $missing += $tool
    }
}
if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "[WARN] Some tools not found on PATH in this session: $($missing -join ', ')" -ForegroundColor Yellow
    Write-Host "       CLOSE AND REOPEN PowerShell and run them to confirm." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Machine setup complete!" -ForegroundColor Green
Write-Host ""

# ---------- Next steps (manual) ----------
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "[NEXT] 0. CLOSE AND REOPEN PowerShell so the new PATH lands." -ForegroundColor Gray
if ($cloned) {
    Write-Host "[NEXT] 1. Go to your new project:   cd '$cloned'" -ForegroundColor Gray
} else {
    Write-Host "[NEXT] 1. Clone the skeleton:       git clone $Repo my-new-app" -ForegroundColor Gray
    Write-Host "[NEXT]                              cd my-new-app" -ForegroundColor Gray
}
Write-Host "[NEXT] 2. Scaffold the project:     .\init.ps1" -ForegroundColor Gray
Write-Host "[NEXT] 3. Install the stack tools:  pwsh ./setup.ps1" -ForegroundColor Gray
Write-Host "[NEXT] 4. Authenticate:             gh auth login   then   claude" -ForegroundColor Gray
Write-Host "[NEXT] 5. Ground the kit:           /ground-project  (inside Claude Code)" -ForegroundColor Gray
Write-Host ""
