---
name: pace:verify
description: Checks completed work against PLAN.md success criteria using the pace-verification-specialist
allowed-tools:
  - Read
  - Task
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
List each failing criterion. Then:
```
Findings saved to .pace/VERIFICATION.md.
Fix the failing criteria above, then run /pace:verify again.
When all criteria pass, run /pace:complete to close out.
```

**If ERROR (specialist could not run):**
Report the error and ask the user to check that PLAN.md is correctly formatted.

</process>
