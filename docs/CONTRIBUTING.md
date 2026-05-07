# Contributing to PACE

PACE is a spec-driven development workflow for Claude Code. Contributions typically fall into one of four categories: new commands, new PACE agents, runtime library scripts, or documentation. This guide covers all four.

## Prerequisites

- Claude Code installed and configured
- At least one agent installed under `~/.claude/agents/` or `.claude/agents/`
- Familiarity with the [PACE workflow](getting-started.md) — specifically how `/pace:plan` and `/pace:execute` work

## Repository Structure

```
pace/
  src/
    agents/
      pace-synthesiser.md          # Top-level PACE agent (synthesiser)
      pace/
        pace-codebase-analyst.md   # PACE sub-agents
        pace-documentation-specialist.md
        pace-verification-specialist.md
    commands/
      pace/
        sync-agents.md             # 15 slash-command definitions
        roadmap.md
        plan.md
        execute.md
        verify.md
        fix.md
        amend.md
        resume.md
        status.md
        create-pr.md
        complete.md
        settings.md
        usage.md
    lib/
      token-usage.py               # Token aggregation script
      find-session.sh              # Session UUID discovery
      append-usage.sh              # Usage file writer
  docs/
    README.md
    CONTRIBUTING.md                # This file
    getting-started.md
    architecture.md
  examples/
    sample-plan.md
    sample-registry.md
    sample-state.md
  install.sh
  uninstall.sh
  LICENSE
```

Key directories:

- `src/commands/pace/` — slash-command definitions. Each file becomes a `/pace:*` command when installed.
- `src/agents/` — top-level agent definitions installed at `~/.claude/agents/pace-*.md` or `.claude/agents/pace-*.md`.
- `src/agents/pace/` — PACE specialist sub-agents. These are nested under the `pace/` namespace.
- `src/lib/` — standalone runtime scripts (Python and Bash) called by commands at execution time.

## File Formats

### Command files

Commands live in `src/commands/pace/` and are Markdown files with YAML frontmatter.

**Required frontmatter fields:**

| Field | Type | Description |
|---|---|---|
| `name` | string | The fully-qualified command name, e.g. `pace:plan` |
| `description` | string | One-sentence description shown in the command list |
| `argument-hint` | string | Short usage hint shown next to the command name, e.g. `[--tdd] [topic]` |
| `allowed-tools` | list | Tools the command may use, e.g. `Read`, `Write`, `Bash`, `Agent` |

**Example:**

```yaml
---
name: pace:plan
description: Interview the user, assemble a domain planning team, and produce PLAN.md
argument-hint: "[--tdd] [--research] [--abandon] [topic]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Agent
  - AskUserQuestion
---
```

The body of the command file is the instruction set that Claude Code executes when the command is invoked. Commands use XML-style `<objective>` and `<process>` sections to separate intent from procedure.

### Agent files

Agents live in `src/agents/` (top-level) or `src/agents/pace/` (PACE sub-agents) and are Markdown files with YAML frontmatter.

**Required frontmatter fields:**

| Field | Type | Description |
|---|---|---|
| `name` | string | The agent's identity, e.g. `pace-codebase-analyst` |
| `description` | string | One-sentence description used in the agent registry |
| `color` | string | Display colour, e.g. `cyan`, `blue`, `green` |
| `emoji` | string | Single emoji shown next to the agent name |
| `vibe` | string | Short personality tag — one sentence in quotes |

**Example:**

```yaml
---
name: pace-codebase-analyst
description: Interprets raw codebase scan output and writes a structured PROJECT.md capturing stack, structure, conventions, and entry points.
color: cyan
emoji: 🔬
vibe: "Reads a codebase like a doctor reads an X-ray — structure, patterns, and anomalies at a glance."
---
```

The body of the agent file defines the agent's identity, capabilities, workflow, and output format.

## Adding a New Command

1. Create `src/commands/pace/{command-name}.md` with the required frontmatter (see above).
2. Write the command body. Structure it with an `<objective>` block (what the command achieves) and a `<process>` block (the step-by-step execution logic).
3. If the command spawns agents, document which agents it uses and under what conditions.
4. If the command writes runtime files (e.g. to `.pace/`), document the file format in the process block.
5. Run `install.sh` to deploy the command to `~/.claude/commands/pace/` and test it in a project.
6. Update the command table in `CLAUDE.md` and `docs/README.md` if the command is user-facing.

**Constraints:**

- Commands are orchestrators — they route work to agents. They do not implement work directly.
- If a command needs to produce output, it delegates to a specialist agent.
- Tool access is declared in frontmatter and must be the minimum required. Avoid granting `Agent` unless the command genuinely spawns sub-agents.

## Adding a New PACE Agent

PACE has two agent locations:

