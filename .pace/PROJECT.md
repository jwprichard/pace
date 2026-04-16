# PROJECT MAP
_Scanned: 2026-04-15T00:30:00Z_
_Commit: eabde35_

## Stack
- **Language:** Markdown (command/agent definitions), Bash (installer)
- **Runtime:** Claude Code slash-command runtime
- **Framework:** PACE (Plan, Assign, Coordinate, Execute) — self-hosted
- **Database:** none
- **Test runner:** none detected

## Structure
- `src/commands/pace/` — slash-command definitions installed into `.claude/commands/pace/`
- `src/agents/` — top-level agent definitions (pace-synthesiser)
- `src/agents/pace/` — PACE specialist sub-agents (codebase-analyst, documentation-specialist, verification-specialist)
- `docs/` — user-facing documentation (README, architecture)
- `.pace/` — runtime state (PLAN.md, STATE.md, AGENT-REGISTRY.md, per-division agent lists, drafts)
- `.pace/agents/` — tier-2 agent registry files, one per division

## Entry Points
- `install.sh` — copies `src/commands/` and `src/agents/` into `~/.claude/` or `./.claude/`; supports `--global`, `--local`, `--force`
- `uninstall.sh` — removes previously installed PACE files from target destination
- `/pace:sync-agents` — scans installed agents, writes tier-1 and tier-2 registry files
- `/pace:plan` — interviews user, spawns domain planner agents in parallel, synthesises into `PLAN.md`
- `/pace:execute` — reads `PLAN.md`, delegates each task to the assigned specialist agent, tracks progress in `STATE.md`
- `/pace:verify` — checks completed work against `PLAN.md` success criteria; auto-fix loop on NEEDS WORK verdict
- `/pace:resume` — reads `STATE.md`, picks up from the last incomplete task
- `/pace:complete` — reconciles branch state, finalises PR, triggers full PROJECT.md refresh
- `/pace:agent` — dispatches a specialist agent with baked-in codebase context
- `/pace:scan` — standalone codebase scan producing `.pace/PROJECT.md`

## Key Config
- `install.sh` — sets `VERSION="0.1.0"`, controls install targets and conflict handling
- `.claude/settings.local.json` — project-local Claude Code settings
- `CLAUDE.md` — project instructions loaded into every Claude Code session; defines key design principles, commands, agents, and runtime file layout

## Conventions
- Commands are `.md` files with YAML frontmatter (`name`, `description`, `argument-hint`, `allowed-tools`)
- Agents are `.md` files with YAML frontmatter (`name`, `description`, `color`, `emoji`, `vibe`)
- Sub-agents are nested under a named directory matching the parent namespace (e.g. `src/agents/pace/`)
- PACE runtime files live exclusively in `.pace/`; none of the src/ files are mutated at runtime
- Orchestrator agents never implement — they delegate every task to a specialist
- Tasks in PLAN.md are atomic: one agent, one session, observable success criteria
- Agent registry uses a two-tier structure: tier-1 division index always loaded, tier-2 division detail loaded on demand
- `--tdd` flag opt-in: when passed to `/pace:plan`, threads TDD requirements through planner team assembly and synthesiser enforcement
- `--research` flag opt-in: when passed to `/pace:plan`, activates research mode; Stage 1.5 runs before the interview — a research Task (dangerouslySkipPermissions: true) searches the web and writes findings to `.pace/research.md`, then displays a bullet summary inline; detected independently of `--tdd` in Stage 2a with its own flag stripping; in Stage 4, full contents of `.pace/research.md` are appended as a `## Research Findings` section to every domain planner Task prompt and (when `tdd_mode` is also true) to the TDD peer planner Task prompt; in Stage 5, the same findings are appended to the synthesiser prompt and the synthesiser is instructed to write `_Research: enabled_` immediately after `_Generated: {timestamp}_` in PLAN.md, enabling downstream commands to detect research mode by reading PLAN.md

## Test Setup
- **Runner:** none
- **Location:** none
- **Command:** unknown
