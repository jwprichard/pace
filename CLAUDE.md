# PACE — Plan, Assign, Coordinate, Execute

A spec-driven development workflow for Claude Code. PACE interviews you for requirements, produces small atomic plans, and delegates every task to the right specialist agent.

> For full project context, design decisions, and build order — load `CONTEXT.md`.

## Key Design Principles

- **Orchestrator never implements** — every task is delegated to a specialist agent. The orchestrator routes; it doesn't code, write, or design.
- **Agent routing is native** — the planner discovers installed agents and assigns agent hints at plan time, not after.
- **Bring your own agents** — PACE routes to whatever is installed in `~/.claude/agents/` and `.claude/agents/`. If no agent fits, the planner flags it rather than falling back to direct implementation.
- **Plans are small** — 2–4 tasks maximum. Bigger work gets split.
- **State is simple** — a single `STATE.md`. No state machine.
- **Verification is goal-backward** — success criteria describe what must be true, not what was done.

## Commands

| Command | What it does |
|---|---|
| `/pace:sync-agents` | Scans installed agents, writes the two-tier agent registry |
| `/pace:plan` | Interviews user, produces `PLAN.md` with atomic tasks and agent hints |
| `/pace:execute` | Reads `PLAN.md`, delegates each task to the assigned specialist agent |
| `/pace:verify` | Checks completed work against `PLAN.md` success criteria |
| `/pace:resume` | Reads `STATE.md`, picks up from the last incomplete task |
| `/pace:complete` | Reconciles branch state, finalises PR |

## Agents

| Agent | Role |
|---|---|
| `pace-planner` | Conducts planning interview, writes `PLAN.md` |
| `pace-orchestrator` | Reads `PLAN.md`, spawns the correct specialist per task |
| `pace-verifier` | Reads success criteria, checks work matches |

## Agent Registry

Two-tier structure to avoid loading 100+ agent descriptions into context unnecessarily.

- **Tier 1** — `.pace/AGENT-REGISTRY.md` — division-level index, always loaded during planning
- **Tier 2** — `.pace/agents/{division}.md` — full agent list per division, loaded only for relevant divisions

Run `/pace:sync-agents` after installing or updating agents.

## Runtime Files

```
.pace/
  AGENT-REGISTRY.md   # Tier 1 — division index (commit this)
  agents/             # Tier 2 — per-division agent lists (commit these)
  PLAN.md             # Current plan
  STATE.md            # Progress tracking across sessions
  DECISIONS.md        # Running decision log
```

## Repository Structure

```
pace/
  src/
    agents/
      pace-planner.md
      pace-orchestrator.md
      pace-verifier.md
    commands/
      pace/
        sync-agents.md
        plan.md
        execute.md
        verify.md
        resume.md
        complete.md
  docs/
    README.md
    CONTRIBUTING.md
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
