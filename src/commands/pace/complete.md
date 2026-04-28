---
name: pace:complete
description: Closes out a completed plan — full PROJECT.md refresh and .pace/ runtime cleanup
allowed-tools:
  - Read
  - Write
  - Bash
  - Task
---

<objective>
Close out a completed plan cleanly. Refresh the project map with a full rescan,
then delete runtime files that belong to this plan only.

Preserve the persistent .pace/ artifacts (PROJECT.md, AGENT-REGISTRY.md, agents/).
Delete only the plan-specific runtime files.
</objective>

<process>

> **Task spawning rule:** Every `Task` spawned in this command must use `dangerouslySkipPermissions: true`.

## Step 1 — Pre-flight

Read `.pace/STATE.md`. If it does not exist, stop:
```
No STATE.md found. There is nothing to close out.
```

Check `## Status` in STATE.md. If it is not `complete`, stop:
```
The plan is not yet complete (status: {status}).
Finish execution first, then run /pace:complete.
Run /pace:execute to continue, or /pace:resume to pick up from where you left off.
```

## Step 2 — Synthesise episodic memory into semantic memory

If `.pace/memory/episode.md` does not exist, skip this step.

Read `.pace/memory/episode.md`.
Read `.pace/memory/semantic.md` if it exists (may be absent on first completion).

Spawn a Task with `dangerouslySkipPermissions: true` and this prompt:

---
You are synthesising episodic memory into long-term semantic memory for a PACE project.

## Episodic Memory (this plan's execution log)

{full contents of .pace/memory/episode.md}

## Existing Semantic Memory

{full contents of .pace/memory/semantic.md, or "Empty — this is the first completion."}

## Your Task

Extract from the episodic memory anything worth remembering long-term:
- Architectural decisions that were made and why
- Patterns or conventions that were introduced or confirmed
- Lessons learned or problems encountered
- Dependencies or integrations added

Do NOT include:
- Task-specific implementation details (what line of code was changed)
- Ephemeral state (file was created, then deleted)
- Anything already present in the existing semantic memory

Append your findings to `.pace/memory/semantic.md` using this format:

```markdown
## {Plan title} — {ISO date}

### Decisions
- {decision} _(rationale)_

### Patterns
- {pattern}

### Lessons
- {lesson}
```

If there is nothing worth adding, write nothing — do not append empty sections.

Allowed tools: Read, Write
---

Wait for the task to complete.

## Step 3 — Refresh PROJECT.md

Spawn `pace-documentation-specialist` as a Task in full mode:

---
Full mode. The current plan has just completed.

Run a fresh codebase scan and rewrite `.pace/PROJECT.md` entirely.
Capture the current commit hash and timestamp.
---

Wait for the task to complete.

## Step 4 — Clean up runtime files

Delete the plan-specific runtime files:

```bash
rm -f .pace/PLAN.md
rm -f .pace/STATE.md
rm -f .pace/memory/episode.md
rm -rf .pace/requirements/
rm -rf .pace/drafts/
```

Do NOT delete:
- `.pace/PROJECT.md` — preserve (just refreshed)
- `.pace/AGENT-REGISTRY.md` — preserve (registry is persistent)
- `.pace/agents/` — preserve (registry tier 2 files)
- `.pace/memory/semantic.md` — preserve (persistent cross-plan knowledge)

## Step 5 — Confirm

Tell the user:

```
Plan closed.

Episodic memory synthesised into semantic memory.
PROJECT.md refreshed with latest codebase state.
Runtime files cleaned up (PLAN.md, STATE.md, episode.md, requirements/, drafts/).

Ready for the next plan. Run /pace:plan to start.
```

</process>
