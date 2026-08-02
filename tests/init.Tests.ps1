# Pester suite for init.ps1 — locks the observable scaffold behavior.
#
# Run with:  just test        (requires Pester 5+ in pwsh:
#                              Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck)
#
# Every Describe copies the whole skeleton into a fresh folder under $env:TEMP and runs
# init.ps1 THERE in a child pwsh — the working tree is never scaffolded, and all temp
# copies are deleted in the file-level AfterAll.
#
# NOTE ON TOKENS: this file must never contain a literal doubled at-sign, or the
# placeholder sweep documented in GROUNDING.md would flag it. Token assertions therefore
# use the sweep's own self-excluding regex form, e.g. '@[@]PORT@[@]'.

BeforeAll {
    $script:RepoRoot  = Split-Path -Parent $PSScriptRoot
    $script:TempRoots = [System.Collections.Generic.List[string]]::new()

    function New-SkeletonCopy {
        $dest = Join-Path $env:TEMP ("skeleton-pester-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $dest | Out-Null
        Get-ChildItem -Path $script:RepoRoot -Force |
            Where-Object { $_.Name -ne '.git' } |
            ForEach-Object { Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force }
        $script:TempRoots.Add($dest)
        return $dest
    }

    function Invoke-Init {
        param(
            [Parameter(Mandatory)] [string]   $Root,
            [Parameter(Mandatory)] [string[]] $Arguments
        )
        $output = & pwsh -NoProfile -File (Join-Path $Root 'init.ps1') @Arguments 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

AfterAll {
    foreach ($t in $script:TempRoots) {
        if (Test-Path $t) { Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue }
    }
}

Describe 'init.ps1 — static stack (server-shaped)' {

    BeforeAll {
        $copy   = New-SkeletonCopy
        $result = Invoke-Init -Root $copy -Arguments @(
            '-Name', 'test-x', '-Stack', 'static', '-Port', '8433', '-Docroot', '.')
        $justfile = if (Test-Path (Join-Path $copy 'justfile')) {
            [System.IO.File]::ReadAllText((Join-Path $copy 'justfile')) } else { '' }
        $setup    = if (Test-Path (Join-Path $copy 'setup.ps1')) {
            [System.IO.File]::ReadAllText((Join-Path $copy 'setup.ps1')) } else { '' }
    }

    It 'completes successfully' {
        $result.ExitCode | Should -Be 0
        $result.Output   | Should -Match 'Scaffold complete'
    }

    It 'puts the stack justfile and setup.ps1 at the root' {
        Join-Path $copy 'justfile'  | Should -Exist
        Join-Path $copy 'setup.ps1' | Should -Exist
    }

    It 'leaves zero mechanical tokens in justfile and setup.ps1' {
        $justfile | Should -Not -Match '@[@]'
        $setup    | Should -Not -Match '@[@]'
    }

    It 'fills port, title and docroot with the given values' {
        $justfile | Should -Match "env_var_or_default\('PORT', '8433'\)"
        $justfile.Contains("\.'") | Should -BeTrue   # -Docroot . -> ...justfile_directory()}}\.
        $justfile | Should -Match 'Test X justfile'
        $setup    | Should -Match 'Test X'
    }

    It 'creates CLAUDE.md and README.md from the templates (templates removed)' {
        Join-Path $copy 'CLAUDE.md' | Should -Exist
        Join-Path $copy 'README.md' | Should -Exist
        Join-Path $copy 'CLAUDE.md.template'       | Should -Not -Exist
        Join-Path $copy 'README.project.template'  | Should -Not -Exist
    }

    It 'moves GROUNDING.md and the stack NOTES.md into .docs/05-reference' {
        Join-Path $copy '.docs/05-reference/conventions.md' | Should -Exist
        Join-Path $copy '.docs/05-reference/stack-notes.md' | Should -Exist
        Join-Path $copy 'GROUNDING.md' | Should -Not -Exist
    }

    It 'removes the scaffolding: stacks/, init.ps1, gitignore-block.txt, tests/' {
        Join-Path $copy 'stacks'              | Should -Not -Exist
        Join-Path $copy 'init.ps1'            | Should -Not -Exist
        Join-Path $copy 'gitignore-block.txt' | Should -Not -Exist
        Join-Path $copy 'tests'               | Should -Not -Exist
    }

    It 'merges the gitignore block into .gitignore' {
        $gi = Get-Content (Join-Path $copy '.gitignore')
        $gi | Should -Contain '.mcp.json'
        $gi | Should -Contain '.claude/settings.local.json'
        $gi | Should -Contain '.claude/workspace/'
    }

    It 'fills the mechanical tokens in CLAUDE.md' {
        $claude = [System.IO.File]::ReadAllText((Join-Path $copy 'CLAUDE.md'))
        $claude | Should -Not -Match '@[@]PORT@[@]'
        $claude | Should -Not -Match '@[@]REPO_SLUG@[@]'
        $claude | Should -Match 'test-x'
        $claude | Should -Match '8433'
    }

    It 'leaves the content tokens for /ground-project, as designed' {
        $claude = [System.IO.File]::ReadAllText((Join-Path $copy 'CLAUDE.md'))
        $readme = [System.IO.File]::ReadAllText((Join-Path $copy 'README.md'))
        $claude | Should -Match '@[@]WHAT_IT_IS@[@]'
        $claude | Should -Match '@[@]STACK_TABLE_ROWS@[@]'
        $readme | Should -Match '@[@]QUICKSTART_STEPS@[@]'
        $readme | Should -Match '@[@]COMMANDS_ROWS@[@]'
    }

    It 'skips conventions.md during the token fill (its token table survives)' {
        $conv = [System.IO.File]::ReadAllText((Join-Path $copy '.docs/05-reference/conventions.md'))
        $conv | Should -Match '@[@]PROJECT_TITLE@[@]'
        $conv | Should -Match '@[@]PORT@[@]'
    }
}

Describe 'init.ps1 — cli-java stack (no port)' {

    BeforeAll {
        $copy   = New-SkeletonCopy
        $result = Invoke-Init -Root $copy -Arguments @(
            '-Name', 'test-y', '-Stack', 'cli-java', '-MainClass', 'Main')
        $justfile = if (Test-Path (Join-Path $copy 'justfile')) {
            [System.IO.File]::ReadAllText((Join-Path $copy 'justfile')) } else { '' }
        $setup    = if (Test-Path (Join-Path $copy 'setup.ps1')) {
            [System.IO.File]::ReadAllText((Join-Path $copy 'setup.ps1')) } else { '' }
    }

    It 'completes successfully' {
        $result.ExitCode | Should -Be 0
        $result.Output   | Should -Match 'Scaffold complete'
    }

    It 'puts the stack justfile and setup.ps1 at the root, tokens filled' {
        Join-Path $copy 'justfile'  | Should -Exist
        Join-Path $copy 'setup.ps1' | Should -Exist
        $justfile | Should -Not -Match '@[@]'
        $setup    | Should -Not -Match '@[@]'
    }

    It 'wires the main class into the run recipes' {
        $justfile | Should -Match 'java -cp out Main'
        $justfile | Should -Match 'Test Y justfile'
    }

    It 'creates CLAUDE.md and README.md and removes the scaffolding' {
        Join-Path $copy 'CLAUDE.md' | Should -Exist
        Join-Path $copy 'README.md' | Should -Exist
        Join-Path $copy 'stacks'    | Should -Not -Exist
        Join-Path $copy 'init.ps1'  | Should -Not -Exist
        Join-Path $copy 'tests'     | Should -Not -Exist
    }

    It 'leaves the content tokens for /ground-project, as designed' {
        $claude = [System.IO.File]::ReadAllText((Join-Path $copy 'CLAUDE.md'))
        $claude | Should -Match '@[@]WHAT_IT_IS@[@]'
        $claude | Should -Match '@[@]TOOLCHAIN_SUMMARY@[@]'
    }
}

Describe 'init.ps1 — re-run guard' {

    BeforeAll {
        $copy  = New-SkeletonCopy
        $first = Invoke-Init -Root $copy -Arguments @(
            '-Name', 'test-x', '-Stack', 'static', '-Port', '8433', '-Docroot', '.')
        # init.ps1 deletes itself on success — put a fresh copy back to simulate someone
        # re-running the scaffolder on an already-scaffolded project.
        Copy-Item (Join-Path $script:RepoRoot 'init.ps1') (Join-Path $copy 'init.ps1')
        $second = Invoke-Init -Root $copy -Arguments @(
            '-Name', 'test-x', '-Stack', 'static', '-Port', '8433', '-Docroot', '.')
    }

    It 'first run succeeds' {
        $first.ExitCode | Should -Be 0
    }

    It 'second run refuses with exit 1' {
        $second.ExitCode | Should -Be 1
        $second.Output   | Should -Match 'already scaffolded'
    }

    It 'second run leaves the scaffolded project untouched' {
        # The guard fires before any copy/move/fill step: the root justfile is still the
        # filled stack justfile, and nothing was re-tokenized or removed.
        $justfile = [System.IO.File]::ReadAllText((Join-Path $copy 'justfile'))
        $justfile | Should -Not -Match '@[@]'
        $justfile | Should -Match 'Test X justfile'
        Join-Path $copy 'CLAUDE.md' | Should -Exist
        Join-Path $copy 'README.md' | Should -Exist
    }
}
