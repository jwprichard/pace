# Semantic Memory

## Add monorepo service awareness to PACE planning pipeline — 2026-05-05

### Decisions
- Monorepo detection requires two corroborating signals before a project is classified as a monorepo _(avoids false positives from a single config file that might serve a different purpose)_
- The `**Service:**` field in plan tasks is conditional — omitted entirely when PROJECT.md has no `## Services` section _(keeps plans clean for single-service repos; planners and synthesiser both respect this)_
- Service names in plan tasks must match entries in PROJECT.md's `## Services` table exactly _(single source of truth; no ad-hoc naming)_
- The `## Services` table in PROJECT.md sits between `## Structure` and `## Entry Points` _(logical placement: structure describes the layout, services detail the logical units within it)_

### Patterns
- Conditional sections in PROJECT.md — the codebase analyst skips sections that don't apply rather than emitting empty headings
- Pipeline-wide feature threading — a new concept (service awareness) required changes at every stage: analysis (codebase-analyst), planning (plan.md Stage 4 planners), synthesis (plan.md Stage 5 + synthesiser agent), and documentation (CLAUDE.md). Each stage must explicitly handle the new field or it gets silently dropped.
- Synthesiser verify checklist must mark optional fields as optional — otherwise verification falsely flags their absence as errors

## Add persistent model override setting for specialist agent spawning — 2026-05-05

### Decisions
- Settings live in a dedicated `.pace/settings.md` file, separate from CLAUDE.md and other runtime files _(separates user-facing configuration from project instructions and operational state)_
- `settings.md` is never cleared by `/pace:complete` — it persists across plan lifecycles _(establishes a new category of runtime file: persistent user configuration, distinct from plan-scoped runtime files like STATE.md and episode.md)_
- Model override affects only spawned specialist agents, never the orchestrator session _(separation of concerns: the user controls agent cost/quality without altering their own interactive session)_
- Absent `settings.md` or blank `model:` field means unchanged behaviour — no error, no warning _(graceful degradation; the feature is purely additive and cannot break existing workflows)_

### Patterns
- Settings are read once during pre-flight/initialization and the extracted value is threaded to every spawn point within the command — consistent structure across all 8 command files
- New cross-cutting concerns (like model override) require touching every command file that spawns agents — reinforces the pipeline-wide threading pattern from monorepo service awareness, but applied to orchestrator infrastructure rather than plan metadata

## Add token usage tracking system for PACE — 2026-05-07

### Decisions
- Token usage is tracked via JSONL session files that Claude Code writes natively — no API instrumentation needed; the data already exists on disk _(avoids coupling to any particular API response shape; works with any model or agent type)_
- Deduplication uses a composite key (`message.id:requestId`) with per-field max to handle duplicate entries in JSONL — this prevents double-counting when the same request appears multiple times in session logs _(JSONL files can contain retries and replays; naive summation inflates costs significantly)_
- `usage.md` is scoped to a plan lifecycle — cleared by `/pace:plan`, preserved through `/pace:complete` _(usage data is most meaningful at plan granularity; preserving through complete allows post-hoc review and PR embedding)_
- `usage.md` is explicitly excluded from the cleanup list in `/pace:complete` _(it belongs to the "persistent across complete" category alongside `settings.md`, but unlike settings it resets with each new plan)_
- Usage data is embedded in the PR body as a `## Token Usage` section via `/pace:create-pr` _(makes cost visible in the code review context where architectural trade-offs are discussed; omitted gracefully when file is absent)_
- Session UUID is captured once at command entry (via `find-session.sh`) and stored in STATE.md — subsequent commands read it from there rather than re-detecting _(session detection is heuristic-based; capturing once avoids drift if the JSONL landscape changes during a long execution)_

### Patterns
- Lib scripts (`token-usage.py`, `find-session.sh`, `append-usage.sh`) are installed to `~/.claude/lib/pace/` and invoked with full paths — consistent with how agents reference installed tooling
- Per-phase append model: each command appends its own phase heading and rows to `usage.md` rather than rewriting the file _(enables incremental accumulation across a multi-command lifecycle without any coordination between commands)_
- Usage recording is always conditional on `session_uuid` being present — commands degrade gracefully with no errors when session detection fails _(tracking is observability infrastructure, not correctness infrastructure; a missing UUID must never block task execution)_
- The aggregate-pipe-append pattern is uniform across all instrumented commands: `token-usage.py aggregate | append-usage.sh <phase> <task> <agent-type>` _(consistent shape makes the pattern easy to apply to new commands and easy to audit)_
- New cross-cutting observability concerns follow the same pipeline-wide threading pattern established by model override: capture once, thread everywhere, degrade gracefully when absent

### Lessons
- stdlib-only Python for tooling scripts avoids environment dependency issues — `token-usage.py` uses only stdlib modules, making it portable across any Python 3 installation without a venv or pip
- JSONL session files include subagent sessions as separate files in the same project directory — aggregation must collect both the main session and all subagent UUIDs to get accurate totals for delegated work
