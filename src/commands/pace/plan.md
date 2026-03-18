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
   - Something larger that probably needs splitting into multiple plans

   If they say larger → tell them PACE plans cover 2-4 tasks maximum and ask
   them to describe the first slice of work to plan now.

Capture all answers as `{requirements}` — a structured summary you will pass
to each planning agent.

## Stage 3 — Agent Selection

Based on the interview answers, select **2-3 domain planning agents** from the
registry. Use this as a guide:

| Work type | Planning team |
|---|---|
| Backend / API | `@engineering-software-architect`, `@engineering-backend-architect` |
| Frontend / UI | `@engineering-software-architect`, `@design-ux-architect` |
| Full-stack feature | `@engineering-software-architect`, `@engineering-backend-architect`, `@design-ux-architect` |
| Design / UX | `@design-ux-architect`, `@design-ui-designer` |
| Infrastructure | `@engineering-software-architect`, `@engineering-devops-automator` |
| Marketing / content | `@product-manager`, `@marketing-content-creator` |
| Product feature | `@engineering-software-architect`, `@product-manager` |

`@engineering-software-architect` should be on the team for any technical work.
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
**Files likely affected:** comma-separated list, or "unknown"
**Agent:** @agent-name-from-registry (the specialist who should implement this)
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

Propose 1-3 tasks. Do not pad with unnecessary tasks.
Only include tasks within your domain expertise.
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

## Stage 6 — Report

Once the synthesiser completes, read `.pace/PLAN.md` and present it to the
user. Ask: **"Does this plan look right, or would you like to adjust anything?"**

If they request changes, edit PLAN.md directly — do not re-run the full
pipeline for minor adjustments.

</process>
