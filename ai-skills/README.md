# Shared AI Skill Library

Portable, cross-agent skill library for **Claude Code**, **OpenAI Codex CLI**,
and **Google Gemini CLI**. Community skill repos are added as git submodules
and deployed to all three agents via symlinks.

## How It Works

All three agents converge on the same **SKILL.md** format — a directory
containing a `SKILL.md` file with YAML frontmatter and Markdown instructions.
Gemini's documentation explicitly describes this as "an open format originally
proposed by Anthropic" designed for cross-agent interoperability.

Skills are sourced from community repos as **git submodules** under `.repos/`:

```
ai-skills/
  README.md
  .repos/                            # git submodules (skill sources)
    superpowers/                     # obra/superpowers (14 skills)
    openai-skills/                   # openai/skills (30 skills)
    tob-skills/                      # trailofbits/skills (27 skills)
    scientific-skills/               # K-Dense-AI/claude-scientific-skills (141 skills)
    ai-research-skills/              # Orchestra-Research/AI-Research-SKILLs (83 skills)
```

The installer (`scripts/install.sh`) symlinks each skill directory into every
agent's discovery path:

```
~/.claude/skills/<name>/  →  <repo>/ai-skills/.repos/<source>/.../<name>/
~/.codex/skills/<name>/   →  <repo>/ai-skills/.repos/<source>/.../<name>/
~/.gemini/skills/<name>/  →  <repo>/ai-skills/.repos/<source>/.../<name>/
```

## Included Skill Repos

