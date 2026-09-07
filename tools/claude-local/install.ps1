#!/usr/bin/env pwsh

# project-skeleton tools/claude-local/install.ps1 -- install the claude-local launcher
#
# claude-local runs the SAME Claude Code binary against a self-hosted vLLM model that
# serves the Anthropic Messages API (vLLM 0.19+), through a small local shim. The README
# next to this file explains what the shim fixes and the limits (context size!).
#
# Usage -- from a clone of the skeleton:
#   pwsh tools/claude-local/install.ps1 -Upstream http://vllm-host:8000
#
# Usage -- from the web, no clone (Windows PowerShell 5.1 is fine):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/dxiiren/project-skeleton/main/tools/claude-local/install.ps1))) -Upstream http://vllm-host:8000
#
# Usage -- as part of the machine bootstrap:
#   initial-setup.ps1 -LocalLlmUpstream http://vllm-host:8000
#
# Parameters:
#   -Upstream <url>      Base URL of the vLLM server (no /v1). Required on the first install;
#                        later runs reuse the one already in config.json.
#   -Model <id>          Exact model id to use (default: first entry of <url>/v1/models, read at launch)
#   -Source <dir|url>    Where claude-local.ps1 / shim.py / README.md come from. Default: this
#                        script's folder when run from a clone, else the skeleton's raw URL.
#   -ClaudeDir <dir>     Install dir            (default %USERPROFILE%\.claude\local-llm)
#   -BinDir <dir>        Dir for the two stubs  (default %USERPROFILE%\.local\bin -- on PATH once uv is installed)
#   -ProfilePath <file>  PowerShell profile that gets the claude-local function (default: pwsh's $PROFILE)
#   -NoProfileEdit       Do not touch any PowerShell profile
#   -SkipProbe           Do not contact the upstream (offline installs, tests)
#
# Idempotent: re-running refreshes the files and never duplicates the profile line.
# Must parse and run under Windows PowerShell 5.1 (initial-setup.ps1 calls it there).

[CmdletBinding()]
param(
    [string]$Upstream,
    [string]$Model,
    [string]$Source,
    [string]$ClaudeDir = "$env:USERPROFILE\.claude\local-llm",
    [string]$BinDir    = "$env:USERPROFILE\.local\bin",
    [string]$ProfilePath,
    [switch]$NoProfileEdit,
    [switch]$SkipProbe
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # 5.1's download progress bar is slow and noisy
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$DefaultRaw = 'https://raw.githubusercontent.com/dxiiren/project-skeleton/main/tools/claude-local'
$Files      = @('claude-local.ps1', 'shim.py', 'README.md')
$utf8NoBom  = New-Object System.Text.UTF8Encoding($false)

Write-Host ""
Write-Host "claude-local install" -ForegroundColor Cyan
Write-Host "====================" -ForegroundColor Cyan

# ---------- 1. Where do the files come from? ----------
if (-not $Source) {
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'claude-local.ps1'))) {
        $Source = $PSScriptRoot
    } else {
        $Source = $DefaultRaw
    }
}
$fromUrl = ($Source -match '^https?://')
$Source  = $Source.TrimEnd('/', '\')
Write-Host "[INFO] Source: $Source" -ForegroundColor Cyan

# ---------- 2. config.json: upstream + model ----------
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
$cfgPath  = Join-Path $ClaudeDir 'config.json'
$existing = $null
if (Test-Path $cfgPath) {
    try { $existing = Get-Content $cfgPath -Raw | ConvertFrom-Json } catch { $existing = $null }
}
if (-not $Upstream -and $existing -and $existing.upstream) { $Upstream = $existing.upstream }
if (-not $Upstream) {
    Write-Host "[FAIL] No upstream. Pass -Upstream http://host:port (the vLLM server's base URL, without /v1)." -ForegroundColor Red
    exit 1
}
$Upstream = $Upstream.TrimEnd('/')
if (-not $Model -and $existing -and $existing.model) { $Model = $existing.model }
$label = ''
if ($existing -and $existing.label) { $label = $existing.label }
$cfg = [ordered]@{ upstream = $Upstream; model = "$Model"; label = "$label" }
[System.IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json), $utf8NoBom)
$modelNote = ''
if ($Model) { $modelNote = ", model $Model" }
Write-Host "[OK] config.json -> upstream $Upstream$modelNote" -ForegroundColor Green

# ---------- 3. Probe the server (informational only) ----------
if (-not $SkipProbe) {
    try {
        $m = Invoke-RestMethod -Uri "$Upstream/v1/models" -TimeoutSec 5 -ErrorAction Stop
        $first = $m.data[0]
        Write-Host "[OK] $Upstream serves '$($first.id)' (context $($first.max_model_len))" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] $Upstream/v1/models not reachable right now (VPN down?). Installing anyway; claude-local re-checks at launch." -ForegroundColor Yellow
    }
}

# ---------- 4. The files ----------
foreach ($f in $Files) {
    $dest = Join-Path $ClaudeDir $f
    if ($fromUrl) {
        Invoke-WebRequest -UseBasicParsing -Uri "$Source/$f" -OutFile $dest
    } else {
        Copy-Item (Join-Path $Source $f) $dest -Force
    }
}
Write-Host "[OK] $($Files -join ', ') -> $ClaudeDir" -ForegroundColor Green

