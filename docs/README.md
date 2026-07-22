# PACE

**Plan, Assign, Coordinate, Execute**

A spec-driven development workflow for Claude Code. PACE interviews you for requirements, produces atomic plans, and delegates every task to the right specialist agent. No single-session degradation, no agents doing work outside their expertise.

PACE doesn't ship its own agents — it discovers whatever agents you have installed and routes to them intelligently. Bring your own agent roster.

## How It Works

1. **Sync** — PACE scans your installed agents and builds a two-tier registry
2. **Scan** — PACE maps your codebase structure and writes `PROJECT.md` so agents have accurate context
3. **Plan** — An interview extracts requirements; a single planner agent turns them into `PLAN.md`
4. **Execute** — Each task is delegated to its assigned specialist agent, one at a time in Implementation Order; each task is committed before the next begins
5. **Verify** — Completed work is checked against the plan's success criteria
6. **Complete** — Branch is reconciled, runtime files are cleaned up, and the PR is finalised

Tasks are atomic: each has one agent owner, is completable in one session, and has observable success criteria. Plan size is not artificially limited — a plan has as many tasks as the work genuinely requires.

## Lifecycle Diagram

```mermaid
flowchart TD
    SA["/pace:sync-agents\nBuild agent registry"]
    SC["/pace:scan\nMap codebase → PROJECT.md"]
    RM["/pace:roadmap\nDecompose into phases\n(optional)"]
    PL["/pace:plan\nInterview → PLAN.md"]
    EX["/pace:execute\nDelegate tasks to specialists"]
    VF["/pace:verify\nCheck success criteria"]
    CP["/pace:complete\nReconcile branch, clean up"]

    SA --> SC
    SC --> RM
    RM --> PL
    SC --> PL
    PL --> EX
    EX --> VF
    VF --> CP

    FX["/pace:fix\nTargeted fixes"]
    AM["/pace:amend\nAdd tasks mid-plan"]
    RS["/pace:resume\nPick up from last incomplete task"]

    EX --> FX
    FX --> EX
    EX --> AM
    AM --> EX
    EX --> RS
    RS --> EX

    ST["/pace:status\nRead-only progress view"]
    AG["/pace:agent\nDispatch one specialist directly"]
    SE["/pace:settings\nModel overrides"]
    US["/pace:usage\nToken usage breakdown"]
    PR["/pace:create-pr\nOpen pull request"]

    EX -.-> ST
    EX -.-> AG
    PL -.-> SE
    EX -.-> US
    VF -.-> PR
```

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
# 1. Build the agent registry (required before planning)
/pace:sync-agents

# 2. Map your codebase (required before planning)
/pace:scan

# 3. Start planning
/pace:plan
```

## Commands

| Command | What it does |
|---|---|
| `/pace:sync-agents` | Scan installed agents and build the PACE agent registry |
| `/pace:scan` | Scans the codebase and produces `.pace/PROJECT.md` for use by planning and execution agents |
| `/pace:roadmap` | Interview the user, decompose a large feature into phases, and produce `ROADMAP.md` |
| `/pace:plan` | Interview the user, then produce `PLAN.md` via a single planner agent |
| `/pace:execute` | Reads `PLAN.md`, delegates each task to the assigned specialist agent, and tracks progress in `STATE.md` |
| `/pace:verify` | Checks completed work against `PLAN.md` success criteria using the pace-verification-specialist |
| `/pace:fix` | Dispatches targeted fixes within the PACE lifecycle — structured by default, `--light` for quick one-shot fixes |
| `/pace:amend` | Adds new tasks to the current plan mid-execution — structured by default, `--light` for quick one-shot additions |
| `/pace:status` | Shows the current plan status, progress, and suggested next steps — read-only, no work is executed |
| `/pace:resume` | Picks up execution from the last incomplete task in `STATE.md` |
| `/pace:create-pr` | Creates a PR from the PACE workflow — summarising what was requested, what was delivered, and what was verified |
| `/pace:settings` | View and manage PACE workflow settings |
| `/pace:usage` | Display token usage and cost breakdown for the current plan — grand total, per-phase subtotals, and per-task detail rows |
| `/pace:complete` | Closes out a completed plan — full `PROJECT.md` refresh and `.pace/` runtime cleanup |
| `/pace:agent` | Dispatches a specialist agent with baked-in codebase context — no blind exploration needed |

## Command Internals

### /pace:plan

```mermaid
flowchart TD
    F0["Stage 0: Parse flags\n--tdd, --research, --abandon"]
    F1["Stage 1: Pre-flight\nLoad settings + model override\nCheck agent registry\nCheck PROJECT.md (scan if missing)\nCheck prior plan state\nCheck roadmap context\nClear plan artifacts\nCapture session UUID"]
    F15["Stage 1.5: Research\n(--research only)\nWebSearch + WebFetch\nWrite requirements/research.md"]
    F2["Stage 2: Interview\nParse prompt + state understanding\nAsk 2-4 targeted questions\nWrite requirements/brief.md"]
    F3["Stage 3: Plan\nSpawn pace-planner with brief +\nPROJECT.md + agent registry\nWrites PLAN.md directly\n(TDD rules applied if --tdd)"]
    F4["Stage 4: Token usage\nAggregate + record planning tokens"]
    F5{"Stage 5: Approval\nApprove / Edit / Reject"}
    F5A["Write STATE.md\nCreate branch if on main/master"]
    F5B["Apply edits\nRe-present plan"]
    F5C["Discard PLAN.md\nStart over"]

    F0 --> F1
    F1 --> F15
    F15 --> F2
    F1 --> F2
    F2 --> F3
    F3 --> F4
    F4 --> F5
    F5 -->|Approve| F5A
    F5 -->|Edit| F5B
    F5B --> F5
    F5 -->|Reject| F5C