| Repo | Skills | Focus |
|------|--------|-------|
| [obra/superpowers](https://github.com/obra/superpowers) | 14 | TDD, debugging, planning, code review, git worktrees, parallel agents |
| [openai/skills](https://github.com/openai/skills) | 30 | GitHub workflows, security, deployment, docs, Playwright |
| [trailofbits/skills](https://github.com/trailofbits/skills) | 27 | Security analysis, Semgrep, property-based testing, modern Python |
| [K-Dense-AI/claude-scientific-skills](https://github.com/K-Dense-AI/claude-scientific-skills) | 141 | Scientific writing, literature review, peer review, citation management, venue templates, bioinformatics |
| [Orchestra-Research/AI-Research-SKILLs](https://github.com/Orchestra-Research/AI-research-SKILLs) | 83 | ML paper writing, model architecture, fine-tuning, evaluation, MLOps, distributed training |

## Managing Skills

### Initial setup (after cloning this repo)

```bash
git submodule update --init --depth 1
./scripts/install.sh
```

### Update all skills to latest

```bash
git submodule update --remote --depth 1
./scripts/install.sh
```

### Add a new skill repo

```bash
git submodule add --depth 1 https://github.com/<owner>/<repo>.git ai-skills/.repos/<name>
```

Then add a deployment loop for its directory structure in `scripts/install.sh`.

### Remove a skill repo

```bash
git submodule deinit ai-skills/.repos/<name>
git rm ai-skills/.repos/<name>
rm -rf .git/modules/ai-skills/.repos/<name>
```

### Disable individual skills

Remove the symlink from the agent's skills directory:

```bash
rm ~/.claude/skills/<skill-name>
rm ~/.codex/skills/<skill-name>
rm ~/.gemini/skills/<skill-name>
```

The symlink will be recreated on next `install.sh` run. To permanently skip
a skill, add a filter in the `install_skills_from` function in `install.sh`.

## SKILL.md Format

Minimal example:

```yaml
---
name: my-skill
description: Short explanation of when this skill should activate.
---

Instructions for the agent to follow when this skill is invoked.
```

### Required Fields

| Field         | Purpose                                                    |
|---------------|------------------------------------------------------------|
| `name`        | Unique identifier (lowercase, hyphens, max 64 chars).      |
| `description` | Tells the model **when** to activate. Critical for auto-invocation. |

### Optional Fields (Cross-Agent)

These fields are understood by all three agents (or safely ignored):

| Field              | Purpose                                            |
|--------------------|----------------------------------------------------|
| `argument-hint`    | Autocomplete hint, e.g. `[issue-number]`.          |

### Agent-Specific Fields

Fields specific to one agent are silently ignored by the others:

| Field                          | Agent   | Purpose                                       |
|--------------------------------|---------|-----------------------------------------------|
| `disable-model-invocation`     | Claude  | `true` = manual-only, agent cannot auto-invoke. |
| `user-invocable`               | Claude  | `false` = hidden from `/` menu, agent-only.    |
| `allowed-tools`                | Claude  | Comma-separated tool allowlist.                |
| `context`                      | Claude  | `fork` to run in isolated subagent.            |
| `agent`                        | Claude  | Subagent type: `Explore`, `Plan`, `general-purpose`. |
| `model`                        | Claude  | Override which model runs this skill.          |
| `allow_implicit_invocation`    | Codex   | `false` in `openai.yaml` to disable auto-invoke. |

## Invoking Skills

| Agent  | Explicit Invocation         | Auto-Invocation                          |
|--------|-----------------------------|------------------------------------------|
| Claude | `/skill-name [args]`        | Model reads descriptions, invokes when relevant. |
| Codex  | `$skill-name` or `/skills`  | Model matches task to description.        |
| Gemini | `/skills enable <name>`     | Model calls `activate_skill` tool.        |

## String Substitution & Dynamic Content

Each agent has slightly different syntax for arguments and shell injection.
Write skills using the most portable subset, or note agent-specific variants
in comments.

### Arguments

| Agent  | Syntax                     | Example                          |
|--------|----------------------------|----------------------------------|
| Claude | `$ARGUMENTS`, `$0`, `$1`   | `Fix issue $ARGUMENTS`           |
| Codex  | `$ARGUMENTS`, `$0`, `$1`   | `Fix issue $ARGUMENTS`           |
| Gemini | `{{args}}`                  | `Fix issue {{args}}`             |

### Shell Command Injection

| Agent  | Syntax         | Example                          |
|--------|----------------|----------------------------------|
| Claude | `` !`cmd` ``   | `` !`git diff --staged` ``       |
| Codex  | `` !`cmd` ``   | `` !`git diff --staged` ``       |
| Gemini | `!{cmd}`       | `!{git diff --staged}`           |

### File Content Injection (Gemini Only)

Gemini supports `@{path}` to embed file or directory content inline.
Claude and Codex do not have an equivalent — use shell injection to `cat`
the file instead.

## Skill Directory Structure

A skill can contain supporting files beyond `SKILL.md`:

```
my-skill/
├── SKILL.md              # Required: main instructions
├── reference.md          # Optional: detailed reference
├── examples.md           # Optional: usage examples
├── templates/
│   └── template.md       # Optional: template the agent fills in
└── scripts/
    └── helper.sh         # Optional: executable script
```

Reference supporting files from `SKILL.md` so the agent knows they exist:

```markdown
## Additional resources
- For complete API details, see [reference.md](reference.md)
- For usage examples, see [examples.md](examples.md)
```

## Discovery Paths (Per Agent)

### Claude Code

| Priority | Location                                |
|----------|-----------------------------------------|
| 1        | Enterprise managed settings             |
| 2        | `~/.claude/skills/<name>/SKILL.md`      |
| 3        | `.claude/skills/<name>/SKILL.md`        |
| 4        | Plugin skills (namespaced)              |

### Codex CLI

| Priority | Location                                |
|----------|-----------------------------------------|
| 1        | `.agents/skills/<name>/SKILL.md`        |
| 2        | Parent `.agents/skills/` (upward walk)  |
| 3        | `$REPO_ROOT/.agents/skills/`            |
| 4        | `~/.codex/skills/<name>/SKILL.md`       |
| 5        | `/etc/codex/skills/`                    |
| 6        | Bundled system skills                   |

### Gemini CLI

| Priority | Location                                |
|----------|-----------------------------------------|
| 1        | `.gemini/skills/<name>/SKILL.md`        |
| 2        | `~/.gemini/skills/<name>/SKILL.md`      |
| 3        | Extension-bundled skills                |

## Writing Cross-Agent Skills

### Best Practices

1. **Description is king.** All three agents use the `description` field to
   decide when to activate a skill. Write it clearly and specifically.
2. **Keep SKILL.md under 500 lines.** Move detailed docs to supporting files.
3. **Use `argument-hint`** so users know what arguments to pass.
4. **Use `disable-model-invocation: true`** (Claude) for side-effect workflows
   like deploy, commit, or send — prevents accidental auto-invocation.
5. **Test across agents.** Agent-specific fields are ignored by others, but
   verify that the core instructions work for all three.
6. **Don't hardcode paths.** Use shell injection or rely on the agent's
   built-in tools for platform detection.

### Portability Notes

- Agent-specific YAML frontmatter fields are **silently ignored** by agents
  that don't recognize them. A single `SKILL.md` works across all three.
- Shell injection syntax differs (`!`cmd`` vs `!{cmd}`). For maximum
  portability, keep dynamic content in supporting scripts and call them
  from instructions rather than using inline injection.
- Gemini uses TOML for custom commands (`.gemini/commands/*.toml`), which is
  a separate system from skills. If you need Gemini-only reusable prompts,
  use that system instead.

## Relationship to Other AI Config

| File / System        | Scope          | Purpose                              |
|----------------------|----------------|--------------------------------------|
| `AI.md`              | Per-project    | Shared project instructions (symlinked to `CLAUDE.md`, `CODEX.md`, `GEMINI.md`). |
| `ai-skills/`         | Global (user)  | Reusable skill library (this directory). |
| `~/.claude/settings.json` | Global  | Claude Code preferences.              |
| `~/.codex/config.toml`   | Global  | Codex CLI preferences.                |
| `~/.gemini/settings.json` | Global | Gemini CLI preferences.               |
| `init-ai.sh`        | Per-project    | Bootstraps `AI.md` + symlinks.        |
| `install.sh`         | Global         | Deploys all configs + skills.         |
