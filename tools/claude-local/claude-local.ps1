# claude-local: run Claude Code against a self-hosted vLLM model that serves the Anthropic
# Messages API, instead of Anthropic's own endpoint. Same `claude` binary, same skills and
# settings -- only the endpoint changes, and only for this process.
#
# Usage:  claude-local [any claude arguments]
#         claude-local                interactive session on the local model
#         claude-local -p "..."       print mode
#         claude-local --no-mcp       same, with every MCP server dropped (saves tens of
#                                     thousands of context tokens on tool schemas)
#
# Config: config.json next to this script, written by install.ps1 -Upstream:
#           { "upstream": "http://host:8000", "model": "", "label": "" }
#         Environment overrides (per shell):
#           LOCAL_LLM_UPSTREAM   base URL of the vLLM server (no trailing /v1)
#           LOCAL_LLM_MODEL      exact model id; default: first entry of <upstream>/v1/models
#
# What it does: (1) checks the server is reachable, (2) starts the local shim on
# 127.0.0.1:8098 if it is not already running (shim.py explains why one is needed),
# (3) sets the Claude Code gateway variables for this process only, (4) runs `claude`.
#
# Must stay Windows PowerShell 5.1 compatible: the .cmd stub falls back to it when pwsh is absent.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

$cfg = $null
$cfgPath = Join-Path $Root 'config.json'
if (Test-Path $cfgPath) {
    try { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json } catch { $cfg = $null }
}
$Upstream = $env:LOCAL_LLM_UPSTREAM
if (-not $Upstream -and $cfg -and $cfg.upstream) { $Upstream = $cfg.upstream }
if (-not $Upstream) {
    Write-Host "claude-local: no upstream configured. Re-run install.ps1 -Upstream http://host:port (or set LOCAL_LLM_UPSTREAM)." -ForegroundColor Red
    exit 1
}
$Upstream = $Upstream.TrimEnd('/')
$ShimPort = 8098
$ShimUrl  = "http://127.0.0.1:$ShimPort"
$LogDir   = Join-Path $Root 'logs'

function Get-Models([string]$Base, [int]$TimeoutSec) {
    try { return (Invoke-RestMethod -Uri "$Base/v1/models" -TimeoutSec $TimeoutSec -ErrorAction Stop) } catch { return $null }
}

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

# 1. Upstream reachable?
$models = Get-Models $Upstream 5
if (-not $models) {
    Write-Host "claude-local: cannot reach $Upstream/v1/models. Is the server up and the VPN connected?" -ForegroundColor Red
    exit 1
}
$Model = $env:LOCAL_LLM_MODEL
if (-not $Model -and $cfg -and $cfg.model) { $Model = $cfg.model }
if (-not $Model) { $Model = $models.data[0].id }
$ContextLen = 65536
if ($models.data[0].max_model_len) { $ContextLen = [int]$models.data[0].max_model_len }
$MaxOutput = [Math]::Min(16384, [int]($ContextLen / 4))
$Label = ''
if ($cfg -and $cfg.label) { $Label = $cfg.label }
if (-not $Label) {
    $leaf = (($Model -split '[/\\]') | Where-Object { $_ } | Select-Object -Last 1)
    $Label = "$leaf (local vLLM)"
}

# 2. Shim up? Start it detached if not.
if (-not (Get-Models $ShimUrl 2)) {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $env:UPSTREAM = $Upstream
    $env:PORT     = "$ShimPort"
    $env:LOGDIR   = $LogDir
    $py = Resolve-Python
    if (-not $py) {
        Write-Host "claude-local: Python 3 not found (pythonw/python on PATH, or uv). The shim needs it: 'uv python install' or install Python." -ForegroundColor Red
        exit 1
    }
    Start-Process -FilePath $py -ArgumentList ('"' + (Join-Path $Root 'shim.py') + '"') -WindowStyle Hidden -WorkingDirectory $Root
    $up = $false
    for ($i = 0; $i -lt 20 -and -not $up; $i++) {
        Start-Sleep -Milliseconds 500
        $up = [bool](Get-Models $ShimUrl 2)
    }
    if (-not $up) {
        Write-Host "claude-local: shim did not come up on $ShimUrl - see $LogDir\shim.err" -ForegroundColor Red
        exit 1
    }
}

# 3. Gateway variables (this process and its children only).
$env:ANTHROPIC_BASE_URL                        = $ShimUrl
$env:ANTHROPIC_AUTH_TOKEN                      = 'local-vllm'   # vLLM ignores it; Claude Code needs *some* credential set
$env:ANTHROPIC_MODEL                           = $Model
$env:ANTHROPIC_DEFAULT_OPUS_MODEL              = $Model         # /model opus|sonnet|haiku|fable all resolve locally
$env:ANTHROPIC_DEFAULT_SONNET_MODEL            = $Model
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL             = $Model
$env:ANTHROPIC_DEFAULT_FABLE_MODEL             = $Model
$env:ANTHROPIC_CUSTOM_MODEL_OPTION             = $Model         # its own row in the /model picker
$env:ANTHROPIC_CUSTOM_MODEL_OPTION_NAME        = $Label
$env:ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION = "Self-hosted at $Upstream via claude-local shim, $ContextLen context"
$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS            = "$ContextLen"  # unrecognised model id -> tell Claude Code the real window
$env:CLAUDE_CODE_MAX_OUTPUT_TOKENS             = "$MaxOutput"
$env:CLAUDE_CODE_ATTRIBUTION_HEADER            = '0'            # vLLM would feed the attribution block to the model
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC  = '1'
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue

Write-Host "claude-local: $Model @ $Upstream (context $ContextLen, max output $MaxOutput) via $ShimUrl" -ForegroundColor DarkGray

# 4. --no-mcp: drop every MCP server for this session. Their tool schemas are the largest
#    context consumer (a project with 11 servers sent 230 tools, ~113k tokens, into a 64k
#    window). Implemented with Claude Code's own flags: an empty --mcp-config plus
#    --strict-mcp-config, which ignores user, project and .mcp.json servers.
$claudeArgs = @($args)
if ($claudeArgs -contains '--no-mcp') {
    $claudeArgs = @($claudeArgs | Where-Object { $_ -ne '--no-mcp' })
    $noMcp = Join-Path $Root 'no-mcp.json'
    if (-not (Test-Path $noMcp)) { [System.IO.File]::WriteAllText($noMcp, '{ "mcpServers": {} }') }
    $claudeArgs += @('--strict-mcp-config', '--mcp-config', $noMcp)
    Write-Host "claude-local: MCP servers disabled for this session (--no-mcp)" -ForegroundColor DarkGray
} elseif ($ContextLen -lt 100000) {
    Write-Host "claude-local: small context - if you see 'Prompt is too long', relaunch with --no-mcp" -ForegroundColor DarkGray
}

# 5. Run Claude Code.
& claude @claudeArgs
exit $LASTEXITCODE
