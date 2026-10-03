# Multi-model roundtable from one CLI/UI

## Status: RESEARCHED (2026-10-01)

### Recommendation

Try **Botference plan mode** first. It is the closest match to the requested
interaction: one terminal TUI containing the user, Claude Code, and Codex in a
shared council where the models can hand each other the floor, debate, and
produce a plan. Its documented defaults are exactly `claude-fable-5-1` and
`gpt-6-astra`, and it reuses authenticated Claude Code and Codex CLIs when API
keys are absent. This machine already has both CLIs installed.

Treat it as an early-stage tool, not infrastructure: the author calls it
"vibe-coded," says only `botference plan` is ready for use, has published no
releases, and the repository currently has 19 stars and one fork. It is active,
however: the repository was pushed on 2026-10-01. Clone it separately, install
the Ink UI dependency, and evaluate plan mode before integrating it here.

For the maintained, vendor-supported fallback, use **GitHub Copilot CLI Fleet**.
The installed Copilot CLI 1.0.91 exposes `/fleet` (parallel subagents),
`/subagents` (default and per-agent model/effort/context), and both
`claude-fable-5.1` and `gpt-6-astra`. GitHub's Fleet documentation explicitly
says a prompt may assign different named models to different subtasks. This is
good for independent opinions plus a synthesis, but it is orchestrated fan-out,
not Botference's visible free-form group chat.

### What “Fable” is

`Fable` here is **Anthropic Claude Fable**, not an OpenAI model. Anthropic lists
Claude Fable 5.1 as an active model with model ID `claude-fable-5-1`, released
2026-09-01. GitHub Copilot also documents Fable 5 and 5.1, subject to plan and
administrator enablement; its documentation includes a special data-retention
notice for these models.

OpenAI's current Codex model catalog contains `gpt-6-astra` but no Fable chat
model. OpenAI does have a lowercase `fable` TTS voice, which is unrelated.
The local Copilot proxy's `/v1/models` catalog currently contains Astra but not
Fable, whereas the official Copilot CLI lists both. Therefore use the official
Copilot CLI or the separate authenticated Claude Code CLI for Fable; do not
assume this repo's `codex-copilot` proxy route can serve it.

### Options compared

| Option | Same terminal/UI | Different models/providers | Actual discussion | Fit here |
|---|---:|---:|---:|---|
| Botference `plan` | Yes | Claude Code + Codex | Yes: shared council, turn handoff, debate | Best UX match; active but immature |
| GitHub Copilot CLI `/fleet` | Yes | Yes; Fable and Astra are listed | Partial: parallel subagents and synthesis | Best supported option |
| Codex subagents | Yes | Different available/configured models | Orchestrated fan-out and synthesis | Good for Astra plus OpenAI models; Fable is not native |
| OpenCode agents | Yes | Yes; 75+ providers, per-agent model override | Prompted subagent collaboration | Best general cross-provider fallback |
| LLM Council | Web UI | OpenRouter models | Three-stage answer/review/chair workflow | Exact pattern, but author explicitly will not support it |
| PAL MCP Server | Existing CLI via MCP | Many API providers/CLIs | `consensus` and chained discussions | Feature-rich, but last code push was 2025-12-15 |
| Promptfoo | CLI | Many providers/models | No; evaluation/comparison | Use for repeatable benchmarks, not conversation |

### Practical starting points

Botference proof of fit:

```sh
git clone https://github.com/angadhn/botference
cd botference/ink-ui
npm install
cd ..
./botference plan
```

Its plan mode keeps the project tree read-only and writes Botference-owned plan
state. For use in another project, its documented flow is `botference init`
followed by `botference plan`. Do not use its experimental build or
research-plan modes for the initial evaluation.

Copilot Fleet fallback:

1. Start `copilot` and use `/subagents` to assign Fable and Astra to separate
   agents, or name the models directly in the Fleet prompt.
2. Use a prompt such as:

   > /fleet Have Claude Fable 5.1 and GPT-6 Astra answer independently. Then
   > have each critique the other's answer and give me a synthesis that preserves
   > disagreements.

3. Use `/tasks` to inspect the subagent work. Fleet consumes more GitHub AI
   Credits because each subagent makes its own model calls.

### Why native Codex alone is not the first choice

Current Codex releases enable subagents by default, allow a custom agent to
select a model, expose `/agent` to inspect threads, and collect subagent results
in the main response. Astra is officially supported in Codex CLI. This makes
Codex a good one-window council for Astra, Sol, Luna, and other models available
to the signed-in account.

It does not natively list Claude Fable. Codex can use a custom model provider,
but the provider must implement a compatible Responses API including streaming
completion events, conversation continuation, and tool-call/result loops;
Chat Completions compatibility alone is insufficient. OpenAI's documentation
does not clearly promise that different subagents can each switch to a
different provider, so a Fable-plus-Astra Codex-only configuration should not
be assumed to work without testing a specific gateway.

### Cross-provider fallback

OpenCode remains the most credible general alternative when the desired models
span unrelated providers. Its current documentation says it supports 75+ LLM
providers (including GitHub Copilot), primary agents can invoke subagents in
parallel, and each agent may override its model using a `provider/model-id`.
It can therefore model a council with separate Fable and Astra subagents, but
requires agent configuration and a synthesis prompt. Since official Copilot
Fleet already exposes both models on this machine, OpenCode adds setup without
improving this exact use case.

### Primary sources

- [Botference README](https://github.com/angadhn/botference): council behavior,
  CLI reuse, defaults, install steps, plan-mode maturity warning.
- [Botference repository metadata](https://api.github.com/repos/angadhn/botference):
  activity, release/maturity signals, stars and forks as observed 2026-10-01.
- [Claude Fable 5.1 overview](https://platform.claude.com/docs/en/models/fable-5-1/overview):
  vendor, model ID, release/lifecycle, intended uses.
- [Supported AI models in GitHub Copilot](https://docs.github.com/en/copilot/reference/ai-models/supported-models):
  Copilot availability and Fable-specific data-retention/admin caveats.
- [Running tasks in parallel with `/fleet`](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/fleet):
  orchestration, explicit per-subtask models, custom agents, credit implications.
- [Speeding up task completion with `/fleet`](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/speed-up-task-completion):
  `/fleet`, `--fleet`, and `/tasks` usage.
- [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents):
  model selection, custom agents, `/agent`, result collection.
- [Codex models](https://learn.chatgpt.com/docs/models): Astra availability and
  current Codex model catalog.
- [Codex gateway compatibility](https://learn.chatgpt.com/docs/enterprise/gateway-compatibility):
  Responses API requirements for custom gateways.
- [OpenCode agents](https://opencode.ai/docs/agents/) and
  [providers](https://opencode.ai/docs/providers/): per-agent models,
  subagents/parallel work, provider breadth, GitHub Copilot support.
- [LLM Council README](https://github.com/karpathy/llm-council): formal
  answer/review/chair workflow and explicit no-support warning.
- [PAL MCP Server README](https://github.com/BeehiveInnovations/pal-mcp-server):
  consensus/cross-model features; repository metadata showed its last push on
  2025-12-15.

