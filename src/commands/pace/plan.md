---
name: pace:plan
description: Interview the user, assemble a domain planning team, and produce PLAN.md
argument-hint: "[--tdd] [--research] [--abandon] [topic]"
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

## Stage 0 — Parse Flags

Read the full argument string. Detect all flags independently:

- If the argument contains `--tdd`: set `tdd_mode = true`, strip `--tdd` from the string
- If the argument contains `--research`: set `research_mode = true`, strip `--research` from the string
- If the argument contains `--abandon`: set `abandon_mode = true`, strip `--abandon` from the string
- If a flag is absent, set the corresponding mode to `false`

All three flags are stripped independently — any combination is valid and no flag
contaminates another. The remaining string after all flags are stripped is the user's
topic prompt.

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
    description: "Run the scan and continue to planning."
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

### Check 3: Prior plan state

Check whether `.pace/STATE.md` exists.

- **Missing** → clean slate, proceed to Check 4
- **Exists, status = complete** → clean slate, proceed to Check 4
- **Exists, status = in_progress or blocked:**
  - If `abandon_mode = false` → stop:
    ```
    A plan is still in progress.
    Run /pace:complete to archive it before starting a new one.
    Or run /pace:plan --abandon to discard it and start fresh.
    ```
  - If `abandon_mode = true` → use AskUserQuestion:
    ```
    question: "Abandon the current plan? This will delete PLAN.md, STATE.md, requirements/, and memory/episode.md. Semantic memory and PROJECT.md are preserved. This cannot be undone."
    header: "Abandon current plan?"
    options:
      - label: "Yes, abandon it"
        description: "Delete the current plan and start fresh."
      - label: "No, keep it"
        description: "Stop here. No changes made."
    ```
    If **Yes**: run:
    ```bash
    rm -f .pace/PLAN.md
    rm -f .pace/STATE.md
    rm -f .pace/memory/episode.md
    rm -rf .pace/requirements/
    rm -rf .pace/drafts/
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

(This is the user's prompt after removing `--tdd`, `--research`, and `--abandon` flags.
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

Wait for the Task to complete. Once it finishes, display the bullet-point summary it
returned to the user before proceeding to Stage 2. Do not write the summary to any file —
`.pace/requirements/research.md` is the single canonical output artifact; the summary is
shown inline only.

## Stage 2 — Interview

### 2a — Parse the prompt

Read the topic string (all flags already stripped in Stage 0).

From the topic, extract what is already known and what is genuinely unclear.

Build a working picture:
- **What** — the thing being built or changed (as specific as possible)
- **Domain** — frontend, backend, infra, etc. (infer if not stated)
- **Scope signals** — any mentioned files, components, services, or constraints
- **Assumptions** — things you are inferring that the user did not state explicitly
- **Open questions** — aspects that are unclear and will materially affect the plan

If no topic was provided, ask a single open question first:
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

### 2d — Build requirements summary and write brief.md

Once all questions are answered, compile everything into a structured requirements block:

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

If `research_mode = true`, append to this block:

```
## Research Findings
{full contents of .pace/requirements/research.md}
```

Write the complete block (including research section if present) to `.pace/requirements/brief.md`.

The `{requirements}` variable used in all subsequent stages means: the contents of
`.pace/requirements/brief.md`. Read from file — do not hold in context.

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
explicitly name the testing peer and explain which preference criterion matched.

## Stage 4 — Parallel Draft Planning

Read `.pace/PROJECT.md` in full. Read `.pace/requirements/brief.md`.

Spawn each selected domain agent as a parallel Task with the following prompt
(substitute `{agent_role}`, `{agent_name}`, `{codebase_context}`, and `{requirements}`):

---
You are acting as a **{agent_role}** planning expert.

Your job is to produce a domain-specific draft plan for the following work.
Focus on your area of expertise only — do not try to cover every aspect.
Another agent will cover other domains and a synthesiser will merge all drafts.

## Codebase Context

{full contents of .pace/PROJECT.md}

## Requirements

{contents of .pace/requirements/brief.md}

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
**Files likely affected:** comma-separated list of specific file paths where known.
Use "TBD" only when files genuinely cannot be determined at planning time — not as a default.
**Agent:** @agent-name-from-registry (the specialist who should implement this)
**Allowed tools:** (optional) comma-separated restriction from the Standard Specialist Toolkit.
Omit this field entirely to grant the full toolkit: Read, Write, Edit, NotebookEdit,
Bash, Glob, Grep, WebSearch, WebFetch. Only specify to restrict below this default.
**Success criteria:**
Success criteria must describe an observable, checkable state — not an action taken.

Good criteria:
  ✓ `GET /api/users/me` returns 200 with `{id, email, name}` when authenticated
  ✓ `src/models/user.ts` exports a `User` interface with fields: id, email, createdAt
  ✓ Running `npm test` exits 0 with no failing tests mentioning "auth"

Bad criteria (do not write these):
  ✗ "Auth middleware is implemented"
  ✗ "Tests pass"
  ✗ "API endpoint is added"

- {observable outcome 1}
- {observable outcome 2}

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

**TDD mode — testing peer planner:**
If `tdd_mode` is `true`, spawn the selected testing peer agent (chosen in
Stage 3) as an additional parallel Task alongside the domain planners above,
using the prompt below (substitute `{testing_agent_role}`).
This Task runs in parallel with the domain planner Tasks — do not wait for
the domain planners to finish before spawning it.

---
You are acting as a **{testing_agent_role}** testing planning expert.

Your job is to propose test tasks that cover the expected features of the
following work. You are writing a test plan only — you must not plan
implementation tasks. Implementation is handled by separate domain planners
and is explicitly out of your scope.

## Codebase Context

{full contents of .pace/PROJECT.md}

## Requirements

{contents of .pace/requirements/brief.md}

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
**Files likely affected:** comma-separated list of specific file paths, or "TBD" only if genuinely unknown
**Agent:** @agent-name-from-registry (the testing specialist who should implement this)
**Allowed tools:** (optional) omit to grant the Standard Specialist Toolkit
**Success criteria:**
Success criteria must describe an observable, checkable state — not an action taken.

Good criteria:
  ✓ Running `npm test -- --testPathPattern=auth` exits 0
  ✓ `tests/auth.test.ts` contains a test case named "returns 401 when token is missing"
  ✓ Coverage report shows >80% line coverage for `src/auth/`

Bad criteria:
  ✗ "Tests are written"
  ✗ "Auth is tested"

- {observable outcome 1}
- {observable outcome 2}

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

If `tdd_mode` is `false`, do not spawn the testing peer planner. Stage 4
spawns only the domain planners described above — no change.

Wait for all parallel Tasks (domain planners and, when applicable, the testing
peer planner) to complete before proceeding to Stage 5.

## Stage 5 — Synthesis

Read `.pace/PROJECT.md` in full. Read `.pace/requirements/brief.md`.

Once all draft files exist in `.pace/drafts/`, spawn the `pace-synthesiser`
agent as a Task with the following prompt:

---
Read all draft plan files in `.pace/drafts/`.
Read `.pace/AGENT-REGISTRY.md` and the relevant Tier 2 division files to
validate agent names.

## Codebase Context

{full contents of .pace/PROJECT.md}

The requirements that drove these drafts are:

{contents of .pace/requirements/brief.md}

Synthesise all drafts into a single PLAN.md at `.pace/PLAN.md`.
---

**TDD mode — synthesiser compliance block:**
If `tdd_mode` is `true`, append the following block to the synthesiser prompt
above (after the final line "Synthesise all drafts into a single PLAN.md at
`.pace/PLAN.md`."):

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
to detect TDD mode by reading PLAN.md without re-parsing the original arguments.
---

If `tdd_mode` is `false`, the Stage 5 prompt is identical to the base prompt
above — no TDD compliance block is appended and no `_TDD: enabled_` header
is written.

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

**If they choose Approve:**
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

**If they choose Edit:**
Ask what they'd like to change. Make the edits to `.pace/PLAN.md` directly.
Re-present the updated plan and ask the approval question again.

**If they choose Reject:**
Confirm with the user, then delete `.pace/PLAN.md` and tell them they can
run `/pace:plan` again when ready.

## Notes

**requirements/ directory:** Plan-specific artifacts live in `.pace/requirements/`:
- `brief.md` — compiled interview requirements (always written at Stage 2d)
- `research.md` — research findings (written at Stage 1.5, only when `--research` is used)

Both files are cleared at the start of each new plan run (Check 4 of Stage 1) and
deleted when `/pace:complete` runs. They are plan-scoped, not persistent.

**Standard Specialist Toolkit:** The default tool set for all specialist agents is:
`Read, Write, Edit, NotebookEdit, Bash, Glob, Grep, WebSearch, WebFetch`.
Planners should omit `Allowed tools:` from tasks unless they have a specific reason
to restrict below this default. `Task`, `TaskCreate`, `TaskUpdate`, and `AskUserQuestion`
are orchestrator-only tools and are never granted to specialist agents.

**Memory layers:** PACE maintains two memory layers in `.pace/memory/`:
- `episode.md` — what was built in the current execution (written by execute, cleared by complete)
- `semantic.md` — cross-plan institutional knowledge (written by complete, never cleared)

Planners read semantic memory (via the orchestrator in execute). Specialists read
episodic memory only — they do not read or write to the semantic layer.

</process>
