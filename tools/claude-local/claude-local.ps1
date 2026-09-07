# claude-local: run Claude Code against a self-hosted model server (vLLM, Ollama) that serves the
# Anthropic Messages API, instead of Anthropic's own endpoint. Same `claude` binary, same skills and
# settings -- only the endpoint changes, and only for this process.
#
# Usage:  claude-local [--endpoint <name> | -e <name>] [--no-mcp] [--list] [any claude arguments]
#         claude-local                    default endpoint; falls back to the next reachable one
#         claude-local -e ollama          a specific endpoint, no fallback
#         claude-local --list             show every endpoint, its reachability, model and context
#         claude-local --no-mcp           drop every MCP server for this session (saves tens of
#                                         thousands of context tokens on tool schemas)
#         claude-local -p "..."           print mode, any claude argument passes through
#
# Config: config.json next to this script, written by install.ps1:
#           { "default": "main",
#             "endpoints": { "main":   { "upstream": "http://host:8000",  "model": "", "label": "", "context": 0 },
#                            "ollama": { "upstream": "http://127.0.0.1:11434", "model": "qwen3.5:4b", "context": 32768 } } }
#         model "" = first entry of <upstream>/v1/models; context 0 = ask the server (max_model_len),
#         else assume 65536 -- set it for Ollama, which never reports it.
#         Environment overrides (per shell): LOCAL_LLM_ENDPOINT (name), LOCAL_LLM_UPSTREAM (+ LOCAL_LLM_MODEL,
#         LOCAL_LLM_CONTEXT) for an ad-hoc endpoint that is not in config.json.
#
# What it does: (1) picks the endpoint and checks it is reachable, (2) starts the local shim on
# 127.0.0.1:8098 if it is not already running (shim.py explains why one is needed), (3) sets the
# Claude Code gateway variables for this process only, tagging every request with the chosen
# upstream so the single shim routes it, (4) runs `claude`.
#
# Must stay Windows PowerShell 5.1 compatible: the .cmd stub falls back to it when pwsh is absent.
$ErrorActionPreference = 'Stop'
$Root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$ShimPort = 8098
$ShimUrl  = "http://127.0.0.1:$ShimPort"
$LogDir   = Join-Path $Root 'logs'

# ---------- arguments ----------
$claudeArgs   = @()
$EndpointName = $env:LOCAL_LLM_ENDPOINT
$ListOnly     = $false
$NoMcp        = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = [string]$args[$i]
    if (($a -eq '--endpoint' -or $a -eq '-e') -and ($i + 1) -lt $args.Count) { $EndpointName = [string]$args[$i + 1]; $i++; continue }
    if ($a -like '--endpoint=*') { $EndpointName = $a.Substring(11); continue }
    if ($a -eq '--list')   { $ListOnly = $true; continue }
    if ($a -eq '--no-mcp') { $NoMcp = $true; continue }
    $claudeArgs += $a
}

# ---------- endpoints (ordered list of name + settings) ----------
function Get-Prop($Obj, [string]$Name) {
    if ($null -eq $Obj) { return $null }
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}
$cfg = $null
$cfgPath = Join-Path $Root 'config.json'
if (Test-Path $cfgPath) {
    try { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json } catch { $cfg = $null }
}
$endpoints = @()   # list of @{ Name; Upstream; Model; Label; Context }
$eps = Get-Prop $cfg 'endpoints'
if ($eps) {
    foreach ($p in $eps.PSObject.Properties) {
        $u = Get-Prop $p.Value 'upstream'
        if (-not $u) { continue }
        $endpoints += @{ Name = $p.Name; Upstream = ([string]$u).TrimEnd('/'); Model = [string](Get-Prop $p.Value 'model');
                         Label = [string](Get-Prop $p.Value 'label'); Context = [int](Get-Prop $p.Value 'context') }
    }
} elseif (Get-Prop $cfg 'upstream') {   # pre-endpoints config.json
    $endpoints += @{ Name = 'main'; Upstream = ([string]$cfg.upstream).TrimEnd('/'); Model = [string](Get-Prop $cfg 'model');
                     Label = [string](Get-Prop $cfg 'label'); Context = 0 }
}
if ($env:LOCAL_LLM_UPSTREAM) {          # ad-hoc endpoint from the shell wins
    $adhoc = @{ Name = 'env'; Upstream = $env:LOCAL_LLM_UPSTREAM.TrimEnd('/'); Model = [string]$env:LOCAL_LLM_MODEL;
                Label = ''; Context = [int]("0" + $env:LOCAL_LLM_CONTEXT) }
    $endpoints = @($adhoc) + $endpoints
    if (-not $EndpointName) { $EndpointName = 'env' }
}
if ($endpoints.Count -eq 0) {
    Write-Host "claude-local: no endpoint configured. Run install.ps1 -Upstream http://host:port (or set LOCAL_LLM_UPSTREAM)." -ForegroundColor Red
    exit 1
}
$DefaultName = [string](Get-Prop $cfg 'default')
if (-not $DefaultName -or -not ($endpoints | Where-Object { $_.Name -eq $DefaultName })) { $DefaultName = $endpoints[0].Name }

