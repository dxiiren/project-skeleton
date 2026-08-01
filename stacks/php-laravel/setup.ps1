#!/usr/bin/env pwsh

# @@PROJECT_TITLE@@ Bootstrap Setup
#
# Installs all required development tools for local development.
# Works on a FRESH PC -- only prerequisites are PowerShell and winget.
# Safe to re-run (idempotent) -- skips tools that are already installed.
#
# Usage: pwsh ./setup.ps1   or   powershell -ExecutionPolicy Bypass -File ./setup.ps1
# Note: run from PowerShell, NOT cmd.exe.

$ErrorActionPreference = 'Stop'

# PowerShell 7.3+ treats native-command stderr output as a terminating error when
# ErrorActionPreference is 'Stop'. PHP, composer, and a few other tools write
# non-fatal warnings to stderr -- disable this behavior so our [FAIL] messages
# are driven by exit codes, not by whether stderr was touched.
$PSNativeCommandUseErrorActionPreference = $false

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

Write-Host ""
Write-Host "@@PROJECT_TITLE@@ Bootstrap Setup" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# ---------- 0. Prerequisites check ----------
Refresh-Path
$hasWinget = Test-Command "winget"
if (-not $hasWinget) {
    Write-Host "[WARN] winget not found. Auto-install for Git/Node will be skipped." -ForegroundColor Yellow
    Write-Host "       Install App Installer from the Microsoft Store to enable winget." -ForegroundColor DarkGray
}

