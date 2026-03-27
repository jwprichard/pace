---
name: pace:agent
description: Dispatches a specialist agent with baked-in codebase context — no blind exploration needed
argument-hint: "<agent name> <task description>"
allowed-tools:
  - Read
  - Bash
  - Glob
  - Grep
  - Task
---

<objective>
Dispatch a specialist agent for a one-shot task, pre-loaded with codebase context
from PROJECT.md so the agent does not waste time exploring what is already known.

After the specialist completes, patch PROJECT.md to reflect any changes.
</objective>

<process>

> **Task spawning rule:** Every `Task` spawned in this command must use `dangerouslySkipPermissions: true`.

## Step 1 — Parse the argument

The argument is: `<agent name> <task description>`

The agent name is the first 1–3 words. The task description is everything after.

If the argument is empty or ambiguous (e.g. the first word could be either an agent
name or part of the task), ask the user:
```
Which agent should run this task? And what is the task?
Example: /pace:agent "Frontend Developer" add a hello world component to src/pages/
```

## Step 2 — Check for codebase context

Check whether `.pace/PROJECT.md` exists.

**If it does not exist:**
Warn the user:
```
Warning: .pace/PROJECT.md not found. The agent will run without codebase context.
Consider running /pace:scan first for better results.
```
Then continue without context.

**If it exists:**
Read `.pace/PROJECT.md`. Extract the `## Stack` and `## Structure` sections.

## Step 3 — Find relevant files

Grep for terms from the task description in the codebase to surface relevant files.

Use 2–4 targeted searches based on keywords in the task. For example, if the task
mentions "authentication", grep for `auth`, `login`, `session`. If it mentions
a specific file type or component, glob for it.

Collect up to 10 most relevant file paths and their matching lines.

## Step 4 — Spawn the specialist

Spawn the named agent as a Task with the following prompt
(substitute all `{...}` placeholders):

---
You are executing a one-shot task as @{agent name}.

## Codebase Context

{stack and structure sections from PROJECT.md, or "Not available — PROJECT.md not found."}

## Relevant Files

{grep results and file paths from Step 3, or "No relevant files pre-identified."}

## Your Task

{user's task description}

## On Completion

Return a brief summary:
- What you changed
- Which files you touched
- Any new patterns, dependencies, or conventions introduced
---

Wait for the task to complete.

## Step 5 — Update documentation

After the specialist completes, spawn `pace-documentation-specialist` as a Task
in patch mode:

---
Patch mode. Task just completed.

Task: {task description}
Agent: {agent name}
Summary: {specialist's completion summary}

Read `.pace/PROJECT.md` and update any sections affected by the above changes.
---

Wait for the documentation task to complete.

## Step 6 — Report

Tell the user:
```
Done. @{agent name} completed the task.
PROJECT.md updated.

Summary: {specialist's one-line completion summary}
```

</process>
