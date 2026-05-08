---
name: pace:amend
description: Adds new tasks to the current plan mid-execution — structured by default, --light for quick one-shot additions
argument-hint: "[--light] [description]"
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
---

<objective>
Add new tasks to a plan that is already in progress. Amendments are extra scope
that belongs with the current plan — things the user forgot, discovered mid-build,
or wants to bolt on without completing and re-planning.

Default mode is structured: interview, assess scope, append tasks to PLAN.md,
dispatch agents, track in STATE.md, route to verify.

Light mode (`--light`) is a one-shot dispatch: auto-select an agent, send it
with full plan context, append a minimal record to PLAN.md and STATE.md, patch
PROJECT.md, done.

Before accepting any amendment, assess whether the request is too large to bolt
onto the existing plan. If it is, recommend a separate plan instead.

You are an orchestrator. You do not implement, code, write, or design anything
yourself. Every task goes to a specialist agent via the Agent tool.
</objective>

<process>

> **Agent spawning rule:** Every `Agent` spawned in this command must use `dangerouslySkipPermissions: true`.

## Stage 0 — Parse Flags

Read the full argument string. Detect flags independently:

- If the argument contains `--light`: set `light_mode = true`, strip `--light` from the string
- The remaining string after stripping is the user's amendment description

### Model override

If `.pace/settings.md` exists, read it and look for an `execute-model:` line in the
`## Model` section. If the line has a non-empty value (e.g. `execute-model: sonnet`),
store that value as the **model override** for all specialist agent spawns during
this command.

If the file does not exist, the `execute-model:` line is missing, or its value is
blank (e.g. `execute-model:` with nothing after it), no model override is used —
agents will inherit the session model as normal.

The orchestrator's own model is never changed by this setting.

> **How to pass the model override:** `model` is a top-level parameter on the Agent tool,
> not text inside the prompt. Correct usage:
> `Agent(description: "...", prompt: "...", model: "{model_value}")`

### Session UUID

Read `.pace/STATE.md` (if it exists) and extract the `_Session: {uuid}_` line. Store
the UUID value as `session_uuid`. Also derive the encoded project path:

```bash
printf '%s\n' "${PWD//[\/.]/-}"
```

Store the output as `encoded_project_path`.

If STATE.md does not exist yet, or the `_Session:` line is missing, or the UUID is
empty, set `session_uuid = null`. Log a warning and skip all usage recording steps:
```
Warning: No session UUID found in STATE.md — token usage will not be recorded.
```

---

## Stage 1 — Pre-flight (both modes)

Read `.pace/STATE.md`. If it does not exist, stop:
```
No STATE.md found. Run /pace:plan first to create a plan.
```

Read `.pace/PLAN.md`. If it does not exist, stop:
```
No PLAN.md found. Cannot amend without a plan.
```

Check `## Status` in STATE.md:
- `complete` → stop: "This plan is already complete. Run `/pace:plan` to start a new one, or `/pace:fix` if something needs fixing."
- `blocked` → warn: "The plan is currently blocked. Amendments will be appended but won't resolve the blocker. Consider fixing the blocker first." Then proceed.
- `in_progress` → proceed normally

---

## Stage 2 — Scope check (both modes)

This stage runs for both light and default mode before any work begins.

Read PLAN.md to understand the existing plan's objective and task count.

If the user provided a description, assess the amendment against the existing plan:

**Ask yourself these questions:**
1. Does the amendment relate to the same feature/objective as the current plan?
2. Would it roughly double or more the existing plan's scope?
3. Does it introduce a new domain or concern not covered by the current plan?

**If the amendment is too large** (answers 2 or 3 are yes), recommend a separate plan:
```
This looks like it could be its own plan rather than an amendment.

The current plan is about: {plan objective summary}
Your request: {amendment summary}

This would be better as a separate /pace:plan because:
- {reason — e.g. "it introduces backend work into a frontend-only plan"}
- {reason — e.g. "it would roughly double the plan's scope"}

Want to proceed as an amendment anyway, or start a new plan for this?
```

Use AskUserQuestion:
```
question: "This request looks large enough to be its own plan. How would you like to proceed?"
header: "Scope check"
options:
  - label: "Amend anyway"
    description: "Add it to the current plan as extra tasks."
  - label: "New plan instead"
    description: "I'll finish this plan first, then plan that separately."
```

