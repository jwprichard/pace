---
name: pace:roadmap
description: Interview the user, decompose a large feature into phases, and produce ROADMAP.md
argument-hint: "[--research] [--abandon] [topic]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Task
  - AskUserQuestion
---

<objective>
Conduct a structured interview about a large feature, select domain expert agents
to propose phase decompositions, then synthesise their output into a single
ROADMAP.md with ordered phases — each scoped to a single /pace:plan cycle.

You are a coordinator. You do not write the roadmap yourself — you assemble the
team and synthesise their output.
</objective>

<process>

> **Task spawning rule:** Every `Task` spawned in this command must use `dangerouslySkipPermissions: true`.
> This applies to all agent spawns without exception.

## Stage 0 — Parse Flags

Read the full argument string. Detect all flags independently:

- If the argument contains `--research`: set `research_mode = true`, strip `--research` from the string
- If the argument contains `--abandon`: set `abandon_mode = true`, strip `--abandon` from the string
- If a flag is absent, set the corresponding mode to `false`

The remaining string after all flags are stripped is the user's topic prompt.

## Stage 1 — Pre-flight

Run the following checks in order. Stop on the first failure unless otherwise noted.

### Check 1: Agent registry

Load `.pace/AGENT-REGISTRY.md`.
If it does not exist, stop:
```
Run /pace:sync-agents first to build the agent registry.
```

### Check 2: PROJECT.md (required for planning)

Check whether `.pace/PROJECT.md` exists.

**If it does not exist:**

Use AskUserQuestion:
```
question: "PROJECT.md not found. A codebase scan is required before planning so agents have accurate context. Can I run it now? This will take a moment."
header: "Codebase scan required"
options:
  - label: "Yes, scan now"
    description: "Run the scan and continue to roadmap planning."
  - label: "No, I'll run /pace:scan myself"
    description: "Stop here. I'll run /pace:scan first and then come back."
```

If **Yes**: run the inline scan:
1. Run the following bash commands and collect all output:
   ```bash
   git rev-parse --short HEAD
   find . -maxdepth 2 \
     -not -path './.git/*' \
     -not -path './node_modules/*' \
     -not -path './.pace/*' \
     | sort
   ```
2. Read the following files **if they exist**: `package.json`, `requirements.txt`,
   `Gemfile`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `tsconfig.json`,
   `docker-compose.yml`, `.env.example`, `Makefile`
3. Ensure `.pace/` exists: `mkdir -p .pace`
4. Spawn `pace-codebase-analyst` as a Task with `dangerouslySkipPermissions: true`
   and the collected data. Wait for completion.

If **No**: stop. Tell the user to run `/pace:scan` first.

**If it exists:** Read the `_Commit:_` line. Run `git rev-parse --short HEAD`.
If they differ, warn (non-blocking):
```
Warning: PROJECT.md is out of date (stored: {stored hash}, current: {current hash}).
Agents may plan against stale codebase structure. Consider running /pace:scan to refresh.
```
Then continue.

### Check 3: Existing roadmap

Check whether `.pace/ROADMAP.md` exists.

- **Missing** → clean slate, proceed to Check 4
- **Exists:**
  - If `abandon_mode = false` → stop:
    ```
    A roadmap already exists. Run /pace:roadmap --abandon to discard it and start fresh.
    ```
  - If `abandon_mode = true` → use AskUserQuestion:
    ```
    question: "Abandon the current roadmap? This will delete ROADMAP.md. Existing PLAN.md and STATE.md are not affected. This cannot be undone."
    header: "Abandon current roadmap?"
    options:
      - label: "Yes, abandon it"
        description: "Delete the roadmap and start fresh."
      - label: "No, keep it"
        description: "Stop here. No changes made."
    ```
    If **Yes**: run:
    ```bash
    rm -f .pace/ROADMAP.md
    ```
    Then proceed to Check 4.
    If **No**: stop. No changes made.

### Check 4: Clear plan-specific artifacts

```bash
rm -rf .pace/requirements/ .pace/drafts/
mkdir -p .pace/requirements/ .pace/drafts/
```

## Stage 1.5 — Research

If `research_mode` is `false`, skip this stage entirely and proceed to Stage 2.

If `research_mode` is `true`, spawn a single Task with `dangerouslySkipPermissions: true`
using the prompt below. The stripped topic string (after all flags are removed) is the
research topic.

---
You are a research agent. Your job is to gather structured background information on the topic provided.

## Topic

{stripped_user_argument}

(This is the user's prompt after removing `--research` and `--abandon` flags.
Infer the research subject from this text.)

## Your Task

1. Use `WebSearch` and `WebFetch` to research the topic thoroughly.
2. Write your findings to `.pace/requirements/research.md` using exactly this structure:

