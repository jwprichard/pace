---
name: pace:verify
description: Checks completed work against PLAN.md success criteria using the pace-verification-specialist
allowed-tools:
  - Read
  - Task
  - AskUserQuestion
---

<objective>
Delegate verification of the current plan to the pace-verification-specialist.
Present the structured verdict to the user and route them to the next step.

You do not verify anything yourself — the specialist does that.
</objective>

<process>

> **Task spawning rule:** Every `Task` spawned in this command must use `dangerouslySkipPermissions: true`.

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

## Step 2 — Spawn verification specialist

Spawn `pace-verification-specialist` as a Task with the following prompt:

---
Read `.pace/PLAN.md` and verify all completed tasks against their success criteria.

For each task marked `[x]` in `.pace/STATE.md`, check every success criterion.
For tasks not yet completed (`[ ]`, `[~]`, `[!]`), note them as unverified — do not check them.

Return the full structured verification report.
---

Wait for the task to complete.

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
    description: "Spawn the assigned agents to fix each failing criterion, then re-verify."
  - label: "Fix manually"
    description: "I'll fix the issues myself. Findings are saved to .pace/VERIFICATION.md."
```

**If they choose Fix automatically → go to Step 4.**
**If they choose Fix manually → tell the user:**
```
Findings saved to .pace/VERIFICATION.md.
Run /pace:verify again when you're ready to re-check.
```

## Step 4 — Spawn fix agents

Read `.pace/VERIFICATION.md`. For each failing task:
- Note the agent, files, allowed tools, and the specific failing criteria

Spawn each failing task's agent as a **parallel Task** with `dangerouslySkipPermissions: true`
and this prompt:

---
You are fixing a verification failure as @{agent}.

## What Failed

{failing criteria block from VERIFICATION.md for this task — criterion, expected, found}

## Files to Fix

{files from VERIFICATION.md}

## Original Task Context

Read `.pace/PLAN.md` — Task {N}: {title} — for full context on what this task was meant to deliver.

## Your Job

Fix only what failed. Do not rewrite passing work. Address each failing criterion
precisely — the expected state is the spec.

When done, confirm each criterion you fixed and what you changed.

## Allowed Tools

{allowed tools from VERIFICATION.md}

---

Wait for all fix agents to complete.

## Step 5 — Re-verify

Spawn `pace-verification-specialist` again (same prompt as Step 2).

Wait for it to complete, then return to **Step 3** to present the new verdict.

If the second pass still returns NEEDS WORK, present the remaining failures and
ask the user again — do not loop automatically more than once without user confirmation.

**If ERROR (specialist could not run):**
Report the error and ask the user to check that PLAN.md is correctly formatted.

</process>