If they choose **"New plan instead"**, stop: "Got it. Finish the current plan with `/pace:execute` or `/pace:complete`, then run `/pace:plan` for the new work."

If they choose **"Amend anyway"** or the scope check passes (amendment is reasonable), continue.

---

## LIGHT MODE

If `light_mode = true`, follow this section and skip the rest of the process.

### L1 — Load context

Read the following files if they exist:
- `.pace/PROJECT.md` — codebase context
- `.pace/PLAN.md` — current plan
- `.pace/memory/episode.md` — what was built in this execution

If `.pace/PROJECT.md` does not exist, warn:
```
Warning: .pace/PROJECT.md not found. The agent will run without codebase context.
Consider running /pace:scan first for better results.
```

### L2 — Parse the description

If the user provided a description in the argument, use it.

If no description was provided, ask:
```
What do you want to add to the plan?
```
Then use their answer as the description.

### L3 — Auto-select agent

Read `.pace/AGENT-REGISTRY.md`. Based on the amendment description, select the most
appropriate specialist agent:

- If the amendment mentions frontend, UI, CSS, components → load the relevant Tier 2
  division file and select the best frontend agent
- If the amendment mentions backend, API, database, server → select the best backend agent
- If the amendment mentions tests, specs, coverage → select the best testing agent
- If the amendment mentions docs, README, comments → select a documentation agent
- If unclear → default to `@Senior Developer` as a generalist

Load the relevant Tier 2 division file from `.pace/agents/` to confirm the
exact agent name before spawning.

Tell the user which agent you selected and why.

### L4 — Find relevant files

Grep for terms from the amendment description in the codebase to surface relevant files.
Use 2–4 targeted searches based on keywords. Collect up to 10 most relevant
file paths and their matching lines.

### L5 — Determine task number

Read PLAN.md and STATE.md to find the highest existing task number (including any
fixes — e.g. if the last entry is Fix 3, the next number is 4; if the last task
is Task 6, the next number is 7). The amendment gets the next sequential number.

### L6 — Dispatch

Spawn the selected agent using the Agent tool with `dangerouslySkipPermissions: true`
and this prompt (substitute all `{...}` placeholders).

If a **model override** was read in Stage 0, set the `model` parameter to `{model_value}` on
the Agent tool call. When no model override is set, omit the `model` parameter
entirely so the agent inherits the session default:

---
You are adding new functionality as @{agent name}, as an amendment to an existing plan.

## Codebase Context

{full contents of .pace/PROJECT.md, or "Not available."}

## Current Plan Context

{summary of PLAN.md objective and completed/in-progress tasks}

## Episodic Memory

{contents of .pace/memory/episode.md, or "Not available."}

## Relevant Files

{grep results and file paths from L4, or "No relevant files pre-identified."}

## What To Add

