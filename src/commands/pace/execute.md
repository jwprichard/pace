---
name: pace:execute
description: Reads PLAN.md, delegates each task to its assigned specialist agent one at a time, and tracks progress in STATE.md
allowed-tools:
  - Read
  - Edit
  - Bash
  - Agent
  - TaskCreate
  - TaskUpdate
---

<objective>
Execute the current plan by delegating each task to its assigned specialist agent,
one task at a time, in Implementation Order. Update STATE.md before and after each
task so progress is durable across sessions.

Mirror all task state into Claude's native task system so progress is visible
in the UI throughout execution.

You are a dispatcher. You do not implement, code, write, or design anything yourself.
Every task goes to a specialist agent via the Agent tool.
</objective>

<process>

> **Agent spawning rule:** Every `Agent` spawned in this command must use `dangerouslySkipPermissions: true`.
> This applies to all specialist agents and the documentation-specialist patch call.

## Stage 1 — Pre-flight

Read `.pace/PLAN.md`. If it does not exist, stop and tell the user to run `/pace:plan` first.

Read `.pace/STATE.md`. If it does not exist, stop and tell the user to run `/pace:plan`
and approve the plan first — STATE.md is created during plan approval.

Check `## Status` in STATE.md:
- If `complete` → tell the user the plan is already finished and suggest `/pace:verify`
- If `blocked` → tell the user a task is blocked, show the blocker from `## Blockers`,
  and ask whether they want to retry or skip

### Session UUID and project path (for token usage)

Re-detect the current session UUID by running:

```bash
bash ~/.claude/lib/pace/find-session.sh
```

Store the output as `session_uuid`. If the command fails or returns empty,
set `session_uuid = null` and log a warning:
```
Warning: Could not detect session UUID — token usage recording will be skipped.
```

If `session_uuid` is non-null, read the `_Session: {uuid}_` line from STATE.md.
If the stored UUID differs from the detected one, update STATE.md's `_Session:` line
to reflect the current session:
- Edit the line `_Session: {old_uuid}_` → `_Session: {session_uuid}_`

Derive the encoded project path (replace every `/` and `.` with `-`):
```bash
printf '%s\n' "${PWD//[\/.]/-}"
```
Store the output as `encoded_project_path`.

All token usage recording steps later in this command are conditional on
`session_uuid` being non-null. If `session_uuid` is null, skip every usage-recording
bash command silently.

### Staleness check

If `.pace/PROJECT.md` exists:
- Read the `_Commit:_` line to get the stored hash
- Run: `git rev-parse --short HEAD`
- If the hashes differ → warn the user:
  ```
  Warning: PROJECT.md is out of date (stored: {stored hash}, current: {current hash}).
  Agents will use stale codebase context. Consider running /pace:scan to refresh.
  ```
  Then continue — this is a warning, not a blocker.

### Semantic memory

If `.pace/memory/semantic.md` exists, read it. This gives the dispatcher
institutional context — cross-plan decisions and patterns — when building agent prompts.

### Model override

If `.pace/settings.md` exists, read it and look for an `execute-model:` line in the
`## Model` section. If the line has a non-empty value (e.g. `execute-model: sonnet`),
store that value as the **model override** for all specialist agent spawns during
this execution.

If the file does not exist, the `execute-model:` line is missing, or its value is
blank (e.g. `execute-model:` with nothing after it), no model override is used —
agents will inherit the session model as normal.

The dispatcher's own model is never changed by this setting.

> **How to pass the model override:** `model` is a top-level parameter on the Agent tool,
> not text inside the prompt. Correct usage:
> `Agent(description: "...", prompt: "...", model: "{model_value}")`

## Stage 2 — Load Tasks and Build the Run Order

Parse all tasks from the `## Tasks` section of STATE.md. Task IDs use the
part-prefixed alphanumeric scheme (e.g. `1a`, `1b`, `2a`):

```
- [ ] 1a: {title} — @{agent}     ← pending
- [~] 1a: {title} — @{agent}     ← in_progress (resume: treat as pending)
- [x] 1a: {title} — @{agent}     ← completed (skip)
- [!] 1a: {title} — @{agent}     ← blocked (stop — surface to user)
```

