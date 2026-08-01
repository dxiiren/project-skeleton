---
name: llm-transfer
description: "Use when the developer says '/llm-transfer', 'transfer to ChatGPT/Ollama/Gemini', 'hand this to another LLM', 'make a master prompt for an external LLM', or 'export context for an external LLM' - enters plan mode, gathers context, and assembles a self-contained master prompt for a cold, tool-less model; prints a copy-paste block and saves a .md to git-ignored .claude/workspace/reports/transfers/{tool}/."
model: sonnet
---

# llm-transfer - Master Prompt Handoff to an External LLM

Package the current work into **one self-contained master prompt** that a fresh external
model - **ChatGPT, Ollama (local), Gemini, DeepSeek, any LLM** - can act on with **zero prior
context**: no access to this repo, this session, or any tool. This skill IS the framework: run
it and it assembles the handoff for you.

Whatever the target, the reader is a **cold, tool-less model receiving a pasted or piped
prompt** - even Ollama, whose plain `ollama run` terminal session has no repo/file access
unless you wire up tools yourself. So the job is always the same: embed everything the model
needs.

## Trigger

```text
/llm-transfer                          # hand off the current work (asks which tool)
/llm-transfer {topic}                  # hand off a specific problem/task
transfer this to ChatGPT / Ollama / Gemini
hand this over to another LLM
make a master prompt for an external LLM
export context for an external LLM
```

## What to do when invoked

Perform these steps **in order**. Do not skip the plan-mode step - the handoff is drafted and
reviewed before it is final.

1. **Enter plan mode.** Call `EnterPlanMode` immediately. Assembly and review happen inside
   plan mode; you `ExitPlanMode` only when the master prompt is ready.

2. **Determine scope, target tool, AND mode.**
   - Scope: the `{topic}` argument, else infer from the current session/task.
   - Target tool + subdir: `gpt` (ChatGPT), `ollama`, `gemini`, `codex`, ... - sets the
     `transfers/{tool}/` subdir and which Per-target notes apply. If unclear, ask once.
   - **Mode (decides the output):** is the target **agentic** (Codex / opencode / Aider - has
     the repo + runs commands) or **cold** (browser / plain `ollama run` - no tools)? Agentic
     -> emit the _orchestration brief_; cold -> the _self-contained master prompt_. See "Two
     target modes" below.
   - If the ask is ambiguous (continue the work vs. second opinion), fold it into the same one
     question.

3. **Gather context.** Pull **only what's relevant**: the objective and _why_, the current
   state (done / tried / failed / where it stands), the exact code / config / logs / errors /
   data - **read the real files** so artifacts are verbatim - the constraints/stack/
   conventions, and the open questions.

4. **No redaction - verbatim.** The saved file is **git-ignored** and stays on this machine,
   so secrets/tokens are kept **as-is**. External exposure happens only when you send the
   prompt, which you drive:
   - **Local Ollama** - nothing leaves the machine; fully safe.
   - **ChatGPT / Gemini / Ollama Cloud (Turbo)** - the content goes to a third-party service
     when you paste/send it. If a specific _live_ credential worries you, strip that one line
     by hand first. The skill won't.

5. **Assemble** the master prompt using **the framework** below.

6. **Deliver.**
   - Print the full master prompt in chat as a single fenced `text` block.
   - Save it to `.claude/workspace/reports/transfers/{tool}/` as `{YYYY-MM-DD}-{topic}.md`
     (`{tool}` = gpt / ollama / gemini; `{topic}` names the work, **not** this skill). Create
     the folder if missing.
   - Tell the developer how to feed it to the target (see Per-target notes), then
     `ExitPlanMode`.

## THE FRAMEWORK - master prompt template

Fill every section. Omit a section only when it truly doesn't apply, and say so rather than
leaving it blank. Keep the headings - the structure is what makes the handoff legible to a
cold model. Restate the task at the very end: for a long prompt, the key instruction should
appear at BOTH the top and the bottom (see Design basis).

````text
# MASTER PROMPT - {one-line title of the task}

