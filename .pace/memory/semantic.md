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
