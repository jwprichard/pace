---
name: pace:verify
description: Checks completed work against PLAN.md success criteria using the pace-verification-specialist
allowed-tools:
  - Read
  - Agent
  - AskUserQuestion
---

<objective>
Delegate verification of the current plan to the pace-verification-specialist.
Present the structured verdict to the user and route them to the next step.

You do not verify anything yourself — the specialist does that.
</objective>

<process>

> **Agent spawning rule:** Every `Agent` spawned in this command must use `dangerouslySkipPermissions: true`.

## Step 1 — Pre-flight

Read `.pace/STATE.md`. If it does not exist, stop:
```
No STATE.md found. Run /pace:plan first to create a plan.
```

Check `## Status` in STATE.md:
- If `in_progress` → warn the user: "Some tasks are still marked as pending or in progress. Verification will check what has been done so far, but the plan is not complete. Proceed anyway? (Running verify on partial work is allowed.)"
- If `blocked` → warn: "The plan is blocked. Verification will only cover completed tasks."
- If `complete` → proceed without warning

Read `.pace/PLAN.md`. If it does not exist, stop:
```
No PLAN.md found. Cannot verify without a plan.
```

### Session UUID

Re-detect the current session UUID by running:

```bash
bash ~/.claude/lib/pace/find-session.sh
```

Store the output as `session_uuid`. If the command fails or returns empty,
set `session_uuid = null` and log a warning:
```
Warning: Could not detect session UUID — token usage will not be recorded.
```

If `session_uuid` is non-null, read the `_Session: {uuid}_` line from STATE.md.
If the stored UUID differs from the detected one, update STATE.md's `_Session:` line
to reflect the current session:
- Edit the line `_Session: {old_uuid}_` → `_Session: {session_uuid}_`

Also derive the encoded project path:

```bash
printf '%s\n' "${PWD//[\/.]/-}"
```

Store the output as `encoded_project_path`.

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

## Step 2 — Spawn verification specialist

If a **model override** was read in Step 1, set the `model` parameter to `{model_value}` on
the Agent tool call. When no model override is set, omit the `model` parameter
entirely so the agent inherits the session default.

Spawn `pace-verification-specialist` using the Agent tool with the following prompt:

---
Read `.pace/PLAN.md` and verify all completed tasks against their success criteria.

For each task marked `[x]` in `.pace/STATE.md`, check every success criterion.
For tasks not yet completed (`[ ]`, `[~]`, `[!]`), note them as unverified — do not check them.

## Episodic Memory

{contents of .pace/memory/episode.md, or "Not available."}

Note: episodic memory records what agents reported building. Use it as context
only — do not trust it as evidence. Verify all criteria from source files and
commands, not from agent summaries.

Return the full structured verification report.
---

Wait for the task to complete.

### Record verification specialist usage

If `session_uuid` is available, run the following. When a **model override** was read in
Step 1, pass it as the 5th argument to `append-usage.sh`. When no model override is set,
omit the 5th argument entirely:

```bash
# With model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} | bash ~/.claude/lib/pace/append-usage.sh verify orchestrator verify-specialist "" {model_value}

# Without model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} | bash ~/.claude/lib/pace/append-usage.sh verify orchestrator verify-specialist
```

If this command fails, continue without interrupting the user — token recording is non-blocking.

## Step 3 — Present the verdict

Display the verification report in full.

Then route the user based on the overall verdict:

**If VERIFIED:**
```
All criteria passed. Run /pace:complete to close out this plan.
```

**If NEEDS WORK:**

Display the failing criteria. Then use AskUserQuestion:

```
question: "Verification found failing criteria. How would you like to proceed?"
header: "Needs work"
options:
  - label: "Fix automatically"
    description: "Spawn a fix agent to address the failing criteria, then re-verify."
  - label: "Fix manually"
    description: "I'll fix the issues myself. Findings are saved to .pace/VERIFICATION.md."
```

**If they choose Fix automatically → go to Step 4.**
**If they choose Fix manually → tell the user:**
```
Findings saved to .pace/VERIFICATION.md.
Run /pace:verify again when you're ready to re-check.
```

## Step 4 — Spawn the fix agent

Read `.pace/VERIFICATION.md`. Collect every failing task's block: the task ID,
files, and the specific failing criteria (criterion, expected, found).

Spawn a **single fix agent** covering all failures, using the Agent tool with
`dangerouslySkipPermissions: true`. If a **model override** was read in Step 1,
set the `model` parameter to `{model_value}` on the Agent tool call. When no model
override is set, omit the `model` parameter entirely so the agent inherits the
session default.

Use this prompt:

---
You are fixing verification failures from a PACE plan.

## What Failed

{all failing criteria blocks from VERIFICATION.md — for each failing task:
task ID, title, files, and each failing criterion with expected vs found}

## Original Task Context

Read `.pace/PLAN.md` — find the task block matching `### {id}. {title}` for each
failing task — for full context on what each task was meant to deliver.

## Your Job

Fix only what failed. Do not rewrite passing work. Address each failing criterion
precisely — the expected state is the spec. Work through the failures one at a
time, in task-ID order.

When done, confirm each criterion you fixed and what you changed.

## Allowed Tools

Read, Write, Edit, NotebookEdit, Bash, Glob, Grep, WebSearch, WebFetch

---

Wait for the fix agent to complete.

### Record fix agent usage

If `session_uuid` is available, run the following. When a **model override** was read
in Step 1, pass it as the 5th argument to `append-usage.sh`. When no model override is
set, omit the 5th argument entirely:

```bash
# With model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} | bash ~/.claude/lib/pace/append-usage.sh verify fix fix-agent "" {model_value}

# Without model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} | bash ~/.claude/lib/pace/append-usage.sh verify fix fix-agent
```

If this command fails, continue without interrupting the user.

## Step 5 — Re-verify

Spawn `pace-verification-specialist` again (same prompt as Step 2, including
`model: {model_value}` in the Agent tool call when the model override is set).

Wait for it to complete.

### Record re-verify specialist usage

If `session_uuid` is available, run the following. When a **model override** was read in
Step 1, pass it as the 5th argument to `append-usage.sh`. When no model override is set,
omit the 5th argument entirely:

```bash
# With model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} | bash ~/.claude/lib/pace/append-usage.sh verify re-verify verify-specialist "" {model_value}

# Without model override:
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} | bash ~/.claude/lib/pace/append-usage.sh verify re-verify verify-specialist
```

If this command fails, continue without interrupting the user — token recording is non-blocking.

Then return to **Step 3** to present the new verdict.

If the second pass still returns NEEDS WORK, present the remaining failures and
ask the user again — do not loop automatically more than once without user confirmation.

**If ERROR (specialist could not run):**
Report the error and ask the user to check that PLAN.md is correctly formatted.

</process>
