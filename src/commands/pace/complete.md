---
name: pace:complete
description: Closes out a completed plan — full PROJECT.md refresh and .pace/ runtime cleanup
allowed-tools:
  - Read
  - Write
  - Bash
  - Task
---

<objective>
Close out a completed plan cleanly. Refresh the project map with a full rescan,
then delete runtime files that belong to this plan only.

Preserve the persistent .pace/ artifacts (PROJECT.md, AGENT-REGISTRY.md, agents/).
Delete only the plan-specific runtime files.
</objective>

<process>

> **Task spawning rule:** Every `Task` spawned in this command must use `dangerouslySkipPermissions: true`.

## Step 1 — Pre-flight

Read `.pace/STATE.md`. If it does not exist, stop:
```
No STATE.md found. There is nothing to close out.
```

Check `## Status` in STATE.md. If it is not `complete`, stop:
```
The plan is not yet complete (status: {status}).
Finish execution first, then run /pace:complete.
Run /pace:execute to continue, or /pace:resume to pick up from where you left off.
```

## Step 2 — Refresh PROJECT.md

Spawn `pace-documentation-specialist` as a Task in full mode:

---
Full mode. The current plan has just completed.

Run a fresh codebase scan and rewrite `.pace/PROJECT.md` entirely.
Capture the current commit hash and timestamp.
---

Wait for the task to complete.

## Step 3 — Clean up runtime files

Delete the plan-specific runtime files:

```bash
rm -f .pace/PLAN.md
rm -f .pace/STATE.md
rm -rf .pace/drafts/
```

Do NOT delete:
- `.pace/PROJECT.md` — preserve (just refreshed)
- `.pace/AGENT-REGISTRY.md` — preserve (registry is persistent)
- `.pace/agents/` — preserve (registry tier 2 files)
- `.pace/DECISIONS.md` — preserve if it exists (running decision log)

## Step 4 — Confirm

Tell the user:

```
Plan closed.

PROJECT.md refreshed with latest codebase state.
Runtime files cleaned up (PLAN.md, STATE.md, drafts/).

Ready for the next plan. Run /pace:plan to start.
```

</process>