# ---------- 1. Git ----------
Refresh-Path
if (Test-Command "git") {
    Write-Host "[OK] Git already installed: $(git --version)" -ForegroundColor Green
} elseif ($hasWinget) {
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

# ---------- 2. Node.js (LTS) ----------
# Needed for `npm install` + `npm run build` (Vite asset build).
Refresh-Path
if (Test-Command "node") {
    Write-Host "[OK] Node.js already installed: $(node -v)" -ForegroundColor Green
} elseif ($hasWinget) {
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

# ---------- 3. Claude Code CLI ----------
Refresh-Path
if (Test-Command "claude") {
    $claudeVer = & claude --version 2>&1 | Select-Object -First 1
    Write-Host "[OK] Claude Code already installed: $claudeVer" -ForegroundColor Green
} else {
    Write-Host "[INSTALL] Installing Claude Code via npm..." -ForegroundColor Yellow
    $savedEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & npm install -g "@anthropic-ai/claude-code" 2>&1 | Out-Host
    $ErrorActionPreference = $savedEAP
    Refresh-Path
    if (Test-Command "claude") {
        $claudeVer = & claude --version 2>&1 | Select-Object -First 1
        Write-Host "[OK] Claude Code installed: $claudeVer" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Claude Code install failed -- check npm output above" -ForegroundColor Yellow
    }
}

# ---------- 4. uv (Python package manager / tool runner) ----------
Refresh-Path
if (Test-Command "uv") {
    $uvVer = & uv --version 2>&1 | Select-Object -First 1
    Write-Host "[OK] uv already installed: $uvVer" -ForegroundColor Green
} else {
    Write-Host "[INSTALL] Installing uv..." -ForegroundColor Yellow
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    Refresh-Path
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

# ---------- 5. Python (used by .claude tooling, e.g. the statusline + skill scripts) ----------
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

# ---------- 6. Microsoft Visual C++ Redistributable (required by PHP) ----------
# PHP @@PHP_MINOR@@ is linked against a recent MSVC runtime. If SYSTEM32\VCRUNTIME140.dll
# is older, PHP aborts at startup with a "not compatible with this PHP build" warning.
# Registry check FIRST: calling winget when the redist is already present attempts an
# in-place upgrade, which throws a UAC elevation prompt and hangs unattended runs forever.
$vcInstalled = $false
try {
    $vcKey = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction Stop
    $vcInstalled = ($vcKey.Installed -eq 1)
} catch {}
if ($vcInstalled) {
    Write-Host "[OK] VC++ 2015-2022 Redistributable (x64) already installed (v$($vcKey.Major).$($vcKey.Minor).$($vcKey.Bld))" -ForegroundColor Green
} elseif ($hasWinget) {
    if (Install-Winget "Microsoft.VCRedist.2015+.x64" "VC++ 2015-2022 Redistributable (x64)") {
        Write-Host "[OK] VC++ 2015-2022 Redistributable (x64) installed" -ForegroundColor Green
    } else {
        Write-Host "[WARN] VC++ redist install returned a non-success code -- PHP may fail to start. Install manually from https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Yellow
    }
} else {
    Write-Host "[WARN] winget unavailable -- cannot verify VC++ redist. Install manually from https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Yellow
}

# ---------- 7. PHP @@PHP_MINOR@@ ----------
# Downloaded directly from php.net rather than via winget: the winget manifest pins
# specific point releases and php.net rotates each patch zip out of its download
# server when the next patch ships -- so winget installs break with a 404 within
# weeks of every PHP release. The "latest" redirect on php.net is self-healing.
$phpDir = Join-Path $env:LOCALAPPDATA "Programs\php-@@PHP_MINOR@@"
$phpExe = Join-Path $phpDir "php.exe"

Refresh-Path
if (Test-Path $phpExe) {
    $phpVer = & $phpExe --version 2>&1 | Select-Object -First 1
    Write-Host "[OK] PHP @@PHP_MINOR@@ already installed: $phpVer" -ForegroundColor Green
} else {
    $phpZipUrl = "https://windows.php.net/downloads/releases/latest/php-@@PHP_MINOR@@-Win32-@@PHP_VS_TAG@@-x64-latest.zip"
    $zipPath = Join-Path $env:TEMP "php-@@PHP_MINOR@@-latest.zip"
    Write-Host "[INSTALL] Downloading PHP @@PHP_MINOR@@ (latest patch) from php.net..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $phpZipUrl -OutFile $zipPath -UseBasicParsing
        if (-not (Test-Path $phpDir)) { New-Item -ItemType Directory -Path $phpDir -Force | Out-Null }
        Expand-Archive -Path $zipPath -DestinationPath $phpDir -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        if (Test-Path $phpExe) {
            $phpVer = & $phpExe --version 2>&1 | Select-Object -First 1
            Write-Host "[OK] PHP @@PHP_MINOR@@ installed: $phpVer" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] PHP extract succeeded but php.exe missing at $phpExe" -ForegroundColor Red
        }
    } catch {
        Write-Host "[FAIL] PHP download/extract failed: $_" -ForegroundColor Red
    }
}

# Laravel + Composer both need a handful of extensions enabled. The fresh PHP
# zip has no php.ini -- only ini-development / ini-production templates -- so
# we copy the development template and append the extensions we need.
if (Test-Path $phpExe) {
    $phpIni = Join-Path $phpDir "php.ini"
    $phpIniTemplate = Join-Path $phpDir "php.ini-development"
    if ((-not (Test-Path $phpIni)) -and (Test-Path $phpIniTemplate)) {
        Copy-Item $phpIniTemplate $phpIni
        $override = @"

; --- @@REPO_SLUG@@ setup.ps1 overrides ---
; Only extensions bundled in the official windows.php.net zip are listed here.
extension_dir = "ext"
extension=curl
extension=exif
extension=fileinfo
extension=gd
extension=intl
extension=mbstring
extension=openssl
extension=pdo_sqlite
extension=sodium
extension=sqlite3
extension=zip

upload_max_filesize = 20M
post_max_size = 20M
memory_limit = 256M
"@
        Add-Content -Path $phpIni -Value $override
        Write-Host "[INFO] Wrote php.ini with Laravel-required extensions" -ForegroundColor Cyan
    }
    Add-UserPath $phpDir
    if ($env:Path -notlike "$phpDir;*") {
        $env:Path = "$phpDir;$env:Path"
    }
}

# ---------- 8. Composer ----------
# Downloaded directly from getcomposer.org as composer.phar. A composer.bat
# wrapper next to php.exe lets `composer` run anywhere once $phpDir is on PATH.
Refresh-Path
$composerPhar = Join-Path $phpDir "composer.phar"
$composerBat  = Join-Path $phpDir "composer.bat"

if ((Test-Path $composerPhar) -and (Test-Path $composerBat)) {
    $composerVer = & $phpExe $composerPhar --version 2>&1 | Select-Object -First 1
    Write-Host "[OK] Composer already installed: $composerVer" -ForegroundColor Green
} elseif (Test-Path $phpExe) {
    Write-Host "[INSTALL] Downloading Composer from getcomposer.org..." -ForegroundColor Yellow
    $installerPath = Join-Path $env:TEMP "composer-installer.php"
    try {
        Invoke-WebRequest -Uri "https://getcomposer.org/installer" -OutFile $installerPath -UseBasicParsing
        & $phpExe $installerPath --install-dir=$phpDir --filename=composer.phar 2>&1 | Out-Host
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        if (Test-Path $composerPhar) {
            # composer.bat forwards all args to `php composer.phar`. %~dp0 resolves
            # to the directory containing composer.bat -- which is $phpDir -- so the
            # wrapper works even if another PHP ends up earlier on PATH.
            @"
@echo off
"%~dp0php.exe" "%~dp0composer.phar" %*
"@ | Set-Content -Path $composerBat -Encoding ASCII
            $composerVer = & $phpExe $composerPhar --version 2>&1 | Select-Object -First 1
            Write-Host "[OK] Composer installed: $composerVer" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Composer installer ran but composer.phar missing at $composerPhar" -ForegroundColor Red
        }
    } catch {
        Write-Host "[FAIL] Composer download failed: $_" -ForegroundColor Red
    }
} else {
    Write-Host "[WARN] Composer skipped -- PHP not available" -ForegroundColor Yellow
}

# ---------- 9. just (task runner) ----------
Refresh-Path
if (Test-Command "just") {
    $justVer = & just --version 2>&1 | Select-Object -First 1
    Write-Host "[OK] just already installed: $justVer" -ForegroundColor Green
} else {
    Write-Host "[INSTALL] Installing just..." -ForegroundColor Yellow
    & uv tool install rust-just
    Refresh-Path
    if (Test-Command "just") {
        $justVer = & just --version 2>&1 | Select-Object -First 1
        Write-Host "[OK] just installed: $justVer" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] just installed but not found on PATH" -ForegroundColor Red
        exit 1
    }
}

