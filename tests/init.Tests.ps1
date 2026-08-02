# Pester suite for init.ps1 — locks the observable scaffold behavior.
#
# Run with:  just test        (requires Pester 5+ in pwsh:
#                              Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck)
#
# Every Describe copies the whole skeleton into a fresh folder under $env:TEMP and runs
# init.ps1 THERE in a child pwsh — the working tree is never scaffolded, and all temp
# copies are deleted in the file-level AfterAll.
#
# Coverage: static and cli-java get hand-written Describes (they assert the shared
# scaffold steps in full); the other seven stacks are driven by $stackMatrix further
# down, one Describe each. Between them all 9 stacks and every mechanical token are
# exercised. The failure paths (FreshGit, missing required value, missing stacks folder)
# have their own Describes at the end.
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

    # Invoke-Init with an EMPTY stdin stream, so any Read-Host init.ps1 reaches returns
    # empty IMMEDIATELY instead of blocking the suite on a prompt nobody can answer.
    # Use it only for prompts whose empty answer TERMINATES init (the missing
    # MainClass/Src guards, which print "[FAIL] This stack needs that value." and exit 1).
    # NEVER point it at an invalid -Stack: that prompt LOOPS on a bad/empty answer
    # (init.ps1's `while (-not $Stack -or ...)`) and would spin forever.
    function Invoke-InitNoInput {
        param(
            [Parameter(Mandatory)] [string]   $Root,
            [Parameter(Mandatory)] [string[]] $Arguments
        )
        $output = '' | & pwsh -NoProfile -File (Join-Path $Root 'init.ps1') @Arguments 2>&1 | Out-String
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

# ===================================================================================
# Stack matrix — one full scaffold per stack NOT covered by the hand-written Describes
# above. Those two (static, cli-java) already lock the stack-independent scaffold steps
# (template promotion, doc moves, scaffolding removal, gitignore merge, content-token
# survival); repeating all of that seven more times would add runtime, not coverage.
# What is stack-SPECIFIC — and what this matrix locks — is the token fill: every stack's
# own tokens must come out carrying the value actually passed on the command line.
#
# Defined at FILE scope on purpose: Pester's discovery phase runs before any BeforeAll,
# and -ForEach data must exist by then. One Describe per row, one It per Expect row, so
# a failure names the stack, the artifact and the exact token that was not filled.
#
# Expect.Pattern is a REGEX matched against the artifact text AFTER init. Every expected
# value is either passed in Arguments or, for PHP_MINOR / PHP_VS_TAG, the 8.4 / vs17 pair
# init.ps1 hardcodes. Project titles are init's Title Case derivation of -Name.
# ===================================================================================
$stackMatrix = @(
    @{
        Stack     = 'cli-cpp'
        Arguments = @('-Name', 'test-cpp', '-Stack', 'cli-cpp', '-Src', 'main.cpp')
        Expect    = @(
            @{ File = 'justfile';  Label = 'the project title';            Pattern = 'Test Cpp justfile' }
            @{ File = 'justfile';  Label = 'the g++ source file (Src)';    Pattern = '-o out\\app\.exe main\.cpp' }
            @{ File = 'setup.ps1'; Label = 'the project title';            Pattern = 'Test Cpp Bootstrap Setup' }
        )
    }
    @{
        Stack     = 'cli-jupyter'
        Arguments = @('-Name', 'test-jup', '-Stack', 'cli-jupyter', '-Port', '8511')
        Expect    = @(
            @{ File = 'justfile';  Label = 'the project title';            Pattern = 'Test Jup justfile' }
            @{ File = 'justfile';  Label = 'the port';                     Pattern = "env_var_or_default\('PORT', '8511'\)" }
            @{ File = 'setup.ps1'; Label = 'the project title';            Pattern = 'Test Jup Bootstrap Setup' }
            @{ File = 'setup.ps1'; Label = 'the port in the next steps';   Pattern = 'Jupyter Lab \(:8511\)' }
        )
    }
    @{
        Stack     = 'node-nuxt'
        Arguments = @('-Name', 'test-nuxt', '-Stack', 'node-nuxt', '-Port', '8522')
        Expect    = @(
            @{ File = 'justfile';  Label = 'the project title';            Pattern = 'Test Nuxt justfile' }
            @{ File = 'justfile';  Label = 'the port';                     Pattern = "env_var_or_default\('PORT', '8522'\)" }
            @{ File = 'setup.ps1'; Label = 'the project title';            Pattern = 'Test Nuxt Bootstrap Setup' }
            @{ File = 'setup.ps1'; Label = 'the port in the next steps';   Pattern = 'dev server \(:8522\)' }
        )
    }
    @{
        Stack     = 'node-vite'
        Arguments = @('-Name', 'test-vite', '-Stack', 'node-vite', '-Port', '8533')
        Expect    = @(
            @{ File = 'justfile';  Label = 'the project title';            Pattern = 'Test Vite justfile' }
            @{ File = 'justfile';  Label = 'the port';                     Pattern = "env_var_or_default\('PORT', '8533'\)" }
            @{ File = 'setup.ps1'; Label = 'the project title';            Pattern = 'Test Vite Bootstrap Setup' }
            @{ File = 'setup.ps1'; Label = 'the port in the next steps';   Pattern = 'dev server \(:8533\)' }
        )
    }
    @{
        Stack     = 'php-laravel'
        Arguments = @('-Name', 'test-laravel', '-Stack', 'php-laravel', '-Port', '8544')
        Expect    = @(
            @{ File = 'justfile';  Label = 'the project title';            Pattern = 'Test Laravel justfile' }
            @{ File = 'justfile';  Label = 'the PHP minor in the php path'; Pattern = '\\Programs\\php-8\.4\\php\.exe' }
            @{ File = 'justfile';  Label = 'the PHP minor in the composer path'; Pattern = '\\Programs\\php-8\.4\\composer\.bat' }
            @{ File = 'justfile';  Label = 'the port';                     Pattern = "env_var_or_default\('PORT', '8544'\)" }
            @{ File = 'setup.ps1'; Label = 'the project title';            Pattern = 'Test Laravel Bootstrap Setup' }
            @{ File = 'setup.ps1'; Label = 'the PHP minor + VS tag in the download URL'; Pattern = 'php-8\.4-Win32-vs17-x64-latest\.zip' }
            @{ File = 'setup.ps1'; Label = 'the repo slug in the php.ini override header'; Pattern = '; --- test-laravel setup\.ps1 overrides ---' }
            @{ File = 'setup.ps1'; Label = 'the port in the next steps';   Pattern = '127\.0\.0\.1:8544' }
        )
    }
    @{
        Stack     = 'php-plain'
        Arguments = @('-Name', 'test-plain', '-Stack', 'php-plain', '-Port', '8555', '-Docroot', 'public')
        Expect    = @(
            @{ File = 'justfile';  Label = 'the project title';            Pattern = 'Test Plain justfile' }
            @{ File = 'justfile';  Label = 'the PHP minor in the php path'; Pattern = '\\Programs\\php-8\.4\\php\.exe' }
            @{ File = 'justfile';  Label = 'the port';                     Pattern = "env_var_or_default\('PORT', '8555'\)" }
            @{ File = 'justfile';  Label = 'the docroot in the serve path'; Pattern = 'justfile_directory\(\)\}\}\\public' }
            @{ File = 'setup.ps1'; Label = 'the project title';            Pattern = 'Test Plain Bootstrap Setup' }
            @{ File = 'setup.ps1'; Label = 'the PHP minor + VS tag in the download URL'; Pattern = 'php-8\.4-Win32-vs17-x64-latest\.zip' }
            @{ File = 'setup.ps1'; Label = 'the repo slug in the php.ini override header'; Pattern = '; --- test-plain setup\.ps1 overrides ---' }
            @{ File = 'setup.ps1'; Label = 'the port in the next steps';   Pattern = '127\.0\.0\.1:8555' }
        )
    }
    @{
        # The only stack needing TWO free-text values, and they are not interchangeable:
        # MainClass is the WinForms project name (folder + exe base), Src is the .sln.
        # Both carry a space on purpose — the documented vbnet values look like 'My App'.
        Stack     = 'vbnet'
        Arguments = @('-Name', 'test-vb', '-Stack', 'vbnet', '-MainClass', 'Lab Runner', '-Src', 'Lab Runner.sln')
        Expect    = @(
            @{ File = 'justfile';  Label = 'the project title';            Pattern = 'Test Vb justfile' }
            @{ File = 'justfile';  Label = 'the solution file (Src)';      Pattern = "sln := 'Lab Runner\.sln'" }
            @{ File = 'justfile';  Label = 'the project name (MainClass) in the output dir'; Pattern = "justfile_directory\(\) \+ '\\Lab Runner\\bin\\Debug'" }
            @{ File = 'justfile';  Label = 'the project name (MainClass) in the exe path'; Pattern = "exe := exe_dir \+ '\\Lab Runner\.exe'" }
            @{ File = 'setup.ps1'; Label = 'the project title';            Pattern = 'Test Vb Bootstrap Setup' }
        )
    }
)

Describe 'init.ps1 — <Stack> stack' -ForEach $stackMatrix {

    BeforeAll {
        $copy   = New-SkeletonCopy
        $result = Invoke-Init -Root $copy -Arguments $Arguments
        # Keyed by the same file names the Expect rows use, so an It can look its
        # artifact up. Test-Path guard + '' fallback: an aborted init must produce a
        # readable assertion failure, not a Pester error inside BeforeAll.
        $artifacts = @{
            'justfile'  = if (Test-Path (Join-Path $copy 'justfile')) {
                [System.IO.File]::ReadAllText((Join-Path $copy 'justfile')) } else { '' }
            'setup.ps1' = if (Test-Path (Join-Path $copy 'setup.ps1')) {
                [System.IO.File]::ReadAllText((Join-Path $copy 'setup.ps1')) } else { '' }
        }
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
        $artifacts['justfile']  | Should -Not -Match '@[@]'
        $artifacts['setup.ps1'] | Should -Not -Match '@[@]'
    }

    It 'fills <Label> in <File>' -ForEach $Expect {
        $artifacts[$File] | Should -Match $Pattern
    }
}

Describe 'init.ps1 — -FreshGit switch' {

    BeforeAll {
        $copy   = New-SkeletonCopy
        # The copy deliberately excludes .git, so this exercises the "no history to wipe,
        # just initialize" half; either way init must end with a repo on branch main.
        $result = Invoke-Init -Root $copy -Arguments @(
            '-Name', 'test-git', '-Stack', 'static', '-Port', '8566', '-Docroot', '.', '-FreshGit')
        # .git/HEAD names the checked-out branch even with zero commits, which is exactly
        # the state init leaves behind — `git rev-parse HEAD` would fail there.
        $headRef = if (Test-Path (Join-Path $copy '.git/HEAD')) {
            [System.IO.File]::ReadAllText((Join-Path $copy '.git/HEAD')) } else { '' }
    }

    It 'completes successfully and reports the fresh history' {
        $result.ExitCode | Should -Be 0
        $result.Output   | Should -Match 'Scaffold complete'
        $result.Output   | Should -Match 'Fresh git history'
    }

    It 'leaves a .git repo checked out on branch main' {
        Join-Path $copy '.git' | Should -Exist
        $headRef.Trim()        | Should -Be 'ref: refs/heads/main'
    }

    It 'still scaffolds normally alongside the git init' {
        $justfile = [System.IO.File]::ReadAllText((Join-Path $copy 'justfile'))
        $justfile | Should -Not -Match '@[@]'
        $justfile | Should -Match "env_var_or_default\('PORT', '8566'\)"
        Join-Path $copy 'CLAUDE.md' | Should -Exist
        Join-Path $copy 'stacks'    | Should -Not -Exist
    }
}

Describe 'init.ps1 — missing required value, non-interactively' {

    BeforeAll {
        # Both runs use Invoke-InitNoInput: the prompt gets an empty answer at once and
        # init bails. Two stacks because the MainClass guard and the Src guard are
        # separate branches in init.ps1.
        $noMainClassCopy = New-SkeletonCopy
        $noMainClass     = Invoke-InitNoInput -Root $noMainClassCopy -Arguments @(
            '-Name', 'test-nomain', '-Stack', 'cli-java')

        $noSrcCopy = New-SkeletonCopy
        $noSrc     = Invoke-InitNoInput -Root $noSrcCopy -Arguments @(
            '-Name', 'test-nosrc', '-Stack', 'cli-cpp')
    }

    It 'cli-java without -MainClass exits 1 and says the stack needs that value' {
        $noMainClass.ExitCode | Should -Be 1
        $noMainClass.Output   | Should -Match 'This stack needs that value'
    }

    It 'cli-cpp without -Src exits 1 and says the stack needs that value' {
        $noSrc.ExitCode | Should -Be 1
        $noSrc.Output   | Should -Match 'This stack needs that value'
    }

    It 'bails BEFORE touching anything — no half-scaffolded project is left behind' {
        # The guard fires before step 1, so the skeleton must be completely intact.
        Join-Path $noMainClassCopy 'setup.ps1'    | Should -Not -Exist
        Join-Path $noMainClassCopy 'CLAUDE.md'    | Should -Not -Exist
        Join-Path $noMainClassCopy 'stacks'       | Should -Exist
        Join-Path $noMainClassCopy 'init.ps1'     | Should -Exist
        Join-Path $noMainClassCopy 'GROUNDING.md' | Should -Exist
    }
}

Describe 'init.ps1 — missing stacks folder' {

    BeforeAll {
        $copy = New-SkeletonCopy
        Remove-Item -Recurse -Force (Join-Path $copy 'stacks')
        # Fully specified arguments: the failure must come from the missing folder, not
        # from a prompt. This never reaches a Read-Host, so plain Invoke-Init is safe.
        $result = Invoke-Init -Root $copy -Arguments @(
            '-Name', 'test-nostacks', '-Stack', 'static', '-Port', '8577', '-Docroot', '.')
    }

    It 'exits 1 and names the missing stacks folder' {
        $result.ExitCode | Should -Be 1
        $result.Output   | Should -Match 'stacks\\ folder not found'
    }

    It 'leaves the clone unscaffolded' {
        Join-Path $copy 'setup.ps1'           | Should -Not -Exist
        Join-Path $copy 'CLAUDE.md'           | Should -Not -Exist
        Join-Path $copy 'init.ps1'            | Should -Exist
        Join-Path $copy 'GROUNDING.md'        | Should -Exist
        Join-Path $copy 'CLAUDE.md.template'  | Should -Exist
    }
}