function Get-Models([string]$Base, [int]$TimeoutSec) {
    try { return (Invoke-RestMethod -Uri "$Base/v1/models" -TimeoutSec $TimeoutSec -ErrorAction Stop) } catch { return $null }
}
function Get-ShimInfo {
    try { return (Invoke-RestMethod -Uri "$ShimUrl/shim/info" -TimeoutSec 2 -ErrorAction Stop) } catch { return $null }
}

# ---------- --list ----------
if ($ListOnly) {
    Write-Host "claude-local endpoints ($cfgPath)"
    foreach ($ep in $endpoints) {
        $mark = ' '
        if ($ep.Name -eq $DefaultName) { $mark = '*' }
        $m = Get-Models $ep.Upstream 4
        if ($m) {
            $id = $ep.Model
            if (-not $id) { $id = $m.data[0].id }
            $ctx = $ep.Context
            if (-not $ctx) { $ctx = [int](Get-Prop $m.data[0] 'max_model_len') }
            $ctxText = "ctx $ctx"
            if (-not $ctx) { $ctxText = 'ctx unknown (assumed 65536)' }
            Write-Host ("  {0} {1,-10} {2,-30} up    {3}  {4}" -f $mark, $ep.Name, $ep.Upstream, $id, $ctxText) -ForegroundColor Green
        } else {
            Write-Host ("  {0} {1,-10} {2,-30} down" -f $mark, $ep.Name, $ep.Upstream) -ForegroundColor DarkGray
        }
    }
    $info = Get-ShimInfo
    if ($info) { Write-Host "shim: $ShimUrl up (pid $($info.pid))" } else { Write-Host "shim: $ShimUrl not running (starts with the next session)" }
    exit 0
}

# ---------- 1. pick a reachable endpoint ----------
$chosen = $null
$models = $null
if ($EndpointName) {
    $chosen = $endpoints | Where-Object { $_.Name -eq $EndpointName } | Select-Object -First 1
    if (-not $chosen) {
        Write-Host "claude-local: no endpoint named '$EndpointName' (have: $(($endpoints | ForEach-Object { $_.Name }) -join ', '))" -ForegroundColor Red
        exit 1
    }
    $models = Get-Models $chosen.Upstream 5
    if (-not $models) {
        Write-Host "claude-local: endpoint '$($chosen.Name)' at $($chosen.Upstream) is unreachable (no answer on /v1/models). Server down, or VPN?" -ForegroundColor Red
        exit 1
    }
} else {
    $order = @($endpoints | Where-Object { $_.Name -eq $DefaultName }) + @($endpoints | Where-Object { $_.Name -ne $DefaultName })
    foreach ($ep in $order) {
        $models = Get-Models $ep.Upstream 4
        if ($models) {
            $chosen = $ep
            if ($ep.Name -ne $DefaultName) { Write-Host "claude-local: default endpoint '$DefaultName' is unreachable, falling back to '$($ep.Name)' ($($ep.Upstream))" -ForegroundColor Yellow }
            break
        }
    }
    if (-not $chosen) {
        Write-Host "claude-local: no endpoint reachable. Tried: $(($order | ForEach-Object { "$($_.Name)=$($_.Upstream)" }) -join ', '). Server down, or VPN?" -ForegroundColor Red
        exit 1
    }
}
$Upstream = $chosen.Upstream
$Model = [string]$env:LOCAL_LLM_MODEL
if (-not $Model) { $Model = $chosen.Model }
if (-not $Model) { $Model = $models.data[0].id }
$ContextLen = [int]$chosen.Context
$ContextKnown = $true
if (-not $ContextLen) {
    $entry = $models.data | Where-Object { $_.id -eq $Model } | Select-Object -First 1
    if (-not $entry) { $entry = $models.data[0] }
    $ContextLen = [int](Get-Prop $entry 'max_model_len')
}
if (-not $ContextLen) { $ContextLen = 65536; $ContextKnown = $false }
# Claude Code keeps max-output tokens out of the usable window, so a small server (64k)
# gets an eighth (8k) rather than a quarter: a 40k baseline prompt otherwise leaves no room.
$MaxOutput = [Math]::Min(16384, [int]($ContextLen / 8))
$Label = $chosen.Label
if (-not $Label) {
    $leaf = (($Model -split '[/\\]') | Where-Object { $_ } | Select-Object -Last 1)
    $Label = "$leaf ($($chosen.Name))"
}