$hasPython = (Get-Command pythonw -ErrorAction SilentlyContinue) -or (Get-Command python -ErrorAction SilentlyContinue) -or (Get-Command uv -ErrorAction SilentlyContinue)
if (-not $hasPython) {
    Write-Host "[WARN] No python/pythonw/uv on PATH. The shim needs Python 3: install it (initial-setup.ps1 does 'uv python install')." -ForegroundColor Yellow
}

# ---------- 5. Stubs on PATH ----------
# Written with %USERPROFILE% / $USERPROFILE / $HOME when the install dir sits under the
# profile, so the stubs stay portable and never bake in a personal path.
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
$launcher     = Join-Path $ClaudeDir 'claude-local.ps1'
$launcherCmd  = $launcher
$launcherBash = $launcher
$launcherPs   = $launcher
$profileRoot  = $env:USERPROFILE
if ($profileRoot -and $launcher.StartsWith($profileRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    $rel          = $launcher.Substring($profileRoot.Length)
    $launcherCmd  = '%USERPROFILE%' + $rel
    $launcherBash = '$USERPROFILE' + ($rel -replace '\\', '/')
    $launcherPs   = '$HOME' + $rel
}
$cmdStub = @(
    '@echo off',
    'rem claude-local: Claude Code on a self-hosted vLLM model. Docs: the README.md next to claude-local.ps1',
    'where pwsh >nul 2>&1',
    'if %errorlevel%==0 (',
    "  pwsh -NoProfile -ExecutionPolicy Bypass -File `"$launcherCmd`" %*",
    ') else (',
    "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$launcherCmd`" %*",
    ')'
) -join "`r`n"
[System.IO.File]::WriteAllText((Join-Path $BinDir 'claude-local.cmd'), $cmdStub + "`r`n", $utf8NoBom)
$bashStub = @(
    '#!/usr/bin/env bash',
    '# claude-local for Git Bash (skips cmd.exe and its "Terminate batch job?" prompt on Ctrl+C).',
    "exec pwsh -NoProfile -ExecutionPolicy Bypass -File `"$launcherBash`" `"`$@`""
) -join "`n"
[System.IO.File]::WriteAllText((Join-Path $BinDir 'claude-local'), $bashStub + "`n", $utf8NoBom)
Write-Host "[OK] claude-local.cmd + claude-local (bash) -> $BinDir" -ForegroundColor Green

# Only the default bin dir is ever added to the User PATH (a custom -BinDir is the caller's business).
$defaultBin = "$env:USERPROFILE\.local\bin"
if ($BinDir.TrimEnd('\') -ieq $defaultBin) {
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $userPath) { $userPath = '' }
    if (($userPath -split ';') -notcontains $defaultBin) {
        [System.Environment]::SetEnvironmentVariable("Path", ($userPath.TrimEnd(';') + ";" + $defaultBin), "User")
        Write-Host "[INFO] Added $defaultBin to the User PATH (close and reopen the terminal)" -ForegroundColor Yellow
    }
}

# ---------- 6. pwsh profile function (so pwsh users skip the .cmd hop) ----------
if (-not $NoProfileEdit) {
    if (-not $ProfilePath) {
        if (Get-Command pwsh -ErrorAction SilentlyContinue) {
            try { $ProfilePath = (& pwsh -NoProfile -Command '$PROFILE' 2>$null | Select-Object -First 1) } catch { }
        }
        if (-not $ProfilePath) {
            $ProfilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
        }
    }
    $profDir = Split-Path -Parent $ProfilePath
    if ($profDir -and -not (Test-Path $profDir)) { New-Item -ItemType Directory -Force -Path $profDir | Out-Null }
    $current = ''
    if (Test-Path $ProfilePath) { $current = [System.IO.File]::ReadAllText($ProfilePath) }
    if ($current.Contains('claude-local.ps1')) {
        Write-Host "[OK] $ProfilePath already defines claude-local" -ForegroundColor Green
    } else {
        $line  = 'function claude-local { & "' + $launcherPs + '" @args }'
        $block = "`r`n# claude-local: Claude Code on a self-hosted vLLM model (project-skeleton tools/claude-local/install.ps1)`r`n$line`r`n"
        [System.IO.File]::AppendAllText($ProfilePath, $block, $utf8NoBom)
        Write-Host "[OK] Added the claude-local function to $ProfilePath" -ForegroundColor Green
    }
}

# ---------- 7. Stop a running shim so the next launch loads the fresh shim.py ----------
$pidFile = Join-Path $ClaudeDir 'logs\shim.pid'
if (Test-Path $pidFile) {
    $oldPid = 0
    try { $oldPid = [int](Get-Content $pidFile -TotalCount 1) } catch { $oldPid = 0 }
    if ($oldPid -gt 0) {
        $p = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
        if ($p -and $p.ProcessName -match 'python') {
            Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Stopped the running shim (pid $oldPid); it restarts on the next claude-local" -ForegroundColor Green
        }
    }
}

# ---------- Done ----------
Write-Host ""
Write-Host "claude-local installed." -ForegroundColor Green
Write-Host "[NEXT] Open a NEW terminal, then:   claude-local" -ForegroundColor Gray
Write-Host "[NEXT] Inside it, /model lists the local model row. Request log: $ClaudeDir\logs\shim.log" -ForegroundColor Gray
Write-Host ""