## 1. Role
You are {persona. [GROUND: 2-3 personas that fit this repo's stack, e.g. "a senior <stack>
engineer" / "a <domain> reviewer" / "a technical copy editor"]}. {Any relevant seniority,
domain, or mindset.}

## 2. Mission
{The single objective, in 1-2 sentences. What "success" delivers.}

## 3. Background & Context
{Everything a model with ZERO prior knowledge and NO repo access needs to understand the
situation: what the project is ([GROUND: one-line description of this app + its shape, e.g.
"a <stack> app doing <what>, <build/serve model>"]), the domain, and WHY this task matters.
Self-contained - assume the reader has never seen this codebase.}

## 4. Current State
- What is already done: ...
- What has been tried: ...
- What failed and how: {exact symptom / error}
- Where it stands right now: ...

## 5. Relevant Artifacts
{Inline the actual code / config / logs / errors / data. Each block labeled with its source
path, separated from your instructions by a fence. Verbatim. Only what's relevant - not a repo
dump.}

`[GROUND: a representative source path from this repo]` (excerpt)
```
{exact contents or the relevant excerpt}
```

{error / log output, if any}
```
{exact text}
```

## 6. Constraints & Rules
- Tech stack: {[GROUND: this repo's stack facts - language, framework, build/serve model,
  how it runs locally]}
- Standards / conventions to honor: ... (cold target: inline the repo's CLAUDE.md rules here;
  an agentic target reads CLAUDE.md itself)
- Hard do's and don'ts: ...
- Anything off-limits: ...

## 7. Your Task
{The precise, unambiguous ask. Exactly what to produce, decide, or solve. If it's a second
opinion, state the problem neutrally - do NOT lead toward a conclusion.}

## 8. Output Format & Success Criteria
- Deliver the answer as: {format - a corrected file, a diff, a step list, a decision + rationale}
- Definition of done: {how we'll know the answer is correct/complete}

## 9. Open Questions & Assumptions
- Known gaps: ...
- If blocked, either ask or state your assumption and proceed: ...

## Reminder (restate - instructions repeated at the end for long context)
{One-line restatement of Section 7: the single thing to deliver.}
````

## Assembly rules (the craft)

- **Self-contained.** The model has no access to this repo, this session, or any tool. If it
  isn't in the prompt, it doesn't exist. Embed it.
- **Selective, not a dump.** Include only artifacts that bear on the task; summarize the rest.
  Respect context limits - three relevant excerpts beat thirty (and see the Ollama note: local
  windows can be small).
- **Fidelity over paraphrase.** Paste exact code, exact errors, exact paths.
- **Instructions top and bottom.** For a long prompt, put the key task at both the start and
  the end; if only once, put it above the pasted context, not below.
- **Local & git-ignored.** The saved copy stays on this machine and is never committed, so
  secrets are left verbatim. Only sending to a cloud service leaves the machine - that call is
  yours.
- **Neutral framing for second opinions.** State the problem and the evidence; don't smuggle
  in the conclusion you already reached.
- **Portable.** The handoff may target any project and any model - spell things out.

## Per-target notes

- **ChatGPT / Gemini (cloud):** large context windows - you rarely hit a limit. Content leaves
  the machine when you paste it. Delivery: paste the block (or the saved `.md`) into the web UI.
- **Ollama (local terminal):** a cold model with no repo/file access in a plain `ollama run`
  session (tool-calling exists but only if you wire tools up yourself). Two real differences
  from ChatGPT:
  - **Small default context.** Ollama's default is VRAM-dependent - **4k tokens under 24 GiB
    VRAM** (32k at 24-48 GiB, 256k at 48 GiB+), and Ollama recommends **>= 64,000 tokens for
    coding/agent work**. A big master prompt can exceed the default, so keep it tight AND raise
    the window: `OLLAMA_CONTEXT_LENGTH=64000 ollama serve` (or per-request `num_ctx`).
  - **Delivery = pipe, not paste.** `cat {file}.md | ollama run {model}` (stdin pipe and
    prompt-as-argument are the documented input forms). Nothing leaves the machine.
  - **Cloud caveat.** Ollama Cloud / Turbo offloads to Ollama's servers (opt-in, sign-in
    required) - when used, treat it like ChatGPT.

## Two target modes: agentic vs cold

The output depends on whether the target can read the repo and run commands.

### Agentic target - Codex / opencode / Aider (or Ollama running inside one)

It HAS the repo, reads files, and runs commands. Do **not** dump a payload - emit a lean
**orchestration brief** that drives the agent to use our own conventions and skills. Include:

1. **Conventions:** "Follow the repo's `CLAUDE.md`." (Codex/opencode/Aider read `AGENTS.md` /
   the repo's instructions automatically; the line reinforces which file to honor.)
2. **Situation (continuation state):** use `claude-transfer`'s brief template - mission,
   DONE / IN PROGRESS / NEXT, pointers (`path:line`, recent commits), open questions,
   dead-ends, first action. Pointer-based; the agent re-reads files itself. This is the
   "continue where Claude left off" payload.
3. **Use our skills:** name the relevant playbook(s) and tell it to follow them - _"For this
   task, read and follow `.claude/skills/<skill>/SKILL.md` (and the skills it references); run
   its scripts, e.g. `uv run --no-project python .claude/skills/<skill>/<x>.py`."_ Our skills
   are just markdown playbooks + stdlib Python - an agent can read and run them. **This is how
   the agent "uses our skills."**
4. **MCP caveat:** skills that use the GitHub MCP need it configured in the agent (Codex
   supports MCP). Until then, do those steps by hand.
5. **First action:** the single next step.

Save to `transfers/{tool}/{YYYY-MM-DD}-{topic}.md`; hand the file over (paste it, or tell the
agent "read `<path>` and proceed").

### Cold target - browser ChatGPT / plain `ollama run`

No repo, no tools. It **cannot** read `CLAUDE.md` or our skills. Use the full self-contained
master-prompt framework above; if it must follow project rules or a skill's method, **inline**
the relevant `CLAUDE.md` rules / SKILL.md steps into the prompt (Section 6).

## Delivery format

Chat:

````text
```text
# MASTER PROMPT - ...
...full assembled prompt...
```
````

Then:

```text
Saved: .claude/workspace/reports/transfers/{tool}/{YYYY-MM-DD}-{topic}.md
Feed it:  (gpt/gemini) paste into the web UI   |   (ollama) cat <file> | ollama run <model>
```

## Worked example (compact)

[GROUND: replace this marker with one compact worked example for THIS repo - a realistic
small handoff (a bug or a focused change in this codebase) showing all 9 sections filled,
with a real excerpt from this repo in Section 5 and this repo's stack facts in Section 6.
Keep it under ~50 lines; end with the one-line Reminder.]

That's the shape of every handoff - scale each section up or down to fit the task.

## Design basis (researched 2026-07-01)

- **Instructions top and bottom** of a long prompt - [OpenAI GPT-4.1 prompting guide](https://developers.openai.com/cookbook/examples/gpt4-1_prompting_guide). (The template's closing Reminder exists for this.)
- **Ollama specifics - verified directly from official docs:** default context is small and
  VRAM-dependent (4k / 32k / 256k), 64k recommended for coding
  ([context length](https://docs.ollama.com/context-length)); a plain `ollama run` has no
  tool/repo access unless the caller wires tools
  ([tool calling](https://docs.ollama.com/capabilities/tool-calling)); local by default,
  Cloud/Turbo is opt-in and sends data off-machine ([cloud](https://docs.ollama.com/cloud));
  stdin-pipe / argument input ([cli](https://docs.ollama.com/cli)).
- **Unverified / honest gaps:** the 9-section scaffold and ordering are standard practice but
  could not be independently confirmed - treat as judgment, not fact. The verbatim-local stance
  is a deliberate call; [OWASP LLM02](https://genai.owasp.org/llmrisk/llm022025-sensitive-information-disclosure/)
  flags the sensitive-info-disclosure risk class.

## Evolution Log

- Shipped with the project-skeleton kit: same 9-section framework and dual-mode design proven
  across the stamped dxiiren repos. `/ground-project` resolves the `[GROUND: ...]` personas,
  stack lines, and the worked example against this repo.
