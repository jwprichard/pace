# PACE — Plan, Assign, Coordinate, Execute

A spec-driven development workflow for Claude Code. PACE interviews you for requirements, produces small atomic plans, and delegates every task to the right specialist agent.

> For full project context, design decisions, and build order — load `CONTEXT.md`.

## Key Design Principles

- **Orchestrator never implements** — every task is delegated to a specialist agent. The orchestrator routes; it doesn't code, write, or design.
- **One agent per stage** — planning, execution, and review each run singular agents. One planner writes the plan, one specialist executes each task in turn, one verifier checks the work. No agent swarms, no draft merging.
- **Agent routing is native** — the planner discovers installed agents and assigns agent hints at plan time, not after.
- **Bring your own agents** — PACE routes to whatever is installed in `~/.claude/agents/` and `.claude/agents/`. If no agent fits, the planner flags it rather than falling back to direct implementation.
- **Tasks are atomic** — each task has one agent owner, is completable in one session, and has observable success criteria. Plan size is not artificially limited.
- **Execution is sequential** — tasks run one at a time in Implementation Order, each in a fresh agent context, each committed before the next starts.
- **State is simple** — a single `STATE.md`. No state machine.
- **Verification is goal-backward** — success criteria describe what must be true, not what was done.

## Commands

| Command | What it does |
|---|---|
| `/pace:sync-agents` | Scan installed agents and build the PACE agent registry |
| `/pace:roadmap` | Interview the user, decompose a large feature into phases, and produce `ROADMAP.md` |
| `/pace:plan` | Interview the user, then produce `PLAN.md` via a single planner agent |
| `/pace:scan` | Scans the codebase and produces `.pace/PROJECT.md` for use by planning and execution agents |
| `/pace:execute` | Reads `PLAN.md`, delegates each task to its assigned specialist agent one at a time, and tracks progress in `STATE.md` |
| `/pace:verify` | Checks completed work against `PLAN.md` success criteria using the pace-verification-specialist |
| `/pace:fix` | Dispatches targeted fixes within the PACE lifecycle — structured by default, `--light` for quick one-shot fixes |
| `/pace:amend` | Adds new tasks to the current plan mid-execution — structured by default, `--light` for quick one-shot additions |
| `/pace:agent` | Dispatches a specialist agent with baked-in codebase context — no blind exploration needed |
| `/pace:status` | Shows the current plan status, progress, and suggested next steps — read-only, no work is executed |
| `/pace:resume` | Picks up execution from the last incomplete task in `STATE.md` |
| `/pace:create-pr` | Creates a PR from the PACE workflow — summarising what was requested, what was delivered, and what was verified |
| `/pace:settings` | View and manage PACE workflow settings |
| `/pace:usage` | Display token usage and cost breakdown for the current plan — grand total, per-phase subtotals, and per-task detail rows |
| `/pace:complete` | Closes out a completed plan — full `PROJECT.md` refresh and `.pace/` runtime cleanup |

## Agents

| Agent | Role |
|---|---|
| `pace-planner` | Produces a complete `PLAN.md` directly from the requirements brief, codebase context, and agent registry. Spawned by `/pace:plan` after the interview completes. |
| `pace-codebase-analyst` | Interprets raw codebase scan output and writes a structured `PROJECT.md` capturing stack, structure, conventions, and entry points. |
| `pace-documentation-specialist` | Maintains `.pace/PROJECT.md` as a living codebase map — patches it after each execution run and rewrites it fully on plan close. |
| `pace-verification-specialist` | Verifies completed work against `PLAN.md` success criteria using evidence-based checks — files, greps, and bash commands. |

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
  usage.md                 # Token usage and cost tracking — per-phase and per-task breakdown (cleared by /pace:plan, preserved by /pace:complete)
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
| `plan-model` | `sonnet`, `opus`, `haiku` | Planner, roadmap planner, research agents, codebase analyst |
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
      pace/
        pace-codebase-analyst.md
        pace-documentation-specialist.md
        pace-planner.md
        pace-verification-specialist.md
    commands/
      pace/
        sync-agents.md
        roadmap.md
        plan.md
        scan.md
        execute.md
        verify.md
        fix.md
        amend.md
        agent.md
        status.md
        resume.md
        create-pr.md
        settings.md
        usage.md
        complete.md
    lib/
      token-usage.py
      find-session.sh
      append-usage.sh
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
