#!/usr/bin/env pwsh

# project-skeleton tools/claude-local/install.ps1 -- install the claude-local launcher
#
# claude-local runs the SAME Claude Code binary against self-hosted model servers that serve
# the Anthropic Messages API (vLLM 0.19+, Ollama), through a small local shim. The README next
# to this file explains what the shim fixes and the limits (context size!).
#
# Usage -- from a clone of the skeleton:
#   pwsh tools/claude-local/install.ps1 -Upstream http://vllm-host:8000                     # endpoint "main"
#   pwsh tools/claude-local/install.ps1 -Name ollama -Upstream http://127.0.0.1:11434 -Model qwen3.5:4b -Context 32768
#   pwsh tools/claude-local/install.ps1 -Name ollama -Default                                # make it the default
#
# Usage -- from the web, no clone (Windows PowerShell 5.1 is fine):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/dxiiren/project-skeleton/main/tools/claude-local/install.ps1))) -Upstream http://vllm-host:8000
#
# Usage -- as part of the machine bootstrap:
#   initial-setup.ps1 -LocalLlmUpstream http://vllm-host:8000
#
# Parameters:
#   -Upstream <url>      Base URL of the model server (no /v1). Required the first time; later
#                        runs without it only refresh the files.
#   -Name <name>         Endpoint name (default "main"). Each run adds or updates ONE endpoint.
#   -Model <id>          Exact model id (default: first entry of <url>/v1/models, read at launch).
#                        Pin it for Ollama, which lists every pulled model.
#   -Label <text>        Name shown in Claude Code's /model picker (default: "<model> (<name>)")
#   -Context <tokens>    Context length. vLLM reports it (max_model_len); Ollama does NOT, so set
#                        it to the same value as OLLAMA_CONTEXT_LENGTH on the Ollama side.
#   -Default             Make -Name the default endpoint (the first endpoint is default anyway)
#   -Source <dir|url>    Where claude-local.ps1 / shim.py / README.md come from. Default: this
#                        script's folder when run from a clone, else the skeleton's raw URL.
#   -ClaudeDir <dir>     Install dir            (default %USERPROFILE%\.claude\local-llm)
#   -BinDir <dir>        Dir for the two stubs  (default %USERPROFILE%\.local\bin -- on PATH once uv is installed)
#   -ProfilePath <file>  PowerShell profile that gets the claude-local function (default: pwsh's $PROFILE)
#   -NoProfileEdit       Do not touch any PowerShell profile
#   -SkipProbe           Do not contact the upstream (offline installs, tests)
#
# Idempotent: re-running refreshes the files, keeps the other endpoints, and never duplicates
# the profile line. Must parse and run under Windows PowerShell 5.1 (initial-setup.ps1 calls it there).

