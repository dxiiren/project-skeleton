#!/usr/bin/env pwsh

# project-skeleton init.ps1 -- mechanical scaffold step
#
# Turns a clone of project-skeleton into YOUR project: picks a stack, copies its
# setup.ps1 + justfile in, fills the mechanical @@TOKENS@@ everywhere, merges the
# gitignore block, removes the scaffolding, and deletes itself.
#
# Usage (interactive):      .\init.ps1
# Usage (non-interactive):  .\init.ps1 -Name my-app -Stack static -Port 8433 -Docroot .
# Optional:                 -FreshGit   (wipe the skeleton's .git and `git init -b main`)
#
# Content tokens (@@WHAT_IT_IS@@, @@STACK_TABLE_ROWS@@, ...) are deliberately LEFT
# unfilled -- the /ground-project skill fills those from the real code afterwards.

param(
    [string]$Name,
    [string]$Stack,
    [int]$Port,
    [string]$MainClass,
    [string]$Src,
    [string]$Docroot,
    [switch]$FreshGit
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$root = $PSScriptRoot

Write-Host ""
Write-Host "project-skeleton init" -ForegroundColor Cyan
Write-Host "=====================" -ForegroundColor Cyan
Write-Host ""

# ---------- Guard: refuse to run twice ----------
$rootJustfile = Join-Path $root "justfile"
if (Test-Path $rootJustfile) {
    $jf = [System.IO.File]::ReadAllText($rootJustfile)
    if ($jf -notmatch '@@') {
        Write-Host "[FAIL] A root justfile already exists and contains no @@ tokens -- this project looks already scaffolded." -ForegroundColor Red
        Write-Host "       Refusing to run. Delete the justfile first if you really want to re-scaffold." -ForegroundColor DarkGray
        exit 1
    }
}

$stacksDir = Join-Path $root "stacks"
if (-not (Test-Path $stacksDir)) {
    Write-Host "[FAIL] stacks\ folder not found -- is this an intact project-skeleton clone?" -ForegroundColor Red
    exit 1
}
$validStacks = @(Get-ChildItem -Path $stacksDir -Directory | Select-Object -ExpandProperty Name)

# ---------- Which stacks need which inputs ----------
$needsPort      = @('php-laravel','php-plain','node-vite','node-nuxt','static','cli-jupyter')
$needsDocroot   = @('php-plain','static')
$needsMainClass = @('cli-java','vbnet')
$needsSrc       = @('cli-cpp','vbnet')
$mainClassLabel = @{ 'cli-java' = 'Main class (the class containing main(), e.g. Main)'
                     'vbnet'    = 'WinForms project name (project folder AND exe base name, e.g. My App)' }
$srcLabel       = @{ 'cli-cpp'  = 'Source file name(s) passed to g++ (e.g. main.cpp)'
                     'vbnet'    = 'Solution file name including .sln (e.g. My App.sln)' }

# ---------- Collect inputs (prompt for anything missing) ----------
if (-not $Name) {
    $defaultName = Split-Path $root -Leaf
    $Name = Read-Host "Project name (kebab-case) [$defaultName]"
    if (-not $Name) { $Name = $defaultName }
}

while (-not $Stack -or $validStacks -notcontains $Stack) {
    Write-Host "[INFO] Available stacks: $($validStacks -join ', ')" -ForegroundColor Cyan
    $Stack = Read-Host "Stack"
    if ($validStacks -notcontains $Stack) {
        Write-Host "[WARN] '$Stack' is not a stack in stacks\ -- pick one from the list." -ForegroundColor Yellow
        $Stack = $null
    }
}

if (($needsPort -contains $Stack) -and (-not $Port)) {
    $suggested = Get-Random -Minimum 8200 -Maximum 9000
    $answer = Read-Host "Port (never 3000/8000/5173) [$suggested]"
    if ($answer) { $Port = [int]$answer } else { $Port = $suggested }
}

if (($needsMainClass -contains $Stack) -and (-not $MainClass)) {
    $MainClass = Read-Host $mainClassLabel[$Stack]
    if (-not $MainClass) { Write-Host "[FAIL] This stack needs that value." -ForegroundColor Red; exit 1 }
}

if (($needsSrc -contains $Stack) -and (-not $Src)) {
    $Src = Read-Host $srcLabel[$Stack]
    if (-not $Src) { Write-Host "[FAIL] This stack needs that value." -ForegroundColor Red; exit 1 }
}

if (($needsDocroot -contains $Stack) -and (-not $Docroot)) {
    $answer = Read-Host "Docroot (folder served; usually .) [.]"
    if ($answer) { $Docroot = $answer } else { $Docroot = '.' }
}

# Derive slug (kebab) + title (Title Case)
$slug  = ($Name -replace '[_\s]+', '-').ToLower()
$title = (($slug -split '-') | Where-Object { $_ } | ForEach-Object {
             $_.Substring(0,1).ToUpper() + $_.Substring(1) }) -join ' '

Write-Host ""
Write-Host "[INFO] Scaffolding '$title' ($slug) as stack '$Stack'$(if ($Port) { " on port $Port" })" -ForegroundColor Cyan
Write-Host ""

# ---------- 1. Copy the stack's files into place ----------
$stackDir = Join-Path $stacksDir $Stack
Copy-Item (Join-Path $stackDir "setup.ps1") (Join-Path $root "setup.ps1") -Force
Copy-Item (Join-Path $stackDir "justfile")  (Join-Path $root "justfile")  -Force
Write-Host "[OK] Copied stacks\$Stack\setup.ps1 + justfile to the root" -ForegroundColor Green

$refDir = Join-Path $root ".docs\05-reference"
if (-not (Test-Path $refDir)) { New-Item -ItemType Directory -Path $refDir -Force | Out-Null }
Copy-Item (Join-Path $stackDir "NOTES.md") (Join-Path $refDir "stack-notes.md") -Force
Write-Host "[OK] stacks\$Stack\NOTES.md -> .docs\05-reference\stack-notes.md" -ForegroundColor Green

# ---------- 2. GROUNDING.md -> .docs\05-reference\conventions.md ----------
# Moved as-is and EXCLUDED from the token fill below: its token table documents the
# literal tokens and must survive.
Move-Item (Join-Path $root "GROUNDING.md") (Join-Path $refDir "conventions.md") -Force
Write-Host "[OK] GROUNDING.md -> .docs\05-reference\conventions.md" -ForegroundColor Green

# ---------- 3. Templates -> live files ----------
Move-Item (Join-Path $root "CLAUDE.md.template") (Join-Path $root "CLAUDE.md") -Force
# The skeleton's own README is intentionally REPLACED by the project README template.
Move-Item (Join-Path $root "README.project.template") (Join-Path $root "README.md") -Force
Write-Host "[OK] CLAUDE.md.template -> CLAUDE.md, README.project.template -> README.md" -ForegroundColor Green

# ---------- 4. Remove the remaining scaffolding (before the token fill) ----------
Remove-Item -Recurse -Force $stacksDir
Write-Host "[OK] Removed stacks\" -ForegroundColor Green

# The skeleton's own Pester suite (tests\init.Tests.ps1) is scaffolding too -- a
# scaffolded project must not inherit tests that target the now-deleted init.ps1.
# Remove only the skeleton's file (an imported project may own other tests), then the
# tests\ folder if that emptied it. (The skeleton's dev justfile needs no removal:
# step 1 already overwrote it with the stack's justfile.)
$testsDir  = Join-Path $root "tests"
$skelTests = Join-Path $testsDir "init.Tests.ps1"
if (Test-Path $skelTests) {
    Remove-Item -Force $skelTests
    if (-not (Get-ChildItem -Path $testsDir -Force)) { Remove-Item -Force $testsDir }
    Write-Host "[OK] Removed tests\init.Tests.ps1 (the skeleton's own Pester suite)" -ForegroundColor Green
}

# ---------- 5. Fill the mechanical tokens ----------
$tokens = [ordered]@{
    '@@PROJECT_TITLE@@' = $title
    '@@REPO_SLUG@@'     = $slug
    '@@PHP_MINOR@@'     = '8.4'
    '@@PHP_VS_TAG@@'    = 'vs17'
}
if ($Port)      { $tokens['@@PORT@@']       = "$Port" }
if ($MainClass) { $tokens['@@MAIN_CLASS@@'] = $MainClass }
if ($Src)       { $tokens['@@SRC@@']        = $Src }
if ($Docroot)   { $tokens['@@DOCROOT@@']    = $Docroot }

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$conventionsPath = (Join-Path $refDir "conventions.md")
$selfPath = $PSCommandPath

# Fill scope: root-level FILES + everything under .docs\ and .claude\ (never user
# source dirs, never .git). Skip this script and conventions.md.
$targets = @(Get-ChildItem -Path $root -File)
foreach ($sub in @('.docs', '.claude')) {
    $subPath = Join-Path $root $sub
    if (Test-Path $subPath) { $targets += Get-ChildItem -Path $subPath -Recurse -File }
}

$filled = 0
foreach ($f in $targets) {
    if ($f.FullName -eq $selfPath) { continue }
    if ($f.FullName -eq (Get-Item $conventionsPath).FullName) { continue }
    $text = [System.IO.File]::ReadAllText($f.FullName)
    if ($text.IndexOf([char]0) -ge 0) { continue }   # binary safety net
    $new = $text
    foreach ($k in $tokens.Keys) { $new = $new.Replace($k, $tokens[$k]) }
    if ($new -ne $text) {
        [System.IO.File]::WriteAllText($f.FullName, $new, $utf8NoBom)
        $filled++
    }
}
Write-Host "[OK] Filled mechanical tokens in $filled file(s)" -ForegroundColor Green

# ---------- 6. Merge gitignore-block.txt into .gitignore ----------
$blockPath = Join-Path $root "gitignore-block.txt"
$giPath    = Join-Path $root ".gitignore"
$giLines   = @()
if (Test-Path $giPath) { $giLines = @(Get-Content $giPath) }
$appended = 0
foreach ($line in Get-Content $blockPath) {
    if ($giLines -notcontains $line) {
        Add-Content -Path $giPath -Value $line -Encoding utf8
        $appended++
    }
}
Remove-Item $blockPath -Force
Write-Host "[OK] .gitignore merged ($appended line(s) appended); gitignore-block.txt removed" -ForegroundColor Green

# ---------- 7. Fresh git history (optional) ----------
if ($FreshGit) {
    $gitDir = Join-Path $root ".git"
    if (Test-Path $gitDir) { Remove-Item -Recurse -Force $gitDir }
    $savedEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & git init -b main $root 2>&1 | Out-Null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $savedEAP
    if ($code -eq 0) {
        Write-Host "[OK] Fresh git history: git init -b main" -ForegroundColor Green
    } else {
        Write-Host "[WARN] git init failed (exit $code) -- run 'git init -b main' yourself." -ForegroundColor Yellow
    }
}

# ---------- Done ----------
Write-Host ""
Write-Host "Scaffold complete." -ForegroundColor Green
Write-Host "[INFO] Content tokens (WHAT_IT_IS, STACK_TABLE_ROWS, LAYOUT_TREE, ...) are still" -ForegroundColor Cyan
Write-Host "       unfilled in CLAUDE.md / README.md / .docs -- that is EXPECTED." -ForegroundColor Cyan
Write-Host "       /ground-project fills them from the real code." -ForegroundColor Cyan
Write-Host ""
Write-Host "[NEXT] 1. One-time machine setup:   pwsh ./setup.ps1" -ForegroundColor Gray
Write-Host "[NEXT] 2. Open Claude Code:         claude" -ForegroundColor Gray
Write-Host "[NEXT] 3. Ground the kit:           /ground-project" -ForegroundColor Gray
Write-Host ""

# ---------- Delete this script LAST ----------
Remove-Item $selfPath -Force
