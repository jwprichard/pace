## What
Fix the token usage tracking pipeline so the model recorded in `.pace/usage.md` reflects the actual model override from `.pace/settings.md`, not the parent session model. Currently, when `execute-model: sonnet` is set, all usage rows still show `opus`.

## Success criteria
- When `execute-model: sonnet` is set in `.pace/settings.md`, execute-phase usage rows in `.pace/usage.md` display `sonnet` as the model, not `opus`
- When `plan-model: opus` is set, plan-phase usage rows display `opus`
- When no model override is set, usage rows display the actual session model (current behaviour preserved)
- The fix is forward-only — no backfill or migration of existing usage data

## Domain
Backend tooling (Python + Bash scripts)

## Constraints
- Fix is scoped to the recording/tracking pipeline: `token-usage.py`, `append-usage.sh`, and the command files that call them
- Do not change how `.pace/settings.md` is read or how the Agent tool's `model` parameter is passed
- The three lib files live at `src/lib/token-usage.py`, `src/lib/find-session.sh`, `src/lib/append-usage.sh`
- Commands that record usage live at `src/commands/pace/` (plan.md, execute.md, verify.md, fix.md, amend.md, complete.md)
- The bug likely originates from `token-usage.py aggregate` reading model from JSONL log fields that reflect the session model rather than the agent-level override, or from `append-usage.sh` not receiving/writing the correct model value

## Scope
Small — investigate the full tracking pipeline (JSONL logs → aggregate → append → usage.md) and fix where the model value goes wrong

## Assumptions
- The Agent tool's `model` parameter works correctly (agents actually run on the overridden model)
- The JSONL logs written by Claude Code may record the parent session's model rather than the agent's overridden model — this is the most likely root cause
- If the JSONL logs don't contain the override model, the fix will need to pass the model value explicitly from the calling command context

## Investigation Findings

CONFIRMED: Subagent JSONL records the overridden model (e.g. `claude-sonnet-4-6`). The override approach in Tasks 2-3 is the correct fix.

**Evidence:**
- Orchestrator session `61a8210c-434b-4de1-b6c1-664d70416f66` spawned Task 1 agent (`agent-aeb901469a0769299`) with `model: "sonnet"` via the Agent tool.
- All `message.model` fields in that agent's JSONL are `claude-sonnet-4-6` (confirmed across 51 response entries).
- For contrast, the three planning agents (Backend Architect, Software Architect, pace-synthesiser) in session `7a47ede0-fb26-446b-8da0-06ad84773c0d` were spawned with `model: "opus"` (from `plan-model: opus` in settings.md) and all recorded `claude-opus-4-6` in their JSONL.

**Implication for Tasks 2-3:**
Since `message.model` in the subagent JSONL correctly reflects the overridden model, `token-usage.py aggregate` _can_ read the correct model from the log — the value is present. The bug is therefore in how `append-usage.sh` or the calling commands derive/pass the model value, not in the JSONL content itself. Tasks 2-3 should pass the model override explicitly from the command context to `append-usage.sh` and write it to `usage.md`, rather than relying on aggregation from JSONL.
