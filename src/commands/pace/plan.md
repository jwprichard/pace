---
name: pace:plan
description: Interview the user, assemble a domain planning team, and produce PLAN.md
argument-hint: "[topic]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Task
  - AskUserQuestion
---

<objective>
Conduct a structured planning interview, select the right domain expert agents
based on the work described, run them in parallel to produce draft plans, then
hand all drafts to the pace-synthesiser to produce a single coherent PLAN.md.

You are a coordinator. You do not write the plan yourself — you assemble the
team and synthesise their output.
</objective>

<process>

## Stage 1 — Pre-flight

Check that the agent registry exists:
- Load `.pace/AGENT-REGISTRY.md`
- If it does not exist, stop and tell the user to run `/pace:sync-agents` first

Create the drafts directory: `.pace/drafts/`
Clear any existing draft files from a previous run.

## Stage 2 — Interview

Ask the user the following questions **one at a time**. Wait for each answer
before asking the next. Do not batch them.

1. **What are you building or changing?**
   (Free-form. Encourage detail — the more context, the better the plan.)

2. **What does success look like when this is done?**
   (Looking for observable outcomes, not implementation steps.)

3. **What's the primary domain of this work?**
   Offer options to help them choose:
   - Backend / API / data
   - Frontend / UI
   - Full-stack feature
   - Design / UX
   - Infrastructure / DevOps
   - Marketing / content
   - Other (ask them to describe)

4. **Are there any constraints, dependencies, or decisions already made?**
   (Tech stack, existing patterns to follow, things to avoid, etc.)

5. **Rough scope check — does this feel like:**
   - A small focused change (1-2 days)
   - A medium feature (3-5 days)
   - Something larger that spans multiple weeks or teams

   If they say larger → ask them to describe the first meaningful slice of
   work to plan now. A good slice delivers value on its own.

Capture all answers as `{requirements}` — a structured summary you will pass
to each planning agent.

## Stage 3 — Agent Selection

Based on the interview answers, select **2-3 domain planning agents** from the
registry. Use this as a guide:

| Work type | Planning team |
|---|---|
| Backend / API | `@Software Architect`, `@Backend Architect` |
| Frontend / UI | `@Software Architect`, `@UX Architect` |
| Full-stack feature | `@Software Architect`, `@Backend Architect`, `@UX Architect` |
| Design / UX | `@UX Architect`, `@UI Designer` |
| Infrastructure | `@Software Architect`, `@DevOps Automator` |
| Marketing / content | `@Product Manager`, `@Content Creator` |
| Product feature | `@Software Architect`, `@Product Manager` |

`@Software Architect` should be on the team for any technical work.
Load the relevant Tier 2 division files from `.pace/agents/` to confirm the
exact agent names before spawning.

Tell the user which agents you are assembling and why, then proceed.

## Stage 4 — Parallel Draft Planning

Spawn each selected agent as a parallel Task with the following prompt
(substitute `{agent_role}`, `{requirements}`, and `{agent_name}`):

---
You are acting as a **{agent_role}** planning expert.

Your job is to produce a domain-specific draft plan for the following work.
Focus on your area of expertise only — do not try to cover every aspect.
Another agent will cover other domains and a synthesiser will merge all drafts.

## Requirements

{requirements}

## Your Task

Produce a draft plan and write it to `.pace/drafts/{agent_name}.md` using
exactly this format:

```markdown
# Draft Plan — {agent_role}

## Domain Focus
One sentence describing which aspect of the work you are planning.

## Proposed Tasks

### Task: {short title}
**Priority:** high | medium | low
**Depends on:** task numbers this must wait for, or "none"
**Files likely affected:** comma-separated list, or "unknown"
**Agent:** @agent-name-from-registry (the specialist who should implement this)
**Allowed tools:** comma-separated list of tools this task needs (e.g. Read, Write, Edit, Bash, Glob, Grep)
**Success criteria:**
- Observable outcome 1
- Observable outcome 2

### Task: {short title}
...

## Constraints & Decisions
Any constraints, risks, or decisions that the synthesiser should factor in.

## Notes
Anything else relevant from your domain perspective.
```

Propose as many tasks as the work genuinely requires. Do not pad with unnecessary tasks.
Only include tasks within your domain expertise.
Mark dependencies accurately — independent tasks will be run in parallel.
---

Wait for all parallel Tasks to complete before proceeding.

## Stage 5 — Synthesis

Once all draft files exist in `.pace/drafts/`, spawn the `pace-synthesiser`
agent as a Task with the following prompt:

---
Read all draft plan files in `.pace/drafts/`.
Read `.pace/AGENT-REGISTRY.md` and the relevant Tier 2 division files to
validate agent names.

The requirements that drove these drafts are:

{requirements}

Synthesise all drafts into a single PLAN.md at `.pace/PLAN.md`.
---

## Stage 6 — Approval

Once the synthesiser completes, read `.pace/PLAN.md` and present it to the
user in full.

Then use the AskUserQuestion tool to ask:

```
question: "How would you like to proceed with this plan?"
header: "Plan review"
options:
  - label: "Approve"
    description: "Lock this plan and begin tracking state. Run /pace:execute when ready."
  - label: "Edit"
    description: "Describe your changes and I'll update the plan, then ask again."
  - label: "Reject"
    description: "Discard this plan and start over."
```

**If they choose A (Approve):**
Write `.pace/STATE.md` using this format:

```markdown
# STATE
_Plan: {plan title}_
_Started: {ISO timestamp}_

## Status
in_progress

## Tasks
- [ ] 1: {task title} — @{agent}
- [ ] 2: {task title} — @{agent}
- [ ] 3: {task title} — @{agent}
- [ ] 4: {task title} — @{agent}

## Completed
(none yet)

## Blockers
(none)
```

Then tell the user: **"Plan approved. Run `/pace:execute` to start."**

**If they choose E (Edit):**
Ask what they'd like to change. Make the edits to `.pace/PLAN.md` directly.
Re-present the updated plan and ask the approval question again.

**If they choose R (Reject):**
Confirm with the user, then delete `.pace/PLAN.md` and tell them they can
run `/pace:plan` again when ready.

</process>
