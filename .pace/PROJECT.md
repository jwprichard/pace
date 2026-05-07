# PROJECT MAP
_Scanned: 2026-05-07T03:59:35Z_
_Commit: 6301a14_

## Stack
- **Language:** Markdown (command/agent definitions), Bash (installer, shell scripts), Python 3 (lib scripts)
- **Runtime:** Claude Code slash-command runtime
- **Framework:** PACE (Plan, Assign, Coordinate, Execute) — self-hosted
- **Database:** none
- **Test runner:** none detected

## Structure
- `src/lib/` — standalone runtime scripts (Python and Bash) used by PACE commands
- `src/commands/pace/` — slash-command definitions (15 commands) installed into `.claude/commands/pace/`
- `src/agents/` — top-level agent definitions (pace-synthesiser)
- `src/agents/pace/` — PACE specialist sub-agents (codebase-analyst, documentation-specialist, verification-specialist)
- `docs/` — user-facing documentation (README, architecture)
- `.pace/` — runtime state (PLAN.md, STATE.md, AGENT-REGISTRY.md, settings.md, usage.md, drafts, memory, requirements)
- `.pace/agents/` — tier-2 agent registry files, one per division
- `.pace/memory/` — episodic and semantic memory files
- `.pace/requirements/` — compiled interview brief and optional research findings
- `.pace/drafts/` — intermediate draft plans from parallel domain planners

## Entry Points
- `install.sh` — copies `src/commands/`, `src/agents/`, and `src/lib/` into `~/.claude/` or `./.claude/`; lib scripts land at `{dest}/lib/pace/`; supports `--global`, `--local`, `--force`
- `uninstall.sh` — removes previously installed PACE files including `lib/pace/` from target destination; supports `--global`, `--local`, `--include-runtime`
- `/pace:plan` — interviews user, spawns domain planner agents in parallel, synthesises into `PLAN.md`; clears `usage.md` and records planning-phase usage on completion
- `/pace:execute` — reads `PLAN.md`, delegates each task to the assigned specialist agent, tracks progress in `STATE.md`; records per-task usage and orchestrator usage on completion
- `/pace:verify` — checks completed work against `PLAN.md` success criteria; records verification-specialist and fix-agent usage
- `/pace:fix` — dispatches targeted fixes; `--light` for quick one-shot fixes; records fix-agent usage in both modes
- `/pace:amend` — adds new tasks to the current plan mid-execution; `--light` for quick one-shot additions; records amendment-agent usage in both modes
- `/pace:resume` — reads `STATE.md`, picks up from the last incomplete task
- `/pace:roadmap` — interviews user, decomposes a large feature into phases, produces `ROADMAP.md`
- `/pace:complete` — reconciles branch state, finalises PR, triggers full PROJECT.md refresh; records memory-synthesis and doc-refresh usage; preserves `usage.md` during cleanup
- `/pace:create-pr` — creates a PR summarising what was requested, delivered, and verified; reads `.pace/usage.md` and includes a `## Token Usage` section in the PR body when usage data is available
- `/pace:agent` — dispatches a specialist agent with baked-in codebase context
- `/pace:scan` — standalone codebase scan producing `.pace/PROJECT.md`
- `/pace:settings` — view and manage PACE settings (model overrides)
- `/pace:status` — read-only plan progress report showing task status and suggested next steps
- `/pace:sync-agents` — scans installed agents, writes tier-1 and tier-2 registry files
- `/pace:usage` — read-only token usage report; reads `.pace/usage.md` and formats grand total, per-phase subtotals, and per-task detail rows via `token-usage.py format detail`
- `src/lib/token-usage.py` — aggregates and formats Claude Code token usage from JSONL logs; subcommands: `aggregate` (deduplicate + cost calc) and `format detail|summary` (markdown table output); deduplication uses per-field max keyed on `message.id:requestId`
- `src/lib/find-session.sh` — identifies the current Claude Code session UUID by encoding CWD path and finding the most recently modified JSONL file
- `src/lib/append-usage.sh` — appends a token usage JSON record to `.pace/usage.md`; accepts phase, task, and agent-type arguments; creates `usage.md` with session header if absent; inserts rows after the last existing data row in the correct phase section

## Key Config
- `install.sh` — sets `VERSION="0.1.0"`, controls install targets and conflict handling
- `.claude/settings.local.json` — project-local Claude Code settings
- `CLAUDE.md` — project instructions loaded into every Claude Code session; defines key design principles, commands, agents, and runtime file layout
- `CONTEXT.md` — full project context, design decisions, and build order (gitignored)
- `.pace/settings.md` — persistent PACE configuration; `plan-model` and `execute-model` control specialist agent model selection independently; not cleared by `/pace:complete`
- `.pace/usage.md` — token usage log; phase-grouped markdown tables; cleared by `/pace:plan`, preserved by `/pace:complete`
- `.gitignore` — excludes CONTEXT.md, EXECUTE-CONTEXT.md, and runtime files (PLAN.md, STATE.md, DECISIONS.md, drafts/)

## Conventions
- Commands are `.md` files with YAML frontmatter (`name`, `description`, `argument-hint`, `allowed-tools`)
- Agents are `.md` files with YAML frontmatter (`name`, `description`, `color`, `emoji`, `vibe`)
- Sub-agents are nested under a named directory matching the parent namespace (e.g. `src/agents/pace/`)
- PACE runtime files live exclusively in `.pace/`; none of the `src/` files are mutated at runtime
- Orchestrator agents never implement — they delegate every task to a specialist
- Tasks in PLAN.md are atomic: one agent, one session, observable success criteria
- Agent registry uses a two-tier structure: tier-1 division index always loaded, tier-2 division detail loaded on demand
- Model override uses two separate settings: `plan-model` (planners, synthesiser, research, analyst) and `execute-model` (implementers, verification, fixes, docs patches); every spawning command reads `.pace/settings.md` during pre-flight and passes the value as the `model` parameter on Agent tool calls
- `## Services` section in PROJECT.md is conditional — written only when two or more monorepo signals are detected; omitted for single-project repos
- Token usage is recorded per-phase into `.pace/usage.md` using `append-usage.sh`; session UUID is captured at plan start via `find-session.sh` and stored in `STATE.md` as `_Session:_`; all five PACE lifecycle commands (plan, execute, verify, fix, amend) instrument usage recording; `/pace:complete` preserves `usage.md` and records its own agents; `/pace:create-pr` reads `usage.md` and includes the formatted summary in the PR body

## Test Setup
- **Runner:** none
- **Location:** none
- **Command:** unknown
