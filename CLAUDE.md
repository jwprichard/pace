# PACE — Plan, Assign, Coordinate, Execute

A spec-driven development workflow for Claude Code. PACE interviews you for requirements, produces small atomic plans, and delegates every task to the right specialist agent.

> For full project context, design decisions, and build order — load `CONTEXT.md`.

## Key Design Principles

- **Orchestrator never implements** — every task is delegated to a specialist agent. The orchestrator routes; it doesn't code, write, or design.
- **Agent routing is native** — the planner discovers installed agents and assigns agent hints at plan time, not after.
- **Bring your own agents** — PACE routes to whatever is installed in `~/.claude/agents/` and `.claude/agents/`. If no agent fits, the planner flags it rather than falling back to direct implementation.
- **Tasks are atomic** — each task has one agent owner, is completable in one session, and has observable success criteria. Plan size is not artificially limited.
- **State is simple** — a single `STATE.md`. No state machine.
- **Verification is goal-backward** — success criteria describe what must be true, not what was done.

## Commands

| Command | What it does |
|---|---|
| `/pace:sync-agents` | Scans installed agents, writes the two-tier agent registry |
| `/pace:roadmap` | Decomposes a large feature into ordered phases, produces `ROADMAP.md` |
| `/pace:plan` | Interviews user, produces `PLAN.md` with atomic tasks and agent hints |
| `/pace:execute` | Reads `PLAN.md`, delegates each task to the assigned specialist agent |
| `/pace:verify` | Checks completed work against `PLAN.md` success criteria |
| `/pace:fix` | Dispatches targeted fixes within the PACE lifecycle — `--light` for quick one-shot fixes |
| `/pace:amend` | Adds new tasks to the current plan mid-execution — `--light` for quick one-shot additions |
| `/pace:resume` | Reads `STATE.md`, picks up from the last incomplete task |
| `/pace:create-pr` | Creates a PR summarising what was requested, delivered, and verified |
| `/pace:settings` | View and manage PACE settings (model overrides, etc.) |
| `/pace:complete` | Reconciles branch state, finalises PR |

## Agents

| Agent | Role |
|---|---|
| `pace-synthesiser` | Merges parallel draft plans into a single `PLAN.md` |
| `pace-codebase-analyst` | Analyses raw codebase data and writes `PROJECT.md` — detects monorepo services when present |
| `pace-documentation-specialist` | Patches or rewrites `PROJECT.md` after tasks complete |
| `pace-verification-specialist` | Checks completed work against success criteria |

## Agent Registry

Two-tier structure to avoid loading 100+ agent descriptions into context unnecessarily.

- **Tier 1** — `.pace/AGENT-REGISTRY.md` — division-level index, always loaded during planning
- **Tier 2** — `.pace/agents/{division}.md` — full agent list per division, loaded only for relevant divisions

Run `/pace:sync-agents` after installing or updating agents.

## Runtime Files

```
.pace/
  AGENT-REGISTRY.md        # Tier 1 — division index (commit this)
  agents/                  # Tier 2 — per-division agent lists (commit these)
  ROADMAP.md               # Phase decomposition for large features (persists across plans)
  PLAN.md                  # Current plan
  STATE.md                 # Operational memory — task status and blockers
  PROJECT.md               # Codebase map — stack, structure, conventions (includes ## Services table for monorepo projects)
  settings.md              # Persistent workflow configuration — model override, etc. (not cleared by /pace:complete)
  memory/
    episode.md             # Episodic memory — what was built this execution (cleared at complete)
    semantic.md            # Semantic memory — cross-plan decisions and patterns (never cleared)
  requirements/
    brief.md               # Compiled interview requirements (plan-specific)
    research.md            # Research findings (plan-specific, --research only)
```

## Settings

PACE reads `.pace/settings.md` for persistent workflow configuration. This file is never cleared by `/pace:complete`. Use `/pace:settings` to view and modify settings interactively, or pass arguments directly (e.g. `/pace:settings set execute-model opus`).

### Model Override

Two separate model settings control planning and execution phases independently:

```markdown
# Settings
_Persistent configuration for the PACE workflow. This file is not cleared by /pace:complete._

## Model
plan-model: opus
execute-model: sonnet
```

| Setting | Accepted values | Which agents it controls |
|---|---|---|
| `plan-model` | `sonnet`, `opus`, `haiku` | Domain planners, synthesiser, research agents, codebase analyst |
| `execute-model` | `sonnet`, `opus`, `haiku` | Specialist implementers, verification, fix agents, documentation patches |

**Which commands read which setting:**
- **`plan-model`**: `/pace:plan`, `/pace:roadmap`, `/pace:scan`
- **`execute-model`**: `/pace:execute`, `/pace:fix`, `/pace:amend`, `/pace:verify`, `/pace:complete`, `/pace:agent`

**What it affects**: Only the specialist agents spawned by these commands. The orchestrator session model is unaffected — it continues to run on whatever model you started it with.

**When no `settings.md` exists** (or a field is blank): Behaviour is unchanged. Agents inherit the session model, exactly as they did before this setting existed.

## Repository Structure

```
pace/
  src/
    agents/
      pace-synthesiser.md
      pace/
        pace-codebase-analyst.md
        pace-documentation-specialist.md
        pace-verification-specialist.md
    commands/
      pace/
        sync-agents.md
        roadmap.md
        plan.md
        execute.md
        verify.md
        fix.md
        amend.md
        resume.md
        create-pr.md
        complete.md
        settings.md
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
