# PROJECT MAP
_Scanned: 2026-05-04T22:44:53Z_
_Commit: 3c0263a_

## Stack
- **Language:** Markdown (command/agent definitions), Bash (installer)
- **Runtime:** Claude Code slash-command runtime
- **Framework:** PACE (Plan, Assign, Coordinate, Execute) — self-hosted
- **Database:** none
- **Test runner:** none detected

## Structure
- `src/commands/pace/` — slash-command definitions (11 commands) installed into `.claude/commands/pace/`
- `src/agents/` — top-level agent definitions (pace-synthesiser)
- `src/agents/pace/` — PACE specialist sub-agents (codebase-analyst, documentation-specialist, verification-specialist)
- `docs/` — user-facing documentation (README, architecture)
- `.pace/` — runtime state (PLAN.md, STATE.md, AGENT-REGISTRY.md, drafts, memory, requirements)
- `.pace/agents/` — tier-2 agent registry files, one per division (15 divisions)
- `.pace/memory/` — episodic and semantic memory files
- `.pace/requirements/` — compiled interview brief and optional research findings
- `.pace/drafts/` — intermediate draft plans from parallel domain planners

## Entry Points
- `install.sh` — copies `src/commands/` and `src/agents/` into `~/.claude/` or `./.claude/`; supports `--global`, `--local`, `--force`
- `uninstall.sh` — removes previously installed PACE files from target destination
- `/pace:sync-agents` — scans installed agents, writes tier-1 and tier-2 registry files
- `/pace:plan` — interviews user, spawns domain planner agents in parallel, synthesises into `PLAN.md`; supports `--tdd`, `--research`, `--abandon`
- `/pace:execute` — reads `PLAN.md`, delegates each task to the assigned specialist agent, tracks progress in `STATE.md`
- `/pace:verify` — checks completed work against `PLAN.md` success criteria; auto-fix loop on NEEDS WORK verdict
- `/pace:fix` — dispatches targeted fixes; `--light` for quick one-shot fixes
- `/pace:resume` — reads `STATE.md`, picks up from the last incomplete task
- `/pace:roadmap` — interviews user, decomposes a large feature into phases, produces `ROADMAP.md`; supports `--research`, `--abandon`
- `/pace:complete` — reconciles branch state, finalises PR, triggers full PROJECT.md refresh
- `/pace:create-pr` — creates a PR summarising what was requested, delivered, and verified; supports `--auto-review`
- `/pace:agent` — dispatches a specialist agent with baked-in codebase context
- `/pace:scan` — standalone codebase scan producing `.pace/PROJECT.md`

## Key Config
- `install.sh` — sets `VERSION="0.1.0"`, controls install targets and conflict handling
- `.claude/settings.local.json` — project-local Claude Code settings
- `CLAUDE.md` — project instructions loaded into every Claude Code session; defines key design principles, commands, agents, and runtime file layout
- `CONTEXT.md` — full project context, design decisions, and build order (gitignored)
- `.gitignore` — excludes CONTEXT.md, EXECUTE-CONTEXT.md, and runtime files (PLAN.md, STATE.md, DECISIONS.md, drafts/)

## Conventions
- Commands are `.md` files with YAML frontmatter (`name`, `description`, `argument-hint`, `allowed-tools`)
- Agents are `.md` files with YAML frontmatter (`name`, `description`, `color`, `emoji`, `vibe`)
- Sub-agents are nested under a named directory matching the parent namespace (e.g. `src/agents/pace/`)
- PACE runtime files live exclusively in `.pace/`; none of the src/ files are mutated at runtime
- Orchestrator agents never implement — they delegate every task to a specialist
- Tasks in PLAN.md are atomic: one agent, one session, observable success criteria
- Agent registry uses a two-tier structure: tier-1 division index always loaded, tier-2 division detail loaded on demand
- `--tdd` flag opt-in: when passed to `/pace:plan`, threads TDD requirements through planner team assembly and synthesiser enforcement
- `--research` flag opt-in: when passed to `/pace:plan`, activates research mode; Stage 1.5 runs before the interview — a research Task searches the web and writes findings to `.pace/requirements/research.md`, then displays a bullet summary inline; in Stage 4, full contents are appended to every domain planner Task prompt; in Stage 5, the synthesiser writes `_Research: enabled_` in PLAN.md
- `## Services` section in PROJECT.md is conditional — the codebase analyst writes it only when two or more monorepo signals are detected (workspace configs, `apps/`/`services/`/`packages/` dirs with their own package files, `docker-compose.yml` service entries, etc.); omitted entirely for single-project repos
- `**Service:**` field in PLAN.md tasks is optional — added by domain and TDD planners only when PROJECT.md contains a `## Services` section; service names must match a row in the Services table; synthesiser preserves Service annotations during merge and does not flag absence as an error

## Test Setup
- **Runner:** none
- **Location:** none
- **Command:** unknown