```markdown
# Research Findings

## Topic
{one-sentence description of what was researched}

## Key Findings
- {finding 1}
- {finding 2}
- {finding 3}
- ...

## Sources
- {URL 1}
- {URL 2}
- ...
```

3. After writing the file, return a concise bullet-point summary of no more than five
   bullets covering the most important findings.

Allowed tools: WebSearch, WebFetch, Write
---

Wait for the Task to complete. Display the bullet-point summary to the user before
proceeding to Stage 2.

## Stage 2 — Interview

### 2a — Parse the prompt

Read the topic string (all flags already stripped in Stage 0).

From the topic, extract what is already known and what is genuinely unclear.

Build a working picture:
- **What** — the large feature or initiative being planned
- **Domain** — frontend, backend, infra, full-stack, etc.
- **Scale signals** — any indication of how large the effort is
- **Known ordering** — any constraints on what must come first
- **Assumptions** — things you are inferring that the user did not state explicitly
- **Open questions** — aspects that are unclear and will materially affect decomposition

If no topic was provided, ask a single open question first:
> "What large feature or initiative do you want to plan a roadmap for?"
Then treat their answer as the prompt and proceed.

### 2b — State your understanding

Before asking anything, tell the user what you already know:

```
I understand you want to build {concise summary of the feature}.

I'll assume:
- {assumption 1}
- {assumption 2}

I have a few questions to help break this down into phases.
```

Skip this step if nothing meaningful was provided.

### 2c — Ask targeted questions

Identify 2–4 genuine unknowns that will materially affect how the work is decomposed
into phases. Ask about these only.

**Do not ask about things already answered by the prompt.**

For each unknown, use AskUserQuestion with:
- A specific, direct question about that unknown
- 3–4 pre-filled options that represent the most likely answers given the context
- An "Other" option for anything not covered

Ask one question at a time. Wait for each answer before asking the next.

**What to ask about (only if genuinely unknown):**

| Unknown | Example question |
|---|---|
| End state | "What does the finished feature look like — what can users do?" |
| Phase boundaries | "Are there natural breakpoints — e.g., backend first, then UI?" |
| Priority ordering | "Is there a part that should ship first for early feedback?" |
| External dependencies | "Does any phase depend on something outside this codebase?" |
| Scale | "Roughly how many plan-sized pieces do you think this is?" |

**Pre-fill options with your best inference.** The user should be able to
confirm your guess with one click in the common case.

### 2d — Build requirements summary and write brief.md

Once all questions are answered, compile everything into a structured requirements block:

```
## What
{the large feature being decomposed — specific}

## End state
{what must be true when all phases are complete — observable outcomes}

## Domain
{primary domain: frontend / backend / full-stack / infra / etc.}

## Constraints
{tech stack, existing patterns, ordering constraints, things to avoid}

## Known phase boundaries
{any decomposition hints from the interview — e.g., "backend before frontend"}

## Scale
{estimated number of phases, or "let agents determine"}

## Assumptions
{things inferred, not stated — so agents know what to flag if wrong}
```

If `research_mode = true`, append:

```
## Research Findings
{full contents of .pace/requirements/research.md}
```

Write the complete block to `.pace/requirements/brief.md`.

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
| Product feature | `@Software Architect`, `@Product Manager` |

`@Software Architect` should be on the team for any technical work.
Load the relevant Tier 2 division files from `.pace/agents/` to confirm the
exact agent names before spawning.

Tell the user which agents you are assembling and why.

## Stage 4 — Parallel Phase Decomposition

Read `.pace/PROJECT.md` in full. Read `.pace/requirements/brief.md`.

Spawn each selected domain agent as a parallel Task with the following prompt
(substitute `{agent_role}`, `{agent_name}`, `{codebase_context}`, and `{requirements}`):

---
You are acting as a **{agent_role}** planning expert.

Your job is to propose how to decompose a large feature into ordered phases.
Each phase should be scoped to a single planning cycle (2–6 tasks when planned
in detail later). Focus on your area of expertise only — another agent will cover
other domains and a synthesiser will merge all proposals.

## Codebase Context

{full contents of .pace/PROJECT.md}

## Requirements

{contents of .pace/requirements/brief.md}

## Your Task

Propose a phase decomposition and write it to `.pace/drafts/{agent_name}.md`
using exactly this format:

```markdown
# Phase Proposal — {agent_role}

## Domain Focus
One sentence describing which aspect of the decomposition you are covering.

## Proposed Phases

### Phase: {short title}
**Objective:** What this phase delivers — one or two sentences describing the
outcome, not the activities.
**Key deliverables:**
- {concrete deliverable 1}
- {concrete deliverable 2}
**Depends on:** phase titles this must wait for, or "none"
**Domain:** {primary domain this phase touches}
**Estimated complexity:** small (2-3 tasks) | medium (3-4 tasks) | large (5-6 tasks)

### Phase: {short title}
...

## Ordering Rationale
Explain why you ordered the phases this way — what must come first and why.

## Risks & Considerations
Anything the synthesiser should factor into the final decomposition.
```