```

### /pace:execute

```mermaid
flowchart TD
    E1["Stage 1: Pre-flight\nLoad PLAN.md + STATE.md\nExtract session UUID\nDerive encoded project path\nStaleness check (PROJECT.md vs HEAD)\nLoad semantic memory\nRead model override from settings.md"]
    E2["Stage 2: Load tasks + build run order\nParse pending/in_progress tasks\nOrder by PLAN.md Implementation Order\nRegister tasks in Claude task system"]
    E3a["Stage 3a: Mark task in_progress\nEdit STATE.md: [ ] → [~]\nTaskUpdate → in_progress"]
    E3b["Stage 3b: Spawn the specialist agent\nBuild context from PLAN.md\nOne task, one agent\nWait for it to complete"]
    E3c["Stage 3c: Commit the task's changes\ngit add files from ## Files Modified\ngit commit with task title"]
    E3d["Stage 3d: Record the outcome\nSTATE.md: [~] → [x] or [!]\nepisode.md: append completion summary\nToken usage recording\nOn failure: record blocker, stop"]
    E4["Stage 4: Complete\nDoc-specialist patch (once, whole run)\nSTATE.md status → complete\nRecord execute dispatcher token usage\nTell user to run /pace:verify"]

    E1 --> E2
    E2 --> E3a
    E3a --> E3b
    E3b --> E3c
    E3c --> E3d
    E3d -->|next task| E3a
    E3d -->|all done| E4
    E3d -->|blocked| STOP["Stop — surface blocker\nRun /pace:resume to retry"]
```

## Agent Registry

PACE uses a two-tier registry to avoid loading 100+ agent descriptions into context when only a few are needed.

**Tier 1** — `.pace/AGENT-REGISTRY.md` is a division-level index. The planner always loads this and uses it to identify which divisions are relevant to the current work.

**Tier 2** — `.pace/agents/{division}.md` files contain the full agent list per division. Only relevant divisions are loaded during planning.

Run `/pace:sync-agents` any time you install, remove, or update agents. The registry is committed to the repo so the whole team stays in sync.

## Runtime Files

PACE creates a `.pace/` directory in your project root:

```
.pace/
  AGENT-REGISTRY.md        # Tier 1 — division index (commit this)
  agents/                  # Tier 2 — per-division agent lists (commit these)
  ROADMAP.md               # Phase decomposition for large features (persists across plans)
  PLAN.md                  # Current plan with tasks and success criteria
  STATE.md                 # Operational memory — task status and blockers
  PROJECT.md               # Codebase map — stack, structure, conventions
  settings.md              # Persistent configuration — not cleared by /pace:complete
  usage.md                 # Token usage and cost tracking — per-phase and per-task breakdown
  memory/
    episode.md             # Episodic memory — what was built this execution (cleared at complete)
    semantic.md            # Semantic memory — cross-plan decisions and patterns (never cleared)
  requirements/
    brief.md               # Compiled interview requirements (plan-specific)
    research.md            # Research findings (plan-specific, --research only)
```

`AGENT-REGISTRY.md`, `agents/`, `PROJECT.md`, and `settings.md` are safe to commit. The rest are plan-scoped runtime state.

## Configuration

PACE reads `.pace/settings.md` for persistent workflow configuration. This file is never cleared by `/pace:complete`, so your preferences carry across plans. Use `/pace:settings` to view and modify settings interactively, or pass arguments directly (e.g. `/pace:settings set execute-model opus`).

### Model Override

Two separate settings control planning and execution phases independently:

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

The orchestrator session model is unaffected. When a field is blank or `settings.md` does not exist, agents inherit the session model as before.

## Key Principles

**The orchestrator never implements.** Every task is delegated to a specialist. The orchestrator routes — it doesn't code, write, or design.

**Fresh context per task.** Each task runs in an isolated agent session. No context degradation across a multi-task plan.

**Tasks are atomic.** Each task has one agent owner, is completable in one session, and has observable success criteria. Plan size is not artificially limited — a plan contains as many tasks as the work genuinely requires.

**Verification is goal-backward.** Success criteria describe what must be true, not what was done.

**Bring your own agents.** PACE routes to whatever agents are installed. It works with Agency Agents, custom agents, or any combination. If no agent fits a task, the planner flags it instead of falling back to direct implementation.

**State is simple.** A single `STATE.md` file tracks all task progress. No state machine, no database.

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
