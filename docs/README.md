# PACE

**Plan, Assign, Coordinate, Execute**

A spec-driven development workflow for Claude Code. PACE interviews you for requirements, produces small atomic plans, and delegates every task to the right specialist agent. No single-session degradation, no agents doing work outside their expertise.

PACE doesn't ship its own agents — it discovers whatever agents you have installed and routes to them intelligently. Bring your own agent roster.

## How It Works

1. **Sync** — PACE scans your installed agents and builds a registry
2. **Plan** — An interview extracts requirements and produces a plan with 2-4 atomic tasks
3. **Execute** — Each task is delegated to the best-fit specialist agent in a fresh context
4. **Verify** — Completed work is checked against the plan's success criteria

## Quick Start

### Install

```bash
# Global — available in all projects
./install.sh

# Project-scoped — committed to repo, shared with team
./install.sh --local
```

### First Run

```bash
# Build the agent registry (required before planning)
/pace:sync-agents

# Start planning
/pace:plan
```

## Commands

| Command | What it does |
|---|---|
| `/pace:sync-agents` | Scans installed agents, writes the agent registry |
| `/pace:plan` | Interviews you, produces PLAN.md with atomic tasks |
| `/pace:execute` | Reads PLAN.md, delegates each task to a specialist agent |
| `/pace:verify` | Checks completed work against plan success criteria |
| `/pace:fix` | Dispatches targeted fixes — structured by default, `--light` for quick one-shot |
| `/pace:resume` | Picks up from the last incomplete task |
| `/pace:complete` | Reconciles branch state, finalises PR |

## Agent Registry

PACE uses a two-tier registry to avoid loading 100+ agent descriptions into context when only a few are needed.

**Tier 1** — `.pace/AGENT-REGISTRY.md` is a division-level index. The planner always loads this and uses it to identify which divisions are relevant to the current work.

**Tier 2** — `.pace/agents/{division}.md` files contain the full agent list per division. Only relevant divisions are loaded during planning.

Run `/pace:sync-agents` any time you install, remove, or update agents. The registry is committed to the repo so the whole team stays in sync.

## Runtime Files

PACE creates a `.pace/` directory in your project root:

```
.pace/
  AGENT-REGISTRY.md   # Tier 1 — division index
  PLAN.md              # Current plan with tasks and success criteria
  STATE.md             # Progress tracking across sessions
  agents/              # Tier 2 — per-division agent lists
    engineering.md
    design.md
    ...
```

These files are generated — don't edit them by hand (except STATE.md if you need to manually mark a task).

## Key Principles

**The orchestrator never implements.** Every task is delegated to a specialist. The orchestrator routes — it doesn't code, write, or design.

**Fresh context per task.** Each task runs in an isolated agent session. No context degradation across a multi-task plan.

**Plans are small.** 2-4 tasks maximum. If the work is bigger, split it into multiple plans.

**Verification is goal-backward.** Success criteria describe what must be true, not what was done.

**Bring your own agents.** PACE routes to whatever agents are installed. It works with Agency Agents, custom agents, or any combination. If no agent fits a task, the planner flags it instead of falling back to direct implementation.

## Install Targets

| Flag | Destination | Use case |
|---|---|---|
| `--global` (default) | `~/.claude/` | Solo dev, available everywhere |
| `--local` | `./.claude/` | Team project, committed to repo |

## Uninstall

```bash
# Remove PACE commands and agents
./uninstall.sh

# Also remove runtime files (.pace/)
./uninstall.sh --include-runtime

# Remove from a local install
./uninstall.sh --local --include-runtime
```

The uninstaller only removes PACE files — it never touches your other agents or commands.

## Requirements

- Claude Code with agent and command support
- Specialist agents installed (e.g. [Agency Agents](https://github.com/wshobson/agents) or your own)

## License

MIT