# ---------- 2. shim up? start it detached if not ----------
# The shim is stdlib Python. Prefer pythonw (no console window); fall back to python, then
# to the interpreter uv manages (initial-setup.ps1 installs Python that way, off PATH).
function Resolve-Python {
    $c = Get-Command pythonw -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $c = Get-Command python -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        $p = (& uv python find 2>$null | Select-Object -First 1)
        if ($p -and (Test-Path $p)) {
            $w = Join-Path (Split-Path -Parent $p) 'pythonw.exe'
            if (Test-Path $w) { return $w }
            return $p
        }
    }
    return $null
}
if (-not (Get-ShimInfo)) {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $env:UPSTREAM    = $Upstream
    $env:PORT        = "$ShimPort"
    $env:LOGDIR      = $LogDir
    $env:CONTEXT_LEN = "$ContextLen"
    $py = Resolve-Python
    if (-not $py) {
        Write-Host "claude-local: Python 3 not found (pythonw/python on PATH, or uv). The shim needs it: 'uv python install' or install Python." -ForegroundColor Red
        exit 1
    }
    Start-Process -FilePath $py -ArgumentList ('"' + (Join-Path $Root 'shim.py') + '"') -WindowStyle Hidden -WorkingDirectory $Root
    $up = $false
    for ($i = 0; $i -lt 20 -and -not $up; $i++) {
        Start-Sleep -Milliseconds 500
        $up = [bool](Get-ShimInfo)
    }
    if (-not $up) {
        Write-Host "claude-local: shim did not come up on $ShimUrl - see $LogDir\shim.err" -ForegroundColor Red
        exit 1
    }
}

# ---------- 3. gateway variables ----------
# Set in this process (child processes and tools see them) AND handed to Claude Code as
# command-line settings (--settings), which outrank a project's .claude/settings.json "env"
# block. A project that pins CLAUDE_CODE_MAX_OUTPUT_TOKENS for Anthropic's 200k window would
# otherwise override the caps that fit this server. ANTHROPIC_CUSTOM_HEADERS tags every request
# with the chosen upstream so the single shim routes it (and its context length, when known).
$routeHeaders = "x-claude-local-upstream: $Upstream"
if ($ContextKnown) { $routeHeaders += "`nx-claude-local-context: $ContextLen" }
$gatewayEnv = [ordered]@{
    ANTHROPIC_BASE_URL                        = $ShimUrl
    ANTHROPIC_AUTH_TOKEN                      = 'local-vllm'    # servers ignore it; Claude Code needs *some* credential set
    ANTHROPIC_CUSTOM_HEADERS                  = $routeHeaders
    ANTHROPIC_MODEL                           = $Model
    ANTHROPIC_DEFAULT_OPUS_MODEL              = $Model          # /model opus|sonnet|haiku|fable all resolve locally
    ANTHROPIC_DEFAULT_SONNET_MODEL            = $Model
    ANTHROPIC_DEFAULT_HAIKU_MODEL             = $Model
    ANTHROPIC_DEFAULT_FABLE_MODEL             = $Model
    ANTHROPIC_CUSTOM_MODEL_OPTION             = $Model          # its own row in the /model picker
    ANTHROPIC_CUSTOM_MODEL_OPTION_NAME        = $Label
    ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION = "Self-hosted at $Upstream via claude-local shim, $ContextLen context"
    CLAUDE_CODE_MAX_CONTEXT_TOKENS            = "$ContextLen"   # unrecognised model id -> tell Claude Code the real window
    CLAUDE_CODE_MAX_OUTPUT_TOKENS             = "$MaxOutput"
    CLAUDE_CODE_ATTRIBUTION_HEADER            = '0'             # the server would feed the attribution block to the model
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC  = '1'
}
foreach ($k in $gatewayEnv.Keys) { Set-Item -Path "Env:$k" -Value $gatewayEnv[$k] }
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
$sessionSettings = Join-Path $Root "session-settings-$($chosen.Name).json"
[System.IO.File]::WriteAllText($sessionSettings, (@{ env = $gatewayEnv } | ConvertTo-Json))

Write-Host "claude-local: [$($chosen.Name)] $Model @ $Upstream (context $ContextLen, max output $MaxOutput) via $ShimUrl" -ForegroundColor DarkGray
if (-not $ContextKnown) {
    Write-Host "claude-local: this server does not report its context length; assuming 65536. Set `"context`" for endpoint '$($chosen.Name)' in config.json (install.ps1 -Name $($chosen.Name) -Context N) to match the server." -ForegroundColor Yellow
}

# ---------- 4. --no-mcp and --settings ----------
# --no-mcp drops every MCP server for this session. Their tool schemas are the largest context
# consumer (a project with 11 servers sent 230 tools, ~113k tokens, into a 64k window).
# Implemented with Claude Code's own flags: an empty --mcp-config plus --strict-mcp-config.
if ($NoMcp) {
    $noMcp = Join-Path $Root 'no-mcp.json'
    if (-not (Test-Path $noMcp)) { [System.IO.File]::WriteAllText($noMcp, '{ "mcpServers": {} }') }
    $claudeArgs += @('--strict-mcp-config', '--mcp-config', $noMcp)
    Write-Host "claude-local: MCP servers disabled for this session (--no-mcp)" -ForegroundColor DarkGray
} elseif ($ContextLen -lt 100000) {
    Write-Host "claude-local: small context - if you see 'Prompt is too long', relaunch with --no-mcp" -ForegroundColor DarkGray
}
if ($claudeArgs -contains '--settings') {
    Write-Host "claude-local: you passed --settings, so the launcher's session settings are not added; keep the context/output caps in yours" -ForegroundColor Yellow
} else {
    $claudeArgs += @('--settings', $sessionSettings)
}

# ---------- 5. run Claude Code ----------
& claude @claudeArgs
exit $LASTEXITCODE
