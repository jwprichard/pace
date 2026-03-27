---
name: pace:resume
description: Picks up execution from the last incomplete task in STATE.md
allowed-tools:
  - Read
---

<objective>
Read STATE.md and route the user to the right next action.
This command is intentionally thin — /pace:execute already handles resume
logic by treating [~] tasks as pending. This command just checks state and
hands off.
</objective>

<process>

## Step 1 — Read STATE.md

Read `.pace/STATE.md`. If it does not exist:
```
No STATE.md found. There is nothing to resume.
Run /pace:plan to start a new plan.
```

## Step 2 — Check status

Read `## Status` in STATE.md.

**If `complete`:**
```
This plan is already complete.
Run /pace:verify to check the work against the success criteria.
```

**If `blocked`:**

Read `## Blockers`. Show the full blocker content to the user:
```
Execution is blocked.

{blocker content from STATE.md}

Fix the issue above, then run /pace:resume to continue.
```

**If `in_progress`:**

Read `## Tasks`. Count and list the incomplete tasks (those marked `[ ]` or `[~]`):

```
Resuming plan: {plan title from STATE.md}

Remaining tasks:
{list of [ ] and [~] tasks}

Handing off to /pace:execute...
```

Then proceed exactly as `/pace:execute` would — load PLAN.md, build waves from
the remaining tasks, and execute them. (The resume logic is identical to a fresh
execute run; execute already skips `[x]` tasks and treats `[~]` as pending.)

</process>