Read the `## Implementation Order` section of PLAN.md. The run order is the
Implementation Order, minus tasks already `[x]` in STATE.md. Tasks marked `[~]`
are treated as pending and keep their position. If a task appears in STATE.md
but not in the Implementation Order (or vice versa), warn the user and fall
back to STATE.md's top-to-bottom order.

Tasks run **one at a time, in this order**. There is no parallel execution —
each task completes (and is committed) before the next starts.

If all tasks are already `[x]`, go to Stage 4 (complete).

Tell the user the run order: which tasks will run, in what order, and which
tasks are being skipped as already done.

### Register tasks in Claude's task system

For every task that will run (not already `[x]`), call TaskCreate with:
- `subject`: `Task {id}: {title} — @{agent}`
- `description`: the task description from PLAN.md

Store the returned Claude task ID mapped to the PACE task ID — you will need
these IDs to update status throughout execution.

For tasks already `[x]` (completed in a prior session), call TaskCreate then
immediately TaskUpdate to `completed` so the full plan is visible in the UI.

## Stage 3 — Execute Tasks Sequentially

For each task in the run order, perform steps 3a–3d, then move to the next task.
Do not start a task until the previous task's outcome is fully recorded.

### 3a — Mark the task in_progress

Edit STATE.md: change the task's marker from `[ ]` or `[~]` to `[~]`.
Call TaskUpdate for the task: set status to `in_progress`.

### 3b — Spawn the specialist agent

Build the task's context from PLAN.md. Find the task's block by matching the
heading `### {id}. {title}` (e.g. `### 1a. Flyway migration`). Extract:
- The full narrative description (everything between the metadata fields and the success criteria)
- `**Files:**` — files likely to be affected
- `**Agent:**` — the assigned specialist
- `**Allowed tools:**` — tools this task is permitted to use
- `**Success criteria:**` — the observable outcomes

If `.pace/PROJECT.md` exists, read the `## Stack` and `## Structure` sections
to prepend as codebase context in the agent's prompt.

Spawn the assigned specialist as a single Agent tool call using this prompt
(substitute all `{...}` placeholders).

If a **model override** was read in Stage 1, set the `model` parameter to `{model_value}` on
the Agent tool call. When no model override is set, omit the `model` parameter
entirely so the agent inherits the session default:

---
You are executing **Task {id}: {title}** as part of a PACE plan.

## Rules
- Before modifying any file — Write, Edit, or NotebookEdit — you must Read it
  first. Never modify a file you have not read in this session.
- Treat Files Likely Affected as your working boundary. You may read any file
  for context, but only modify files within that list. If you genuinely need
  to modify a file outside the list, note it in your completion summary — do
  not silently expand scope.
- Do not implement work outside your assignment.
- Do not run any `git` commands — no `git add`, `git commit`, or `git push`.
  The dispatcher handles all commits.
- When done, confirm each success criterion is met.
- Your completion summary MUST end with a `## Files Modified` section listing
  every file you created, modified, or deleted. One file path per line. Example:
  ```
  ## Files Modified
  src/new-file.ts
  src/existing-file.ts
  src/removed-file.ts
  ```

## Allowed Tools
Read, Write, Edit, NotebookEdit, Bash, Glob, Grep, WebSearch, WebFetch
{If PLAN.md specifies a restricted Allowed tools field for this task: "Note: this task is restricted to: {list}"}

## Codebase Context

{full contents of .pace/PROJECT.md, or "Not available — run /pace:scan to generate."}

## Episodic Memory

{contents of .pace/memory/episode.md, or "No tasks completed yet in this execution."}

## Your Assignment

{full task narrative description from PLAN.md — include the complete narrative text
between the metadata fields and the success criteria}

## Files Likely Affected

{files from PLAN.md, or "not specified"}

## Success Criteria

{success criteria from PLAN.md}
---

Wait for the task to complete before proceeding.

### 3c — Commit the task's changes

**On success:**

1. Parse the `## Files Modified` section from the agent's completion summary.
   Extract all file paths listed.
2. Stage the files:
   ```bash
   git add {file1} {file2} ...
   ```
   Quote any paths containing spaces. If a listed file does not exist on disk
   (the agent deleted it), `git add` still stages the deletion correctly.