{user's amendment description}

## Rules
- Before modifying any file — Write, Edit, or NotebookEdit — you must Read it
  first. Never modify a file you have not read in this session.
- Implement only what is described. Do not refactor or improve unrelated code.
- When done, confirm what you changed and which files you touched.
- Your completion summary MUST end with a `## Files Modified` section listing
  every file you created, modified, or deleted. One file path per line.
---

Wait for the task to complete.

### Record light mode amendment usage

If `session_uuid` is available, run the following. When a **model override** was read in
Stage 0, pass it as the 5th argument to `append-usage.sh`. When no model override is set,
omit the 5th argument entirely:

```bash
# With model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} | bash ~/.claude/lib/pace/append-usage.sh amend light {agent_type} "" {model_value}

# Without model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} | bash ~/.claude/lib/pace/append-usage.sh amend light {agent_type}
```

Where `{agent_type}` is the agent type selected in L3. If this command fails, continue
without interrupting the user — token recording is non-blocking.

### L7 — Commit changes

Parse the `## Files Modified` section from the agent's completion summary.
Stage and commit the files:

```bash
git add {file1} {file2} ...
git diff --cached --quiet || git commit -m "Amendment: {short description}"
```

If the agent did not include `## Files Modified`, fall back to:
```bash
git add -A
git diff --cached --quiet || git commit -m "Amendment: {short description}"
```

### L8 — Append to PLAN.md and STATE.md

Append a minimal record to PLAN.md. If no `## Amendments` section exists,
add it after the `## Fixes` section (or after `## Notes`, or at the end):

```markdown

## Amendments

### Amendment {N}: {short title}
**Agent:** @{agent-name}
**Files:** {files from agent summary}
**Status:** complete (light mode)
```

Edit STATE.md — add the amendment to `## Completed`:

```
- [x] A{N}: {title} — @{agent} _(completed {ISO timestamp})_
```

### L9 — Patch documentation

Spawn `pace-documentation-specialist` using the Agent tool in patch mode.
If a **model override** was read in Stage 0, set the `model` parameter to `{model_value}` on
this Agent tool call. When no model override is set, omit the `model` parameter
entirely:

---
Patch mode. Amendment just completed.
Task: {amendment description}
Agent: {agent name}
Summary: {specialist's completion summary}
Update .pace/PROJECT.md to reflect any changes introduced by this amendment.
---

Wait for the documentation task to complete.

### L10 — Report

Tell the user:
```
Done. @{agent name} added the amendment.
PROJECT.md updated.

Summary: {specialist's one-line completion summary}

Run /pace:verify to check the full plan criteria, or /pace:execute to continue with remaining tasks.
```

**End of light mode. Stop here.**

---

## DEFAULT MODE (structured)

If `light_mode = false`, follow this section.

### Stage 3 — Load context

Read the following files:
- `.pace/PROJECT.md` — codebase context (warn if missing, continue without)
- `.pace/AGENT-REGISTRY.md` — agent registry (stop if missing: "Run /pace:sync-agents first.")
- `.pace/memory/episode.md` — episodic memory (optional)
- `.pace/memory/semantic.md` — semantic memory (optional)

### Stage 4 — Interview

If the user provided a description in the argument, state your understanding:

```
I understand you want to add: {summary of described additions}

The current plan is: {plan objective from PLAN.md}
```

If no description was provided, ask:
```
What do you want to add to the current plan? Describe each addition briefly — I'll turn them into tasks.
```

Then ask one follow-up using AskUserQuestion:

```
question: "Anything else to add, or is that everything?"
header: "Amendment scope"
options:
  - label: "That's everything"
    description: "Proceed with the additions described above."
  - label: "One more thing..."
    description: "I have another addition."
```

If they choose "One more thing...", ask for the additional description, then
ask the same follow-up again. Repeat until they confirm "That's everything."

### Stage 5 — Build amendment tasks

Determine the next task number. Read PLAN.md — find the highest existing task
or fix number and continue from there.

For each addition the user described:

1. Determine the appropriate agent from the registry (same logic as L3 in light mode,
   but load the relevant Tier 2 files to confirm)
2. Determine which files are likely affected (grep the codebase for relevant terms)
3. Check for dependencies — does this amendment depend on any existing tasks that
   are still pending? If so, note the dependency.
4. Write observable success criteria — what must be true after the amendment

Append to `.pace/PLAN.md`:

If no `## Amendments` section exists yet, add it after the `## Fixes` section
(or after `## Notes`, or at the end of the file):

```markdown

## Amendments

### Amendment {N}: {short title}
**Agent:** @{agent-name}
**Depends on:** {task numbers or "none"}
**Files:** {comma-separated file paths, or "TBD"}
**Success criteria:**
- {observable outcome 1}
- {observable outcome 2}
```

For each additional amendment, append another `### Amendment {N+1}:` block.

### Stage 6 — Update STATE.md

Edit `.pace/STATE.md`:

1. Ensure `## Status` is `in_progress`
2. Add amendment tasks to `## Tasks`:

```
- [ ] A{N}: {title} — @{agent}
```

Present the amendment tasks to the user:

```
Amendment tasks added to the plan:

- A{N}: {title} — @{agent}
- A{N+1}: {title} — @{agent}

Dispatching now...
```

### Stage 7 — Dispatch amendment agents

For each amendment task, build wave scheduling based on dependencies:
- Amendments with `Depends on: none` and no dependency on pending existing tasks
  → dispatch in parallel
- Amendments that depend on pending existing tasks → cannot dispatch yet; leave
  them as `[ ]` in STATE.md and tell the user they will run on the next
  `/pace:execute` or `/pace:resume`

For dispatchable amendments, spawn the assigned agent as a parallel Agent tool call with
`dangerouslySkipPermissions: true` and this prompt (substitute all placeholders).

If a **model override** was read in Stage 0, set the `model` parameter to `{model_value}` on
every Agent tool call. When no model override is set, omit the `model` parameter
entirely so agents inherit the session default:

---
You are executing **Amendment {N}: {title}** as part of a PACE plan.

## Rules
- Before modifying any file — Write, Edit, or NotebookEdit — you must Read it
  first. Never modify a file you have not read in this session.
- Implement only what is described. Do not refactor or improve unrelated code.
- When done, confirm each success criterion is met.
- Your completion summary MUST end with a `## Files Modified` section listing
  every file you created, modified, or deleted. One file path per line.

## Codebase Context

{full contents of .pace/PROJECT.md, or "Not available."}

## Episodic Memory

{contents of .pace/memory/episode.md, or "No tasks completed yet in this execution."}

## Current Plan Context

{summary of PLAN.md objective and what has been completed so far}

## Your Assignment

{amendment description from the user}

## Files Likely Affected

{files from PLAN.md amendment block, or "not specified"}

## Success Criteria

{success criteria from PLAN.md amendment block}
---

Wait for all dispatched amendment agents to complete.

### Record amendment agent usage

If `session_uuid` is available, record each amendment agent's token usage in order. For
each amendment task A{N} dispatched in this stage, run the following. When a **model
override** was read in Stage 0, pass it as the 5th argument to `append-usage.sh`. When
no model override is set, omit the 5th argument entirely:

```bash
# With model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} | bash ~/.claude/lib/pace/append-usage.sh amend A{N} {agent_type} "" {model_value}

# Without model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} | bash ~/.claude/lib/pace/append-usage.sh amend A{N} {agent_type}
```

Where `{N}` is the amendment number and `{agent_type}` is the agent assigned to that
amendment task. If these commands fail, continue without interrupting the user.

### Stage 8 — Commit and record outcomes

For each dispatched amendment task, process in task-number order:

**Commit changes:**

1. Parse the `## Files Modified` section from the agent's completion summary.
2. Stage the files:
   ```bash
   git add {file1} {file2} ...
   ```
3. Check if there are staged changes:
   ```bash
   git diff --cached --quiet
   ```
   - If staged changes exist (exit code 1), commit:
     ```bash
     git commit -m "Amendment {N}: {title}"
     ```
   - If no staged changes (exit code 0), skip the commit.

If the agent did not include `## Files Modified`, fall back to:
```bash
git add -A
git diff --cached --quiet || git commit -m "Amendment {N}: {title}"
```

**Record outcomes:**

**On success:** Edit STATE.md — change `[ ]` to `[x]`. Move the task line into
`## Completed` with a timestamp:

```
- [x] A{N}: {title} — @{agent} _(completed {ISO timestamp})_
```

Append the specialist's completion summary to `.pace/memory/episode.md`.
If the file does not exist, create `.pace/memory/` and create the file first.

Then append:

```markdown
## Amendment {N}: {title} (@{agent})
_Completed: {ISO timestamp}_

{completion summary returned by the specialist}

---
```

Spawn `pace-documentation-specialist` as a fire-and-forget Agent tool call in patch mode.
If a **model override** was read in Stage 0, set the `model` parameter to `{model_value}` on
this Agent tool call. When no model override is set, omit the `model` parameter
entirely:

```
Patch mode. Amendment just completed.
Task: Amendment {N} — {title}
Agent: {agent}
Files: {files from PLAN.md}
Summary: {completion summary returned by the specialist}
Update .pace/PROJECT.md to reflect any changes introduced by this amendment.
```

**On failure:** Edit STATE.md — change `[ ]` to `[!]`. Record the error in
`## Blockers`:

```
Amendment {N} ({title}): {brief description of what went wrong}
```

Set `## Status` to `blocked` and tell the user which amendment failed and why.

### Stage 9 — Complete

When all dispatched amendment tasks are `[x]`:

Check whether any amendment tasks were deferred (dependencies on pending existing tasks).

**If deferred tasks exist:**
```
Amendments applied: {count}
Deferred (waiting on dependencies): {count}

- A{N}: {title} — depends on Task {X} (still pending)

Run /pace:execute or /pace:resume to continue the plan — deferred amendments will run when their dependencies complete.
```

**If no deferred tasks:**
```
All amendments applied.

Run /pace:verify to check the full plan criteria.
Or /pace:execute to continue with any remaining original tasks.
```

</process>
</output>
