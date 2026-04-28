---
name: pace:fix
description: Dispatches targeted fixes within the PACE lifecycle — structured by default, --light for quick one-shot fixes
argument-hint: "[--light] [description]"
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash
  - Glob
  - Grep
  - Task
  - AskUserQuestion
---

<objective>
Apply targeted fixes to work completed under the current plan. Fixes are
small adjustments or bugs that surface after execution or verification —
things that don't warrant a new plan cycle.

Default mode is structured: interview, append fix tasks to PLAN.md, dispatch
agents, track in STATE.md, route to verify.

Light mode (`--light`) is a one-shot dispatch: auto-select an agent, send it
with full plan context, patch PROJECT.md, done. No plan modification, no
state tracking.

You are an orchestrator. You do not implement, code, write, or design anything
yourself. Every fix goes to a specialist agent via the Task tool.
</objective>

<process>

> **Task spawning rule:** Every `Task` spawned in this command must use `dangerouslySkipPermissions: true`.

## Stage 0 — Parse Flags

Read the full argument string. Detect flags independently:

- If the argument contains `--light`: set `light_mode = true`, strip `--light` from the string
- The remaining string after stripping is the user's fix description

---

## LIGHT MODE

If `light_mode = true`, follow this section and skip the rest of the process.

### L1 — Pre-flight

Check whether `.pace/PROJECT.md` exists. If not, warn:
```
Warning: .pace/PROJECT.md not found. The agent will run without codebase context.
Consider running /pace:scan first for better results.
```

### L2 — Load context

Read the following files if they exist:
- `.pace/PROJECT.md` — codebase context
- `.pace/PLAN.md` — current plan (gives the agent awareness of what was built)
- `.pace/memory/episode.md` — what was built in this execution
- `.pace/VERIFICATION.md` — verification findings (if the fix relates to these)

### L3 — Parse the description

If the user provided a description in the argument, use it.

If no description was provided, ask:
```
What needs fixing?
```
Then use their answer as the description.

### L4 — Auto-select agent

Read `.pace/AGENT-REGISTRY.md`. Based on the fix description, select the most
appropriate specialist agent:

- If the fix mentions frontend, UI, CSS, components → load the relevant Tier 2
  division file and select the best frontend agent
- If the fix mentions backend, API, database, server → select the best backend agent
- If the fix mentions tests, specs, coverage → select the best testing agent
- If the fix mentions docs, README, comments → select a documentation agent
- If unclear → default to `@Senior Developer` as a generalist

Load the relevant Tier 2 division file from `.pace/agents/` to confirm the
exact agent name before spawning.

Tell the user which agent you selected and why.

### L5 — Find relevant files

Grep for terms from the fix description in the codebase to surface relevant files.
Use 2–4 targeted searches based on keywords. Collect up to 10 most relevant
file paths and their matching lines.

### L6 — Dispatch

Spawn the selected agent as a Task with `dangerouslySkipPermissions: true`
and this prompt (substitute all `{...}` placeholders):

---
You are applying a targeted fix as @{agent name}.

## Codebase Context

{full contents of .pace/PROJECT.md, or "Not available."}

## Current Plan Context

{summary of PLAN.md objective and completed tasks, or "No plan context available."}

## Episodic Memory

{contents of .pace/memory/episode.md, or "Not available."}

## Verification Findings

{contents of .pace/VERIFICATION.md, or "No verification findings available."}

## Relevant Files

{grep results and file paths from L5, or "No relevant files pre-identified."}

## What Needs Fixing

