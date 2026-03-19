---
name: pace:execute
description: Reads PLAN.md, delegates each task to the assigned specialist agent, and tracks progress in STATE.md
allowed-tools:
  - Read
  - Edit
  - Task
  - TaskCreate
  - TaskUpdate
---

<objective>
Execute the current plan by delegating each task to its assigned specialist agent.
Run independent tasks in parallel. Update STATE.md before and after each task so
progress is durable across sessions.

Mirror all task state into Claude's native task system so progress is visible
in the UI throughout execution.

You are an orchestrator. You do not implement, code, write, or design anything yourself.
Every task goes to a specialist agent via the Task tool.
</objective>

<process>

## Stage 1 — Pre-flight

Read `.pace/PLAN.md`. If it does not exist, stop and tell the user to run `/pace:plan` first.

Read `.pace/STATE.md`. If it does not exist, stop and tell the user to run `/pace:plan`
and approve the plan first — STATE.md is created during plan approval.

Check `## Status` in STATE.md:
- If `complete` → tell the user the plan is already finished and suggest `/pace:verify`
- If `blocked` → tell the user a task is blocked, show the blocker from `## Blockers`,
  and ask whether they want to retry or skip

## Stage 2 — Load Tasks and Build Waves

Parse all tasks from the `## Tasks` section of STATE.md:

```
- [ ] 1: {title} — @{agent}     ← pending
- [~] 1: {title} — @{agent}     ← in_progress (resume: treat as pending)
- [x] 1: {title} — @{agent}     ← completed (skip)
- [!] 1: {title} — @{agent}     ← blocked (stop — surface to user)
```

For each pending or in_progress task, read its block from PLAN.md to get the
`**Depends on:**` field.

Build an execution plan using wave scheduling:
- **Wave 1** — tasks with `Depends on: none` (or no dependencies)
- **Wave N** — tasks whose dependencies are all completed or in a prior wave

Example: tasks 1, 2, 3 where 3 depends on 1:
- Wave 1: tasks 1 and 2 (run in parallel)
- Wave 2: task 3

If all tasks are already `[x]`, go to Stage 4 (complete).

Tell the user the execution plan: how many waves, which tasks run in each wave,
which tasks are being skipped as already done.

### Register tasks in Claude's task system

For every task that will run (not already `[x]`), call TaskCreate with:
- `subject`: `Task {number}: {title} — @{agent}`
- `description`: the task description from PLAN.md

Store the returned Claude task ID mapped to the PACE task number — you will need
these IDs to update status throughout execution.

For tasks already `[x]` (completed in a prior session), call TaskCreate then
immediately TaskUpdate to `completed` so the full plan is visible in the UI.

## Stage 3 — Execute Waves

For each wave, in order:

### 3a — Mark all wave tasks in_progress

Edit STATE.md: change each task's marker from `[ ]` or `[~]` to `[~]`.
Call TaskUpdate for each wave task: set status to `in_progress`.
Do this for all tasks in the wave before spawning any agents.

### 3b — Spawn all wave agents in parallel

For each task in the wave, build its context from PLAN.md:
- Task title and description
- `**Files:**` — files likely to be affected
- `**Agent:**` — the assigned specialist
- `**Allowed tools:**` — tools this task is permitted to use
- `**Success criteria:**` — the observable outcomes

Spawn all tasks in the wave as **simultaneous parallel Task calls** using this
prompt for each (substitute all `{...}` placeholders):

---
You are executing **Task {number}: {title}** as part of a PACE plan.

## Allowed Tools

{allowed tools from PLAN.md}

## Your Assignment

{task description from PLAN.md}

## Files Likely Affected

{files from PLAN.md, or "not specified"}

## Success Criteria

{success criteria from PLAN.md}

## Context

Previously completed tasks in this plan:
{list of completed task titles, or "none — this is the first task"}

Do not implement work outside your assignment. Focus only on the task above.
Only use the tools listed above. When done, confirm each success criterion is met.
---

Wait for **all** tasks in the wave to complete before proceeding to the next wave.

### 3c — Record wave outcomes

For each task in the wave:

**On success:** Edit STATE.md — change `[~]` to `[x]`. Move the task line into
`## Completed` with a timestamp:

```
- [x] {number}: {title} — @{agent} _(completed {ISO timestamp})_
```

Call TaskUpdate for this task: set status to `completed`.

**On failure:** Edit STATE.md — change `[~]` to `[!]`. Record the error in
`## Blockers`:

```
## Blockers
Task {number} ({title}): {brief description of what went wrong}
```

Call TaskUpdate for this task: set subject to `[BLOCKED] Task {number}: {title}`,
status to `completed` (Claude tasks have no blocked state).

Then update `## Status` to `blocked`, stop execution (do not start the next wave),
and tell the user:
- Which task failed and why
- What they can do to resolve it (fix the issue, then run `/pace:resume`)

If multiple tasks in the same wave fail, record all blockers before stopping.

## Stage 4 — Complete

When all tasks are `[x]`:

Edit STATE.md — update `## Status` to `complete`.

Tell the user:

```
All tasks complete. Run `/pace:verify` to check the work against the success criteria.
```

</process>
