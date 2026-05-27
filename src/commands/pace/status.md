---
name: pace:status
description: Shows the current plan status, progress, and suggested next steps — read-only, no work is executed
allowed-tools:
  - Read
  - Bash
---

<objective>
Display a concise summary of the current plan's status: what's done, what's
pending, what's blocked, and what the user should do next.

This is strictly read-only. No tasks are executed, no state is modified,
no agents are spawned.
</objective>

<process>

## Step 1 — Check for active plan

Read `.pace/STATE.md`. If it does not exist:
```
No active plan. Run /pace:plan to start one.
```
Stop.

Read `.pace/PLAN.md`. If it does not exist:
```
STATE.md exists but PLAN.md is missing. The plan file may have been deleted.
Run /pace:plan to create a new plan.
```
Stop.

## Step 2 — Parse state

From STATE.md, extract:
- **Plan title** from the `# {title}` heading
- **Status** from `## Status`
- **All tasks** from `## Tasks` and `## Completed`, with their markers:
  - `[x]` completed
  - `[~]` in progress
  - `[ ]` pending
  - `[!]` blocked
- **Blockers** from `## Blockers` (if the section exists and is non-empty)

Count tasks by status.

## Step 3 — Check for roadmap context

If `.pace/ROADMAP.md` exists, read it to determine which phase the current plan
belongs to. Note the phase number and total phases for display.

## Step 4 — Display summary

Present the status in this format:

```
## {Plan title}

**Status:** {status}
{if roadmap: **Roadmap:** Phase {N} of {total} — {phase title}}

### Progress

{completed count}/{total count} tasks complete

  [x] 1a: {title} — @{agent}
  [x] 1b: {title} — @{agent}
  [~] 2a: {title} — @{agent}      <- in progress
  [ ] 2b: {title} — @{agent}
  [!] 3a: {title} — @{agent}      <- blocked

{if blockers exist:}
### Blockers

{blocker content from STATE.md}
```

Use the exact task lines from STATE.md. Annotate `[~]` tasks with "in progress"
and `[!]` tasks with "blocked" as inline notes.

## Step 5 — Suggest next steps

Based on the current status, suggest the appropriate next action:

**If `complete`:**
```
All tasks are done. Next: run /pace:verify to check the work.
```

**If `blocked`:**
```
Execution is blocked. Fix the issue above, then run /pace:resume to continue.
```

**If `in_progress` with `[~]` tasks:**
```
Tasks are marked in progress — this may be from an interrupted session.
Run /pace:resume to pick up where you left off.
```

**If `in_progress` with only `[ ]` and `[x]` tasks:**
```
Ready to continue. Run /pace:execute to start the next wave.
```

</process>