- **Top-level agents** (`src/agents/`) — standalone agents that PACE commands spawn directly (e.g. `pace-synthesiser`).
- **Sub-agents** (`src/agents/pace/`) — specialist agents scoped to the PACE namespace (e.g. `pace-codebase-analyst`, `pace-verification-specialist`).

Choose `src/agents/pace/` for agents that are part of the PACE internal workflow. Choose `src/agents/` only for agents that act as standalone routing targets.

### Steps

1. Create the agent file with the required frontmatter (see above).
2. Write the agent body. Include:
   - An identity and memory section — who the agent is and what it remembers
   - A core mission section — what it produces
   - Critical rules — constraints the agent must never violate
   - A workflow — numbered steps from input to output
   - A communication style or success metrics section
3. Run `/pace:sync-agents` to rebuild the agent registry (see below).
4. Verify the agent appears in `.pace/AGENT-REGISTRY.md` under the correct division.

**Agent body conventions:**

- Write in second-person imperative ("You receive...", "You write...").
- Define observable success criteria — what the output file must contain, not what steps were taken.
- If the agent writes a file, specify the exact format in the workflow section.

## The Two-Tier Agent Registry

PACE uses a two-tier registry to avoid loading all agent descriptions into planning context at once.

**Tier 1 — `.pace/AGENT-REGISTRY.md`**

A division-level index, always loaded during `/pace:plan`. Contains one row per division with agent count and a brief capability summary. This file is generated — do not edit it by hand.

**Tier 2 — `.pace/agents/{division}.md`**

One file per division, containing the full name and description of every agent in that division. Loaded only when the planner selects that division for a task. These files are also generated.

The division is derived from the directory structure of the agent files: an agent at `~/.claude/agents/engineering/my-agent.md` belongs to the `engineering` division. An agent at the root of `~/.claude/agents/` (no subdirectory) falls into the `general` division.

### Running `/pace:sync-agents`

Run this command whenever you:

- Install a new agent (global or local)
- Rename or remove an existing agent
- Change an agent's `name` or `description` frontmatter field

```
/pace:sync-agents
```

The command scans both `~/.claude/agents/` (global) and `.claude/agents/` (local, project-scoped). Local agents take precedence over global agents with the same name. The registry files are written to `.pace/AGENT-REGISTRY.md` and `.pace/agents/`. Commit both after running.

## Adding a Runtime Library Script

Runtime scripts live in `src/lib/` and are installed to `~/.claude/lib/pace/` by `install.sh`.

- Python scripts (`.py`) are invoked with `python3` and handle data processing tasks (e.g. token aggregation).
- Bash scripts (`.sh`) handle filesystem and shell operations (e.g. session discovery, file appending).

When adding a script:

1. Place it in `src/lib/`.
2. Reference it in the relevant command file using the installed path: `~/.claude/lib/pace/{script-name}`.
3. Update `install.sh` to copy the new script to `~/.claude/lib/pace/`.
4. Document the script's input format, output format, and exit codes in a comment block at the top of the file.

## Testing Your Changes

PACE has no automated test suite. Verification is manual and workflow-based.

**For commands:**

1. Install with `install.sh`.
2. Run the command in a test project with a known state.
3. Verify the runtime files it produces (e.g. `PLAN.md`, `STATE.md`) match the documented format.
4. If the command spawns agents, confirm the agents receive accurate context and produce correct output.

**For agents:**

1. Run `/pace:sync-agents` and confirm the agent appears in the registry output.
2. Trigger a `/pace:plan` that would select the agent and verify it is assigned tasks correctly.
3. Run `/pace:execute` and observe the agent's output against its documented success criteria.

**For registry changes:**

After any agent addition or modification, run `/pace:sync-agents` and inspect both `.pace/AGENT-REGISTRY.md` and the relevant `.pace/agents/{division}.md` to confirm the agent appears with the correct name, description, and division.

## Key Design Principles

When contributing, keep these constraints in mind:

- **Orchestrators never implement** — commands route work to agents. If a command is doing implementation work itself, that work belongs in an agent.
- **Tasks are atomic** — each task in a plan has one agent owner, is completable in one session, and has observable success criteria.
- **State is a single file** — do not introduce new state files. All plan-execution state lives in `.pace/STATE.md`.
- **Bring your own agents** — PACE routes to whatever agents are installed. New PACE-internal behaviour should be added as a new agent or command, not as logic embedded in an existing command.

## Commit Guidelines

- One logical change per commit.
- Commit message subject line: 50 characters or fewer, imperative mood ("Add", "Fix", "Update").
- If the change affects installed files, include a note about running `install.sh`.

## Submitting a Pull Request

1. Fork the repository and create a branch from `main`.
2. Make your changes following the guidelines above.
3. Run `install.sh` and test the affected commands or agents manually.
4. Run `/pace:sync-agents` if you added or modified any agent files, and commit the updated registry files.
5. Open a pull request with a clear description of what changed and why.