3. Check if there are staged changes:
   ```bash
   git diff --cached --quiet
   ```
   - If there are staged changes (exit code 1), commit:
     ```bash
     git commit -m "{task title}"
     ```
   - If there are no staged changes (exit code 0), skip the commit — the agent
     may have made no effective changes.

If the agent did not include a `## Files Modified` section, fall back to:
```bash
git add -A
git diff --cached --quiet || git commit -m "{task title}"
```
This is a safety net — agents should always report their files.

### 3d — Record the outcome

**On success:** Edit STATE.md — change `[~]` to `[x]`. Move the task line into
`## Completed` with a timestamp:

```
- [x] {id}: {title} — @{agent} _(completed {ISO timestamp})_
```

Call TaskUpdate for this task: set status to `completed`.

Append the specialist's completion summary to `.pace/memory/episode.md`.
If the file does not exist, create `.pace/memory/` and create the file with this header first:

```markdown
# Episodic Memory
_Plan: {plan title from STATE.md}_

```

Then append:

```markdown
## Task {id}: {title} (@{agent})
_Completed: {ISO timestamp}_

{completion summary returned by the specialist}

---
```

**Record token usage for this task (if `session_uuid` is non-null):**

Run the following bash commands. When a **model override** was read in Stage 1, pass it
as the 5th argument to `append-usage.sh`. When no model override is set, omit the 5th
argument entirely:

```bash
# With model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} \
  | bash ~/.claude/lib/pace/append-usage.sh execute {id} {agent} "" {model_value}

# Without model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} \
  | bash ~/.claude/lib/pace/append-usage.sh execute {id} {agent}
```

Where `{id}` is the task ID (e.g. `1a`) and `{agent}` is the agent type from the task line
in STATE.md. If the command fails, continue without interrupting the user — token
recording is non-blocking.

Then move to the next task in the run order (back to 3a).

**On failure:** Edit STATE.md — change `[~]` to `[!]`. Record the error in
`## Blockers`:

```
## Blockers
Task {id} ({title}): {brief description of what went wrong}
```

Call TaskUpdate for this task: set subject to `[BLOCKED] Task {id}: {title}`,
status to `completed` (Claude tasks have no blocked state).

Then update `## Status` to `blocked`, stop execution (do not start the next task),
and tell the user:
- Which task failed and why
- What they can do to resolve it (fix the issue, then run `/pace:resume`)

## Stage 4 — Complete

When all tasks are `[x]`:

### Patch PROJECT.md

Spawn `pace-documentation-specialist` using the Agent tool in patch mode, once for
the whole execution. If a **model override** was read in Stage 1, set the `model`
parameter to `{model_value}` on this Agent tool call. When no model override is set,
omit the `model` parameter entirely:

```
Patch mode. A plan execution just completed.
Plan: {plan title from STATE.md}
Execution log:

{full contents of .pace/memory/episode.md}

Update .pace/PROJECT.md to reflect the changes introduced by this execution.
```

Wait for it to complete. (If PROJECT.md does not exist, the specialist will skip silently.)

**Record token usage for the documentation patch (if `session_uuid` is non-null):**

When a **model override** was read in Stage 1, pass it as the 5th argument to
`append-usage.sh`. When no model override is set, omit the 5th argument entirely:

```bash
# With model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} \
  | bash ~/.claude/lib/pace/append-usage.sh execute doc-patch pace-documentation-specialist "" {model_value}

# Without model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} \
  | bash ~/.claude/lib/pace/append-usage.sh execute doc-patch pace-documentation-specialist
```

If the command fails, continue without interrupting the user — token recording is non-blocking.

### Finalise state

Edit STATE.md — update `## Status` to `complete`.

**Record execute dispatcher token usage (if `session_uuid` is non-null):**

Run the following bash commands:

```bash
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} \
  | bash ~/.claude/lib/pace/append-usage.sh execute orchestrator execute-orchestrator
```

If the command fails, continue without interrupting the user — token recording is non-blocking.

Tell the user:

```
All tasks complete. Run `/pace:verify` to check the work against the success criteria.
```

</process>