{user's fix description}

## Rules
- Before modifying any file — Write, Edit, or NotebookEdit — you must Read it
  first. Never modify a file you have not read in this session.
- Fix only what is described. Do not refactor or improve unrelated code.
- When done, confirm what you changed and which files you touched.
---

Wait for the task to complete.

### L7 — Patch documentation

Spawn `pace-documentation-specialist` as a Task in patch mode:

---
Patch mode. Fix just completed.
Task: {fix description}
Agent: {agent name}
Summary: {specialist's completion summary}
Update .pace/PROJECT.md to reflect any changes introduced by this fix.
---

Wait for the documentation task to complete.

### L8 — Report

Tell the user:
```
Done. @{agent name} applied the fix.
PROJECT.md updated.

Summary: {specialist's one-line completion summary}

Run /pace:verify to re-check the plan criteria, or /pace:fix for more fixes.
```

**End of light mode. Stop here.**

---

## DEFAULT MODE (structured)

If `light_mode = false`, follow this section.

### Stage 1 — Pre-flight

Read `.pace/STATE.md`. If it does not exist, stop:
```
No STATE.md found. Run /pace:plan first to create a plan.
```

Read `.pace/PLAN.md`. If it does not exist, stop:
```
No PLAN.md found. Cannot append fixes without a plan.
```

Check `## Status` in STATE.md:
- `complete` → normal post-verify flow, proceed
- `in_progress` → warn: "Some tasks are still in progress. You can still queue fixes — they'll be appended after the existing tasks." Then proceed.
- `blocked` → warn: "The plan is blocked. Fixes will be appended but won't resolve the blocker. Consider fixing the blocker first." Then proceed.

### Stage 2 — Load context

Read the following files:
- `.pace/PROJECT.md` — codebase context (warn if missing, continue without)
- `.pace/AGENT-REGISTRY.md` — agent registry (stop if missing: "Run /pace:sync-agents first.")
- `.pace/memory/episode.md` — episodic memory (optional)
- `.pace/memory/semantic.md` — semantic memory (optional)
- `.pace/VERIFICATION.md` — verification findings (optional)

### Stage 3 — Interview

If `.pace/VERIFICATION.md` exists, show a brief summary of the failing criteria
to the user before asking questions — these may be what they want to fix.

If the user provided a description in the argument, use it as the starting point.
State your understanding:

```
I understand you want to fix: {summary of described issues}
```

If no description was provided, ask:
```
What needs fixing? Describe each issue briefly — I'll turn them into fix tasks.
```

Then ask one follow-up using AskUserQuestion:

```
question: "Anything else to fix, or is that everything?"
header: "Fix scope"
options:
  - label: "That's everything"
    description: "Proceed with the fixes described above."
  - label: "One more thing..."
    description: "I have another fix to add."
```

If they choose "One more thing...", ask for the additional description, then
ask the same follow-up again. Repeat until they confirm "That's everything."

### Stage 4 — Build fix tasks

For each fix the user described:

1. Determine the appropriate agent from the registry (same logic as L4 in light mode,
   but load the relevant Tier 2 files to confirm)
2. Determine which files are likely affected (grep the codebase for relevant terms)
3. Write observable success criteria — what must be true after the fix

Determine the next fix number. Read PLAN.md — if a `## Fixes` section already
exists, continue numbering from the last fix. Otherwise start at Fix 1.

Append to `.pace/PLAN.md`:

If no `## Fixes` section exists yet, add it after the `## Notes` section (or at
the end of the file if no Notes section):

```markdown

## Fixes

### Fix {N}: {short title}
**Agent:** @{agent-name}
**Depends on:** none
**Files:** {comma-separated file paths, or "TBD"}
**Success criteria:**
- {observable outcome 1}
- {observable outcome 2}
```

For each additional fix, append another `### Fix {N+1}:` block.

### Stage 5 — Update STATE.md

Edit `.pace/STATE.md`:

1. Set `## Status` to `in_progress`
2. Add fix tasks to `## Tasks`:

```
- [ ] F{N}: {title} — @{agent}
```

Present the fix tasks to the user:

```
Fix tasks added to the plan:

- F{N}: {title} — @{agent}
- F{N+1}: {title} — @{agent}

Dispatching now...
```

### Stage 6 — Dispatch fix agents

For each fix task, spawn the assigned agent as a parallel Task with
`dangerouslySkipPermissions: true` and this prompt (substitute all placeholders):

---
You are applying **Fix {N}: {title}** as part of a PACE plan.

## Rules
- Before modifying any file — Write, Edit, or NotebookEdit — you must Read it
  first. Never modify a file you have not read in this session.
- Fix only what is described. Do not refactor or improve unrelated code.
- When done, confirm each success criterion is met.

## Codebase Context

{full contents of .pace/PROJECT.md, or "Not available."}

## Episodic Memory

{contents of .pace/memory/episode.md, or "No tasks completed yet in this execution."}

## What Needs Fixing

{fix description from the user}

## Files Likely Affected

{files from PLAN.md fix block, or "not specified"}

## Success Criteria

{success criteria from PLAN.md fix block}
---

Wait for all fix agents to complete.

### Stage 7 — Record outcomes

For each fix task:

**On success:** Edit STATE.md — change `[ ]` to `[x]`. Move the task line into
`## Completed` with a timestamp:

```
- [x] F{N}: {title} — @{agent} _(completed {ISO timestamp})_
```

Append the specialist's completion summary to `.pace/memory/episode.md`.
If the file does not exist, create `.pace/memory/` and create the file first.

Then append:

```markdown
## Fix {N}: {title} (@{agent})
_Completed: {ISO timestamp}_

{completion summary returned by the specialist}

---
```

Spawn `pace-documentation-specialist` as a fire-and-forget Task in patch mode:

```
Patch mode. Fix just completed.
Task: Fix {N} — {title}
Agent: {agent}
Files: {files from PLAN.md}
Summary: {completion summary returned by the specialist}
Update .pace/PROJECT.md to reflect any changes introduced by this fix.
```

**On failure:** Edit STATE.md — change `[ ]` to `[!]`. Record the error in
`## Blockers`:

```
Fix {N} ({title}): {brief description of what went wrong}
```

Set `## Status` to `blocked` and tell the user which fix failed and why.

### Stage 8 — Complete

When all fix tasks are `[x]`:

Edit STATE.md — update `## Status` to `complete`.

Tell the user:

```
All fixes applied.

Run /pace:verify to re-check the plan criteria.
Or /pace:fix to apply more fixes.
```

</process>