Guidelines:
- Each phase should deliver incremental value where possible — avoid phases that
  produce nothing usable on their own.
- Prefer smaller phases over larger ones. If in doubt, split.
- Mark dependencies accurately — independent phases can be planned in parallel later.
- Do not plan the tasks within each phase — that is `/pace:plan`'s job.
  Keep phases at the objective/deliverable level.
---

Wait for all parallel Tasks to complete before proceeding to Stage 5.

## Stage 5 — Synthesis

Read `.pace/PROJECT.md` in full. Read `.pace/requirements/brief.md`.

Once all draft files exist in `.pace/drafts/`, spawn the `pace-synthesiser`
agent as a Task with the following prompt:

---
Read all phase proposal files in `.pace/drafts/`.

## Codebase Context

{full contents of .pace/PROJECT.md}

The requirements that drove these proposals are:

{contents of .pace/requirements/brief.md}

## Your Task

Synthesise all phase proposals into a single ROADMAP.md at `.pace/ROADMAP.md`.

Use exactly this format:

```markdown
# ROADMAP: {feature title}
_Created: {ISO timestamp}_

## Objective
{What this roadmap achieves when all phases are complete — 1-2 sentences.}

## Phases

### Phase 1: {title}
**Status:** pending
**Objective:** {What this phase delivers — outcome, not activity}
**Key deliverables:**
- {deliverable}
- {deliverable}
**Depends on:** none

### Phase 2: {title}
**Status:** pending
**Objective:** {What this phase delivers}
**Key deliverables:**
- {deliverable}
- {deliverable}
**Depends on:** 1

### Phase 3: {title}
...

## Notes
{Any constraints, decisions, dropped phases, or context from the proposals}
```

Rules:
1. **Deduplicate** — if multiple proposals cover the same work, merge into one phase.
2. **Order by dependencies** — a phase cannot depend on a later-numbered phase.
3. **Preserve all deliverables** — every deliverable from every proposal must appear
   in some phase unless it is clearly redundant.
4. **Number sequentially** — Phase 1, Phase 2, Phase 3, etc.
5. **All phases start as `pending`** — do not set any other status.
6. **Keep phases plan-sized** — each should produce 2–6 tasks when planned in detail.
   If a proposed phase is too large, split it. If too small, merge with an adjacent phase.
7. **Objective describes outcome** — what is true when the phase is done, not what
   activities occur during it.
---

## Stage 6 — Approval

Once the synthesiser completes, read `.pace/ROADMAP.md` and present it to the
user in full.

Then use the AskUserQuestion tool to ask:

```
question: "How would you like to proceed with this roadmap?"
header: "Roadmap review"
options:
  - label: "Approve"
    description: "Lock this roadmap. Run /pace:plan to start planning the first phase."
  - label: "Edit"
    description: "Describe your changes and I'll update the roadmap, then ask again."
  - label: "Reject"
    description: "Discard this roadmap and start over."
```

**If they choose Approve:**
Tell the user:
```
Roadmap approved. Run /pace:plan to start planning Phase 1.
```

**If they choose Edit:**
Ask what they'd like to change. Make the edits to `.pace/ROADMAP.md` directly.
Re-present the updated roadmap and ask the approval question again.

**If they choose Reject:**
Confirm with the user, then delete `.pace/ROADMAP.md` and tell them they can
run `/pace:roadmap` again when ready.

## Notes

**Relationship to /pace:plan:** The roadmap decomposes a large feature into phases.
Each phase is then planned in detail via `/pace:plan`. When a roadmap exists,
`/pace:plan` should use the next pending phase's objective and deliverables as
input context for the planning interview — pre-populating what is known so the
user only answers what is genuinely unclear at that level.

**Relationship to /pace:complete:** When `/pace:complete` closes a plan that
corresponds to a roadmap phase, it should mark that phase as `complete` in
ROADMAP.md and advance to the next pending phase.

**Phase status values:**
- `pending` — not yet started
- `in_progress` — currently being planned or executed via /pace:plan
- `complete` — plan completed and verified

**Lifecycle:** ROADMAP.md persists across multiple plan cycles. It is only deleted
when explicitly abandoned via `--abandon` or when the user manually removes it.
It is NOT deleted by `/pace:complete`.

**requirements/ directory:** The brief.md and research.md files produced during
roadmap creation will be overwritten when `/pace:plan` runs for a specific phase.
This is expected — the roadmap requirements are consumed during synthesis and
persisted in ROADMAP.md itself.

</process>
