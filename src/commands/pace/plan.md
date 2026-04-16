---
name: pace:plan
description: Interview the user, assemble a domain planning team, and produce PLAN.md
argument-hint: "[--tdd] [--research] [topic]"
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

> **Task spawning rule:** Every `Task` spawned in this command must use `dangerouslySkipPermissions: true`.
> This applies to all agent spawns without exception — planners, synthesiser, and any others.

## Stage 1 — Pre-flight

Check that the agent registry exists:
- Load `.pace/AGENT-REGISTRY.md`
- If it does not exist, stop and tell the user to run `/pace:sync-agents` first

Create the drafts directory: `.pace/drafts/`
Clear any existing draft files from a previous run.

## Stage 1.5 — Research

If `research_mode` is `false`, skip this stage entirely and proceed to Stage 2.

If `research_mode` is `true`, spawn a single Task with `dangerouslySkipPermissions: true` using the prompt below.
The stripped user argument (after both `--tdd` and `--research` have been removed) is the research topic.

---
You are a research agent. Your job is to gather structured background information on the topic provided.

## Topic

{stripped_user_argument}

(This is the user's prompt after removing `--tdd` and `--research` flags. Infer the research subject from this text.)

## Your Task

1. Use `WebSearch` and `WebFetch` to research the topic thoroughly.
2. Write your findings to `.pace/research.md` using exactly this structure:

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

3. After writing the file, return a concise bullet-point summary of no more than five bullets covering the most important findings.

Allowed tools: WebSearch, WebFetch, Write
---

Wait for the Task to complete. Once it finishes, display the bullet-point summary it returned to the user before proceeding to Stage 2. Do not write the summary to any file — `.pace/research.md` is the single canonical output artifact; the summary is shown inline only.

## Stage 2 — Interview

### 2a — Parse the prompt

Read the argument passed to `/pace:plan` (if any).

**TDD mode detection:** Check whether the ARGUMENTS string contains the literal
text `--tdd`. If it does, set `tdd_mode = true` and carry this flag forward into
every subsequent stage — it will affect how tasks are structured in Stage 4 and
what the synthesiser is told in Stage 5. If `--tdd` is not present, set
`tdd_mode = false` and no behaviour changes downstream. Strip `--tdd` from the
argument before treating the remainder as the user's prompt.

**Research mode detection:** Check whether the ARGUMENTS string contains the
literal text `--research`. If it does, set `research_mode = true` and carry
this flag forward into every subsequent stage — it will affect how planning
agents are instructed to gather information in Stage 4 and what the synthesiser
is told in Stage 5. If `--research` is not present, set `research_mode = false`
and no behaviour changes downstream. Strip `--research` from the argument before
treating the remainder as the user's prompt. Both `--tdd` and `--research` are
stripped independently — if both flags are present, both are removed and both
`tdd_mode` and `research_mode` are set to `true` without any else-if chain;
neither flag contaminates the topic string.

From the (stripped) argument, extract what is already known and what is
genuinely unclear.

Build a working picture:
- **What** — the thing being built or changed (as specific as possible)
- **Domain** — frontend, backend, infra, etc. (infer if not stated)
- **Scope signals** — any mentioned files, components, services, or constraints
- **Assumptions** — things you are inferring that the user did not state explicitly
- **Open questions** — aspects that are unclear and will materially affect the plan

If no argument was provided, ask a single open question first:
> "What are you building or changing?"
Then treat their answer as the prompt and proceed.

### 2b — State your understanding

Before asking anything, tell the user what you already know:

```
I understand you want to {concise summary of the work}.

I'll assume:
- {assumption 1}
- {assumption 2}

I have a few questions about the parts that aren't clear yet.
```

Skip this step if nothing meaningful was provided.

### 2c — Ask targeted questions

Identify 2–4 genuine unknowns — things that are unclear from the prompt and
will materially affect how the plan is structured. Ask about these only.

**Do not ask about things already answered by the prompt.**
If the user said "add dark mode to the settings page", do not ask what they are
building. Do ask how they want the preference persisted if that is unclear.

For each unknown, use AskUserQuestion with:
- A specific, direct question about that unknown
- 3–4 pre-filled options that represent the most likely answers given the context
- An "Other" option for anything not covered

Ask one question at a time. Wait for each answer before asking the next.

**What to ask about (only if genuinely unknown):**

| Unknown | Example question |
|---|---|
| Success definition | "What does done look like — what can a user do that they couldn't before?" |
| Scope boundary | "Should this affect X as well, or just Y?" |
| Key constraint | "Any tech or pattern constraints I should know about?" |
| Approach fork | "Two reasonable approaches here — which fits better?" |
| Slice size | "Is this a focused change or a larger feature?" |

**Pre-fill options with your best inference.** The user should be able to
confirm your guess with one click in the common case. Always include an
"Other / something else" option.

**Example** — prompt: "add user avatar upload to the profile page"

Question 1: "Where should uploaded avatars be stored?"
- `Cloud storage (S3 / GCS)` — upload to object storage, store URL in DB
- `Database` — store as binary blob in the users table
- `Local filesystem` — store on the server (not recommended for production)
- `Other / not sure yet`

Question 2: "Should we enforce size or format limits on uploads?"
- `Yes — limit to 5MB, accept JPG/PNG/WebP`
- `Yes — but I'll specify the limits`
- `No limits needed`
- `Other`

### 2d — Build requirements summary

Once all questions are answered, compile everything into a structured
`{requirements}` block:

```
## What
{what is being built or changed — specific}

## Success criteria
{what must be true when this is done — observable outcomes}

## Domain
{primary domain: frontend / backend / full-stack / infra / etc.}

## Constraints
{tech stack, existing patterns, things to avoid, decisions already made}

## Scope
{small / medium / large; if large, the first slice being planned}

## Assumptions
{things inferred, not stated — so planners know what to flag if wrong}
```

Pass this `{requirements}` block to all planning agents.

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

**TDD mode — testing peer selection:**
If `tdd_mode` is `true`, add exactly one testing-division peer planner to the
team alongside the 2–3 domain agents selected above. Use this preference order:

1. `@Reality Checker` — preferred for behavioural or integration-heavy work
   (i.e. the requirements describe end-to-end flows, user-facing behaviour, or
   cross-service interactions)
2. `@Test Results Analyzer` — preferred for analysis-heavy work (i.e. the
   requirements are primarily about data pipelines, reporting, metrics, or
   understanding existing test output)
3. `@API Tester` — preferred for API-focused work (i.e. the primary deliverable
   is a new or changed API surface — endpoints, contracts, or schemas)

Select the first agent in the list whose description matches the work; if none
fits clearly, default to `@Reality Checker`. Load the testing division Tier 2
file from `.pace/agents/` to confirm the exact agent name before spawning.

If `tdd_mode` is `false`, do not add a testing peer — Stage 3 behaviour is
identical to its non-TDD form and no testing agent is selected here.

Tell the user which agents you are assembling and why. When TDD mode is active,
explicitly name the testing peer and explain which preference criterion matched
(e.g. "I'm adding @Reality Checker as a testing peer because this work is
behavioural/integration-focused").

## Stage 4 — Parallel Draft Planning

Spawn each selected domain agent as a parallel Task with the following prompt
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

**Research mode — findings injection:**
If `research_mode` is `true`, append the following section to every domain
planner Task prompt above (after the final line "Mark dependencies accurately —
independent tasks will be run in parallel."):

---
## Research Findings

{full contents of .pace/research.md}
---

Read `.pace/research.md` and substitute its full contents in place of the
placeholder above before spawning each domain planner Task. The appended section
gives each domain planner structured background knowledge gathered in Stage 1.5.

If `research_mode` is `false`, domain planner Task prompts are byte-for-byte
identical to the base prompt above — no section is appended and no changes are
made.

**TDD mode — testing peer planner:**
If `tdd_mode` is `true`, spawn the selected testing peer agent (chosen in
Stage 3) as an additional parallel Task alongside the domain planners above,
using the prompt below (substitute `{testing_agent_role}` and
`{requirements}`). This Task runs in parallel with the domain planner Tasks —
do not wait for the domain planners to finish before spawning it.

---
You are acting as a **{testing_agent_role}** testing planning expert.

Your job is to propose test tasks that cover the expected features of the
following work. You are writing a test plan only — you must not plan
implementation tasks. Implementation is handled by separate domain planners
and is explicitly out of your scope.

## Requirements

{requirements}

## Your Task

Produce a test draft plan and write it to `.pace/drafts/tdd-planner.md` using
exactly this format:

```markdown
# Draft Plan — Testing ({testing_agent_role})

## Domain Focus
One sentence describing the testing perspective you are covering.

## Proposed Tasks

### Task: [TEST] {short title describing what is being tested}
**Priority:** high | medium | low
**Depends on:** none
**Files likely affected:** comma-separated list, or "unknown"
**Agent:** @agent-name-from-registry (the testing specialist who should implement this)
**Allowed tools:** comma-separated list of tools this task needs (e.g. Read, Write, Edit, Bash, Glob, Grep)
**Success criteria:**
- Observable outcome 1
- Observable outcome 2

### Task: [TEST] {short title}
...

## Constraints & Decisions
Any constraints, risks, or test-strategy decisions the synthesiser should factor in.

## Notes
Anything else relevant from a testing perspective.
```

Rules you must follow:
- Propose exactly one test task per expected feature described in the requirements.
- Every task title must begin with the prefix `[TEST]`.
- Every task must have `Depends on: none` — test tasks are not sequenced on
  each other or on implementation tasks here; the synthesiser will handle
  ordering in the final plan.
- Do not plan implementation tasks. Implementation is out of scope for this
  draft. Limit your tasks strictly to verification, testing, and quality
  assurance activities.
---

When both `tdd_mode` and `research_mode` are `true`, apply the research
findings injection to the testing peer planner Task prompt as well: append a
`## Research Findings` section (populated with the full contents of
`.pace/research.md`) to the testing peer planner prompt above, after the final
line of the rules block ("Limit your tasks strictly to verification, testing,
and quality assurance activities."). This is independent of the domain planner
injection — both apply in parallel; neither depends on the other.

If `tdd_mode` is `false`, do not spawn the testing peer planner. Stage 4
spawns only the domain planners described above — no change.

Wait for all parallel Tasks (domain planners and, when applicable, the testing
peer planner) to complete before proceeding to Stage 5.

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

<!-- Ordering note: research block is evaluated first, then TDD block. Both are
     independent — neither references nor depends on the other. Both can be
     active simultaneously without conflict. -->

**Research mode — synthesiser context:**
If `research_mode` is `true`, append the following block to the synthesiser
prompt above (after the final line "Synthesise all drafts into a single PLAN.md
at `.pace/PLAN.md`."). Read `.pace/research.md` and substitute its full
contents in place of the placeholder before spawning the synthesiser Task.

---
## Research Findings

{full contents of .pace/research.md}

When writing PLAN.md, add `_Research: enabled_` on the line immediately after
`_Generated: {timestamp}_`. Example:

```
_Generated: 2026-04-15T12:00:00Z_
_Research: enabled_
```

This marker allows downstream commands (`/pace:execute`, `/pace:verify`, etc.)
to detect research mode by reading PLAN.md without re-parsing the original
arguments.
---

If `research_mode` is `false`, the synthesiser prompt is identical to the base
prompt above — no block is appended, and no `_Research: enabled_` marker is
written to PLAN.md.

**TDD mode — synthesiser compliance block:**
If `tdd_mode` is `true`, append the following block to the synthesiser prompt
above (after the final line "Synthesise all drafts into a single PLAN.md at
`.pace/PLAN.md`."). When both `research_mode` and `tdd_mode` are `true`, both
blocks are appended — the research block first, then this TDD block — each
independently after the base prompt's final line:

---
## TDD Compliance Rules

This plan was generated in TDD mode. You must apply all four rules below when
merging the draft plans into PLAN.md. These rules are mandatory — do not skip
or soften any of them.

1. **[TEST] tasks are required prerequisites.** Treat every task whose title
   begins with `[TEST]` (from `.pace/drafts/tdd-planner.md`) as a required
   prerequisite, not an optional addition. Every `[TEST]` task must appear in
   the final PLAN.md.

2. **Implementation tasks must declare their test dependency.** For every
   implementation task that has a corresponding `[TEST]` task (matched by the
   feature or behaviour being implemented), you must add the `[TEST]` task's
   number to the `Depends on:` field of the implementation task.

3. **Enforce red-green ordering.** No implementation task may carry a lower
   task number than its paired `[TEST]` task. If a `[TEST]` task is task N,
   its paired implementation task must be task N+1 or higher.

4. **Flag untested implementation tasks.** If an implementation task has no
   corresponding `[TEST]` task, do not silently include it. Add a `Notes:`
   field to that task containing exactly: `[TDD VIOLATION] No test task was
   proposed for this implementation task.`

## TDD Header in PLAN.md

After you write the `_Generated: {timestamp}_` line in PLAN.md, add the
following line immediately after it:

```
_TDD: enabled_
```

This marker allows downstream commands (`/pace:execute`, `/pace:verify`, etc.)
to detect TDD mode by reading PLAN.md without re-parsing the original
arguments.
---

If `tdd_mode` is `false`, the Stage 5 prompt is identical to the base prompt
above — no TDD compliance block is appended and no `_TDD: enabled_` header is
written.

## Notes

**Why `WebSearch` and `WebFetch` are not in the frontmatter `allowed-tools` list:**
The frontmatter `allowed-tools` list governs the tools available to the
`pace:plan` command itself — the orchestrating process that conducts the
interview, spawns Tasks, and writes STATE.md. It does not govern the tools
available to spawned Tasks. Each spawned Task (domain planner, testing peer
planner, synthesiser) declares its own allowed tools in the prompt passed to
`Task`, or inherits defaults from the agent definition. When `research_mode` is
`true`, `WebSearch` and `WebFetch` should be listed in the `Allowed tools:`
field of the individual Task prompts passed to planning agents in Stage 4 — not
added here. Adding them to the frontmatter would grant them to the orchestrator
only, which does not perform research itself.

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
