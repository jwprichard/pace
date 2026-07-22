---
name: pace:roadmap
description: Interview the user, decompose a large feature into phases, and produce ROADMAP.md
argument-hint: "[--research] [--abandon] [topic]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Agent
  - AskUserQuestion
---

<objective>
Conduct a structured interview about a large feature, then hand the requirements
to a single roadmap planning agent that decomposes the work into ordered phases
and writes ROADMAP.md — each phase scoped to a single /pace:plan cycle.

You are a coordinator. You do not write the roadmap yourself — you run the
interview and dispatch the planner.
</objective>

<process>

> **Agent spawning rule:** Every `Agent` spawned in this command must use `dangerouslySkipPermissions: true`.
> This applies to all agent spawns without exception.

## Stage 0 — Parse Flags

Read the full argument string. Detect all flags independently:

- If the argument contains `--research`: set `research_mode = true`, strip `--research` from the string
- If the argument contains `--abandon`: set `abandon_mode = true`, strip `--abandon` from the string
- If a flag is absent, set the corresponding mode to `false`

The remaining string after all flags are stripped is the user's topic prompt.

## Stage 1 — Pre-flight

### Load settings

Read `.pace/settings.md`. If the file exists, extract the value after `plan-model:`
on its own line. Trim whitespace. If the value is non-empty, set `model_override` to
that value (e.g. `sonnet`, `opus`, `haiku`). If the file does not exist, or the
`plan-model:` line is absent, or its value is empty, set `model_override = null`.

> **How to pass the model override:** `model` is a top-level parameter on the Agent tool,
> not text inside the prompt. Correct usage:
> `Agent(description: "...", prompt: "...", model: "{model_override}")`

Run the following checks in order. Stop on the first failure unless otherwise noted.

### Check 1: PROJECT.md (required for planning)

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
4. Spawn `pace-codebase-analyst` using the Agent tool with `dangerouslySkipPermissions: true`
   and the collected data. If `model_override` is set, set the `model` parameter to `{model_override}`
   in the Agent tool call. Wait for completion.

If **No**: stop. Tell the user to run `/pace:scan` first.

**If it exists:** Read the `_Commit:_` line. Run `git rev-parse --short HEAD`.
If they differ, warn (non-blocking):
```
Warning: PROJECT.md is out of date (stored: {stored hash}, current: {current hash}).
Agents may plan against stale codebase structure. Consider running /pace:scan to refresh.
```
Then continue.

### Check 2: Existing roadmap

Check whether `.pace/ROADMAP.md` exists.

- **Missing** → clean slate, proceed to Check 3
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
    Then proceed to Check 3.
    If **No**: stop. No changes made.

### Check 3: Clear plan-specific artifacts

```bash
rm -rf .pace/requirements/
mkdir -p .pace/requirements/
```

## Stage 1.5 — Research

If `research_mode` is `false`, skip this stage entirely and proceed to Stage 2.

If `research_mode` is `true`, spawn a single Agent tool call with `dangerouslySkipPermissions: true`
using the prompt below. If `model_override` is set, set the `model` parameter to `{model_override}`
in the Agent tool call. The stripped topic string (after all flags are removed) is the
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

Wait for the agent to complete. Display the bullet-point summary to the user before
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
{estimated number of phases, or "let the planner determine"}

## Assumptions
{things inferred, not stated — so the planner knows what to flag if wrong}
```

If `research_mode = true`, append:

```
## Research Findings
{full contents of .pace/requirements/research.md}
```

Write the complete block to `.pace/requirements/brief.md`.

## Stage 3 — Decompose

Read `.pace/PROJECT.md` in full. Read `.pace/requirements/brief.md`.

Tell the user you are dispatching the roadmap planner, then spawn a single
Agent tool call with `dangerouslySkipPermissions: true` using the prompt below.
If `model_override` is set, set the `model` parameter to `{model_override}` on
the Agent tool call:

---
You are a roadmap planning expert. Your job is to decompose a large feature
into ordered phases and write the roadmap. Each phase must be scoped to a
single planning cycle (2–6 tasks when planned in detail later).

## Codebase Context

{full contents of .pace/PROJECT.md}

## Requirements

{contents of .pace/requirements/brief.md}

## Your Task

Decompose the work into phases and write `.pace/ROADMAP.md` using exactly
this format:

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
{Any constraints, risks, dropped scope, or decomposition decisions worth recording}
```

Rules:
1. **Order by dependencies** — a phase cannot depend on a later-numbered phase.
2. **Number sequentially** — Phase 1, Phase 2, Phase 3, etc.
3. **All phases start as `pending`** — do not set any other status.
4. **Keep phases plan-sized** — each should produce 2–6 tasks when planned in
   detail. If a phase is too large, split it. If too small, merge with an
   adjacent phase.
5. **Each phase delivers incremental value where possible** — avoid phases that
   produce nothing usable on their own. Prefer smaller phases over larger ones;
   if in doubt, split.
6. **Objective describes outcome** — what is true when the phase is done, not
   what activities occur during it.
7. **Do not plan the tasks within each phase** — that is `/pace:plan`'s job.
   Keep phases at the objective/deliverable level.
8. **Record the ordering rationale** — explain in `## Notes` why the phases
   are ordered the way they are, and note any risks or considerations for
   later planning.

When done, report back a one-line summary: how many phases, their titles, and
any risks flagged.
---

Wait for the agent to complete.

## Stage 4 — Approval

Once the planner completes, read `.pace/ROADMAP.md` and present it to the
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
This is expected — the roadmap requirements are consumed during decomposition and
persisted in ROADMAP.md itself.

</process>