# ---------- 10. GitHub CLI ----------
# Used by the /create-pr and /commit skills. Run `gh auth login` once interactively.
Refresh-Path
if (Test-Command "gh") {
    $ghVer = & gh --version 2>&1 | Select-Object -First 1
    Write-Host "[OK] GitHub CLI already installed: $ghVer" -ForegroundColor Green
} elseif ($hasWinget) {
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

# ---------- 11. Claude MCP config (.mcp.json from stub) ----------
Write-Host ""
Write-Host "Configuring Claude MCP servers..." -ForegroundColor Cyan
$mcpStub = Join-Path $PSScriptRoot ".mcp.json.stub"
$mcpJson = Join-Path $PSScriptRoot ".mcp.json"
if (Test-Path $mcpJson) {
    Write-Host "[OK] .mcp.json already exists -- leaving your local config untouched." -ForegroundColor Green
} elseif (Test-Path $mcpStub) {
    Copy-Item $mcpStub $mcpJson
    Write-Host "[OK] Created .mcp.json from .mcp.json.stub (git-ignored -- never committed)." -ForegroundColor Green
    Write-Host "     Fill REPLACE_WITH_* placeholders (GitHub PAT) by hand." -ForegroundColor DarkGray
} else {
    Write-Host "[INFO] No .mcp.json.stub found -- skipping MCP setup." -ForegroundColor Cyan
}

# ---------- Final verification ----------
Refresh-Path
Write-Host ""
Write-Host "Verifying installations..." -ForegroundColor Cyan
$missing = @()
foreach ($tool in @('git','node','npm','claude','uv','just','gh')) {
    if (Test-Command $tool) {
        Write-Host "  [OK] $tool" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $tool" -ForegroundColor Red
        $missing += $tool
    }
}
if (Test-Path $phpExe) {
    Write-Host "  [OK] php ($phpExe)" -ForegroundColor Green
} else {
    Write-Host "  [MISSING] php" -ForegroundColor Red
    $missing += 'php'
}
if (Test-Path $composerPhar) {
    Write-Host "  [OK] composer ($composerPhar)" -ForegroundColor Green
} else {
    Write-Host "  [MISSING] composer" -ForegroundColor Red
    $missing += 'composer'
}
if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "[WARN] Some tools not found on PATH in this session: $($missing -join ', ')" -ForegroundColor Yellow
    Write-Host "       This usually means PATH updates need a new shell session." -ForegroundColor Yellow
    Write-Host "       CLOSE AND REOPEN PowerShell and run them to confirm." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ""

# ---------- Next steps (manual) ----------
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. CLOSE AND REOPEN PowerShell so PATH picks up PHP + Composer." -ForegroundColor Gray
Write-Host "  2. Bootstrap the app (composer + npm + .env + sqlite + migrate):" -ForegroundColor Gray
Write-Host "       just bootstrap" -ForegroundColor DarkGray
Write-Host "  3. Start the dev server on http://127.0.0.1:@@PORT@@ :" -ForegroundColor Gray
Write-Host "       just start" -ForegroundColor DarkGray
Write-Host "  4. Login to Claude Code in the repo:  claude" -ForegroundColor Gray
Write-Host ""
