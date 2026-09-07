# claude-local: Claude Code on a self-hosted vLLM model

Run the **same** Claude Code binary against a self-hosted model served by vLLM instead of
Anthropic's API. Nothing global changes: `claude` keeps using Anthropic, `claude-local`
uses your server, and every variable is set only for the `claude-local` process.

```powershell
claude-local                 # interactive session on the local model
claude-local -p "..."        # print mode
claude-local --resume        # any claude argument passes through
claude-local --no-mcp        # drop every MCP server for this session (see Known limits)
just claudel                 # same, with --dangerously-skip-permissions (project justfiles)
```

## Table of contents

1. [Install](#install)
2. [Files](#files)
3. [How it works](#how-it-works)
4. [Why a shim is needed](#why-a-shim-is-needed)
5. [Known limits](#known-limits)
6. [Operations](#operations)

## Install

Requirements: Claude Code, Python 3 (on PATH, or managed by `uv`), PowerShell 7, and a
vLLM server (0.19+) whose `/v1/messages` endpoint you can reach.

```powershell
# from a clone of project-skeleton
pwsh tools/claude-local/install.ps1 -Upstream http://vllm-host:8000

# from the web (Windows PowerShell 5.1 is fine)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/dxiiren/project-skeleton/main/tools/claude-local/install.ps1))) -Upstream http://vllm-host:8000

# as part of the machine bootstrap
initial-setup.ps1 -LocalLlmUpstream http://vllm-host:8000
```

Then open a **new** terminal and run `claude-local`. The installer is idempotent.
`-Model <id>` pins a model; otherwise the first entry of `/v1/models` is used at launch.

## Files

| Path | Role |
| --- | --- |
| `~\.claude\local-llm\claude-local.ps1` | the launcher (checks the server, starts the shim, sets env, runs `claude`) |
| `~\.claude\local-llm\shim.py` | local proxy on `127.0.0.1:8098` -> vLLM (stdlib Python, no dependencies) |
| `~\.claude\local-llm\config.json` | `{ "upstream", "model", "label" }` written by the installer |
| `~\.claude\local-llm\logs\shim.log` | one line per request: tools, folded system turns, prompt tokens, status, bytes, seconds |
| `~\.local\bin\claude-local.cmd` | entry point for cmd / anything that resolves PATH |
| `~\.local\bin\claude-local` | entry point for Git Bash (avoids cmd.exe's "Terminate batch job?" prompt on Ctrl+C) |
| pwsh `$PROFILE` | a `claude-local` function, so pwsh runs the launcher directly |

## How it works

```mermaid
flowchart LR
    U[claude-local] -->|env: ANTHROPIC_BASE_URL=127.0.0.1:8098| C[claude CLI]
    C -->|/v1/messages Anthropic format| S[shim.py]
    S -->|fold role:system -> user\nclamp max_tokens| V[vLLM /v1/messages]
```

The launcher sets, for its own process only:

- `ANTHROPIC_BASE_URL` -> the shim; a dummy `ANTHROPIC_AUTH_TOKEN` (vLLM has no auth, Claude Code needs a credential set).
- `ANTHROPIC_MODEL` and the four `ANTHROPIC_DEFAULT_*_MODEL` tier aliases -> the vLLM model id, so `/model opus` etc. never leak to Anthropic.
- `ANTHROPIC_CUSTOM_MODEL_OPTION` -> a labelled row in the `/model` picker.
- `CLAUDE_CODE_MAX_CONTEXT_TOKENS` -> `max_model_len` read live from `/v1/models`, so auto-compact fires at the right size.
- `CLAUDE_CODE_MAX_OUTPUT_TOKENS` (16384, or an eighth of the context on small servers, since Claude Code keeps that reservation out of the usable window), `CLAUDE_CODE_ATTRIBUTION_HEADER=0`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.

The same values are also written to `session-settings.json` and passed as `--settings`,
because command-line settings outrank a project's `.claude/settings.json` `env` block. A
project that pins `CLAUDE_CODE_MAX_OUTPUT_TOKENS` to 100000 for Anthropic's 200k window would
otherwise override the launcher and hit "Context limit reached" after the first reply.

Model id and context length are discovered from the server at launch, so a model swap on
the server needs no reinstall. Per-shell overrides: `LOCAL_LLM_UPSTREAM`, `LOCAL_LLM_MODEL`.

## Why a shim is needed

vLLM 0.19 implements the Anthropic Messages API natively (`/v1/messages`, streaming, tools,
thinking, `count_tokens`) and all of that works with Claude Code as-is. Two things do not:

1. **`role: "system"` entries inside `messages`** (Claude Code's `mid-conversation-system`
   beta). vLLM only accepts user/assistant there and returns 400, and Claude Code's
   "retry without the capability" logic keys on Anthropic's error wording, which vLLM's
   pydantic error does not match, so the session dies on the first request. The shim folds
   those entries into the adjacent user turn as text blocks.
   `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1` does not stop them (tested).
2. **`max_tokens` + prompt > `max_model_len`** makes vLLM return 500. The shim counts the
   prompt via upstream `count_tokens`, clamps `max_tokens`, and returns an Anthropic-style
   `prompt is too long` 400 when nothing fits, which Claude Code understands as "compact now".

Everything else is forwarded unchanged. Anthropic documents gateway use but states that
routing Claude Code to non-Claude models is unsupported: treat this as self-supported.

## Known limits

- **Context is whatever the server allows, not 200k.** Claude Code's baseline (system
  prompt + 62 built-in tools) is ~27k tokens per request, ~35k with a few MCP servers,
  and a project with 11 MCP servers plus a 43k-char CLAUDE.md sent 230 tools and ~113k
  tokens on its very first turn, which a 64k server can never accept ("Prompt is too
  long" before you type anything). Fixes, best first: raise `--max-model-len` on the
  server (the launcher picks the new value up automatically); launch with
  `claude-local --no-mcp`, which drops every MCP server via `--strict-mcp-config` and an
  empty `--mcp-config`; or pass your own small `--mcp-config` file to keep one or two.
  Trim the project's CLAUDE.md too: Claude Code itself warns above 40k chars.
- **Model id must match exactly**; vLLM 404s on anything else. That is why every tier alias
  is pointed at it.
- claude.ai connectors and OAuth-only features are off in local sessions (a credential
  variable is set, which takes precedence over the login). Plain `claude` is unaffected.
- Auto permission mode's classifier requests also go to the local model. If it misjudges,
  start with `claude-local --permission-mode default`.
- Prompt caching is not reported by vLLM (`cache_read_input_tokens` stays 0); vLLM prefix-caches internally.
- One endpoint per session: `/model` inside `claude-local` cannot reach Anthropic, and
  `/model` inside plain `claude` cannot reach the local server.

## Operations

```powershell
# is the shim up?
Invoke-RestMethod http://127.0.0.1:8098/v1/models

# tail the request log
Get-Content ~\.claude\local-llm\logs\shim.log -Tail 20 -Wait

# stop the shim (it restarts on the next claude-local)
Stop-Process -Id (Get-Content ~\.claude\local-llm\logs\shim.pid)

# debug a bad request: dump full bodies (contain conversation text; delete afterwards)
$env:SHIM_DUMP = '1'; Stop-Process -Id (Get-Content ~\.claude\local-llm\logs\shim.pid); claude-local
```

The shim runs detached under `pythonw` and survives the terminal closing. It listens on
loopback only. Re-running `install.ps1` refreshes the files and stops the old shim.