[CmdletBinding()]
param(
    [string]$Upstream,
    [string]$Name = 'main',
    [string]$Model,
    [string]$Label,
    [int]$Context = 0,
    [switch]$Default,
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

function Get-Prop($Obj, [string]$PropName) {
    if ($null -eq $Obj) { return $null }
    $p = $Obj.PSObject.Properties[$PropName]
    if ($p) { return $p.Value }
    return $null
}

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

# ---------- 2. config.json: named endpoints ----------
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
$cfgPath   = Join-Path $ClaudeDir 'config.json'
$existing  = $null
$endpoints = [ordered]@{}
$defaultName = ''
if (Test-Path $cfgPath) {
    try { $existing = Get-Content $cfgPath -Raw | ConvertFrom-Json } catch { $existing = $null }
}
if ($existing) {
    $eps = Get-Prop $existing 'endpoints'
    if ($eps) {
        foreach ($p in $eps.PSObject.Properties) {
            $endpoints[$p.Name] = [ordered]@{
                upstream = [string](Get-Prop $p.Value 'upstream'); model = [string](Get-Prop $p.Value 'model')
                label    = [string](Get-Prop $p.Value 'label');    context = [int](Get-Prop $p.Value 'context') }
        }
        $defaultName = [string](Get-Prop $existing 'default')
    } elseif (Get-Prop $existing 'upstream') {
        # pre-endpoints config.json ({ upstream, model, label }) -> endpoints.main
        $endpoints['main'] = [ordered]@{
            upstream = ([string]$existing.upstream).TrimEnd('/'); model = [string](Get-Prop $existing 'model')
            label    = [string](Get-Prop $existing 'label');       context = 0 }
        $defaultName = 'main'
        Write-Host "[OK] Migrated the single-endpoint config.json to endpoints.main" -ForegroundColor Green
    }
}
if ($Upstream) {
    $Upstream = $Upstream.TrimEnd('/')
    if (-not $endpoints.Contains($Name)) { $endpoints[$Name] = [ordered]@{ upstream = ''; model = ''; label = ''; context = 0 } }
    $endpoints[$Name].upstream = $Upstream
}
if ($endpoints.Contains($Name)) {
    if ($Model)        { $endpoints[$Name].model   = $Model }
    if ($Label)        { $endpoints[$Name].label   = $Label }
    if ($Context -gt 0) { $endpoints[$Name].context = $Context }
} elseif ($Model -or $Label -or $Context -gt 0 -or $Default) {
    Write-Host "[FAIL] No endpoint named '$Name' yet. Add it with -Upstream http://host:port." -ForegroundColor Red
    exit 1
}
if ($endpoints.Count -eq 0) {
    Write-Host "[FAIL] No endpoint. Pass -Upstream http://host:port (the model server's base URL, without /v1)." -ForegroundColor Red
    exit 1
}
if ($Default) { $defaultName = $Name }
if (-not $defaultName -or -not $endpoints.Contains($defaultName)) { $defaultName = [string]($endpoints.Keys | Select-Object -First 1) }

# ---------- 3. Probe the endpoint just set (informational, plus the Ollama context rule) ----------
$probeName = $defaultName
if ($Upstream) { $probeName = $Name }
if (-not $SkipProbe) {
    $u = $endpoints[$probeName].upstream
    try {
        $m = Invoke-RestMethod -Uri "$u/v1/models" -TimeoutSec 5 -ErrorAction Stop
        $first = $m.data[0]
        $ctxText = Get-Prop $first 'max_model_len'
        if (-not $ctxText) { $ctxText = 'not reported' }
        Write-Host "[OK] [$probeName] $u serves '$($first.id)' (context $ctxText)" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] [$probeName] $u/v1/models not reachable right now (server down, VPN?). Installing anyway; claude-local re-checks at launch." -ForegroundColor Yellow
    }
    $isOllama = $false
    try {
        $v = Invoke-RestMethod -Uri "$u/api/version" -TimeoutSec 3 -ErrorAction Stop
        if (Get-Prop $v 'version') { $isOllama = $true }
    } catch { }
    if ($isOllama) {
        if ($endpoints[$probeName].context -le 0) {
            $endpoints[$probeName].context = 32768
            Write-Host "[WARN] Ollama never reports its context length; recorded 32768 for '$probeName'. Set OLLAMA_CONTEXT_LENGTH=32768 (or more) on the Ollama side, or re-run with -Context N to match what Ollama actually uses -- a mismatch makes Ollama truncate prompts silently." -ForegroundColor Yellow
        }
        if (-not $endpoints[$probeName].model) {
            Write-Host "[WARN] Ollama lists every pulled model; pin the one to use with -Model <name:tag> (it must support tools)." -ForegroundColor Yellow
        }
    }
}

$cfgObj = [ordered]@{ default = $defaultName; endpoints = $endpoints }
[System.IO.File]::WriteAllText($cfgPath, ($cfgObj | ConvertTo-Json -Depth 5), $utf8NoBom)
foreach ($k in $endpoints.Keys) {
    $mark = ' '
    if ($k -eq $defaultName) { $mark = '*' }
    $e = $endpoints[$k]
    $extra = ''
    if ($e.model)   { $extra += " model $($e.model)" }
    if ($e.context) { $extra += " context $($e.context)" }
    Write-Host "[OK] $mark $k -> $($e.upstream)$extra" -ForegroundColor Green
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
    'rem claude-local: Claude Code on a self-hosted model server. Docs: the README.md next to claude-local.ps1',
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
        $block = "`r`n# claude-local: Claude Code on a self-hosted model server (project-skeleton tools/claude-local/install.ps1)`r`n$line`r`n"
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
Write-Host "[NEXT] Open a NEW terminal, then:   claude-local            (default endpoint '$defaultName', falls back to the others)" -ForegroundColor Gray
Write-Host "[NEXT]                              claude-local --list     (every endpoint, reachability, model, context)" -ForegroundColor Gray
Write-Host "[NEXT]                              claude-local -e <name>  (a specific endpoint)" -ForegroundColor Gray
Write-Host "[NEXT] Request log: $ClaudeDir\logs\shim.log" -ForegroundColor Gray
Write-Host ""
