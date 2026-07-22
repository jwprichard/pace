---
name: pace:plan
description: Interview the user, then produce PLAN.md via a single planner agent
argument-hint: "[--tdd] [--research] [--abandon] [topic]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Agent
  - AskUserQuestion
---

<objective>
Conduct a structured planning interview, compile the requirements into a brief,
then hand the brief to a single pace-planner agent to produce PLAN.md.

You are a coordinator. You do not write the plan yourself — you run the
interview and dispatch the planner.
</objective>

<process>

> **Agent spawning rule:** Every `Agent` spawned in this command must use `dangerouslySkipPermissions: true`.
> This applies to all agent spawns without exception — the planner, research agent, and any others.

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

### Load settings

Read `.pace/settings.md`. If the file exists, extract the value after `plan-model:`
on its own line. Trim whitespace. If the value is non-empty, set `model_override` to
that value (e.g. `sonnet`, `opus`, `haiku`). If the file does not exist, or the
`plan-model:` line is absent, or its value is empty, set `model_override = null`.

> **How to pass the model override:** `model` is a top-level parameter on the Agent tool,
> not text inside the prompt. Correct usage:
> `Agent(description: "...", prompt: "...", model: "{model_override}")`

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
    ```
    Then proceed to Check 4.
    If **No**: stop. No changes made.

### Check 3b: Roadmap context

Check whether `.pace/ROADMAP.md` exists.

If it does not exist, set `roadmap_phase = null` and proceed to Check 4.

If it exists:
1. Read it and find the first phase with `**Status:** pending`
2. If no pending phase exists → set `roadmap_phase = null`, proceed to Check 4
3. If a pending phase is found:
   - Set `roadmap_phase = {phase number}`, `roadmap_phase_title = {phase title}`
   - Store the phase's **Objective** and **Key deliverables** as `phase_context`
   - If the user provided no topic in the argument string → use AskUserQuestion:
     ```
     question: "A roadmap exists with a pending phase. Plan this phase next?"
     header: "Phase {roadmap_phase}: {roadmap_phase_title}"
     options:
       - label: "Yes, plan this phase"
         description: "Use the phase objective and deliverables as context for planning."
       - label: "No, plan something else"
         description: "Ignore the roadmap and plan standalone work."
     ```
     If **Yes**: use the phase objective as the topic string. Proceed.
     If **No**: set `roadmap_phase = null`. Proceed — the user will provide a topic at Stage 2a.
   - If the user provided a topic → set `roadmap_phase = null`. They know what they want.

### Check 4: Clear plan-specific artifacts

```bash
rm -rf .pace/requirements/
rm -f .pace/usage.md
mkdir -p .pace/requirements/
```

### Capture session UUID

Run the following bash command and store the output as `session_uuid`:

```bash
bash ~/.claude/lib/pace/find-session.sh
```

If the command exits non-zero or returns an empty string, set `session_uuid = unknown`.
Store `session_uuid` for use in Stage 5 (STATE.md) and token usage recording.

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

Wait for the agent to complete. Once it finishes, display the bullet-point summary it
returned to the user before proceeding to Stage 2. Do not write the summary to any file —
`.pace/requirements/research.md` is the single canonical output artifact; the summary is
shown inline only.

## Stage 2 — Interview

### 2a — Parse the prompt

Read the topic string (all flags already stripped in Stage 0).

If `roadmap_phase` is set, the phase objective is the topic and the phase
deliverables define the scope boundary. Focus open questions on *how* to
implement the phase, not *what* to build — the roadmap already defines that.

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

### 2c — Ask targeted questions (initial round)

Identify **at least 3** genuine unknowns — things that are unclear from the prompt and
will materially affect how the plan is structured. You must ask a minimum of 3 questions
in this initial round, even if the prompt seems comprehensive. Dig into implementation
details, edge cases, error handling, or user experience nuances to surface questions
the user may not have considered.

**Do not ask about things already answered by the prompt.**
If the user said "add dark mode to the settings page", do not ask what they are
building. Do ask how they want the preference persisted if that is unclear.

For each unknown, use AskUserQuestion with:
- A specific, direct question about that unknown
- 2–3 pre-filled options that represent the most likely answers given the context
- A final option labelled **"Let Claude decide"** with description: "I'll pick the best approach based on the codebase and context."

Ask one question at a time. Wait for each answer before asking the next.

**What to ask about (only if genuinely unknown):**

| Unknown | Example question |
|---|---|
| Success definition | "What does done look like — what can a user do that they couldn't before?" |
| Scope boundary | "Should this affect X as well, or just Y?" |
| Key constraint | "Any tech or pattern constraints I should know about?" |
| Approach fork | "Two reasonable approaches here — which fits better?" |
| Slice size | "Is this a focused change or a larger feature?" |
| Edge case | "What should happen when X fails or is unavailable?" |
| Migration / compatibility | "Do we need to handle existing data or can we start fresh?" |

**Pre-fill options with your best inference.** The user should be able to
confirm your guess with one click in the common case.

### 2c-bis — Continue or proceed

After all initial questions are answered, use AskUserQuestion:

```
question: "I think I have a good understanding of what you're after. Would you like to proceed to planning, or is there more to discuss?"
header: "Ready?"
options:
  - label: "Proceed to planning"
    description: "I'm happy with the scope — go ahead and produce the plan."
  - label: "Let's keep discussing"
    description: "I have more to add, or I'd like you to dig deeper into edge cases and details."
```

**If they choose "Proceed to planning":** move to Stage 2d.

**If they choose "Let's keep discussing":** run another interview round:

1. Think carefully about the requirements gathered so far. Consider:
   - Edge cases that haven't been addressed
   - Failure modes and error handling
   - Performance or scalability implications
   - Security considerations
   - Migration or backwards compatibility concerns
   - UX edge cases (empty states, loading states, error states)
   - Dependencies or ordering constraints that might not be obvious
2. Ask **at least 3 more questions** following the same format as Stage 2c
   (2–3 options + "Let Claude decide" as the final option). These questions
   should go deeper than the initial round — probe the non-obvious aspects
   that could derail implementation if left unresolved.
3. After this round completes, ask the "Continue or proceed" question again
   (repeat Stage 2c-bis). The user can keep iterating as many times as they want.

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
{things inferred, not stated — so the planner knows what to flag if wrong}
```

If `research_mode = true`, append to this block:

```
## Research Findings
{full contents of .pace/requirements/research.md}
```

Write the complete block (including research section if present) to `.pace/requirements/brief.md`.

The `{requirements}` variable used in all subsequent stages means: the contents of
`.pace/requirements/brief.md`. Read from file — do not hold in context.

## Stage 3 — Plan

Read `.pace/PROJECT.md` in full. Read `.pace/requirements/brief.md`.

Tell the user you are dispatching the planner, then spawn the `pace-planner`
agent using the Agent tool with the following prompt. If `model_override` is set,
set the `model` parameter to `{model_override}` on the Agent tool call:

---
Produce a complete PLAN.md at `.pace/PLAN.md` for the following work, following
the format and process defined in your instructions.

Read `.pace/AGENT-REGISTRY.md` and the relevant Tier 2 division files in
`.pace/agents/` to select and validate the agent assigned to each task.

## Codebase Context

{full contents of .pace/PROJECT.md}

## Requirements

{contents of .pace/requirements/brief.md}

{If `tdd_mode` is `true`, append:}

## TDD Mode

TDD mode is enabled for this plan. Apply the TDD rules from your instructions:
plan a `[TEST]` task per expected feature, make implementation tasks depend on
their paired `[TEST]` tasks, enforce red-green ordering in the Implementation
Order, flag untested implementation tasks, and write the `_TDD: enabled_`
header line.

{End of tdd_mode conditional block.}

{If `roadmap_phase` is set, append:}

## Phase Marker

This plan implements Phase {roadmap_phase} of the project roadmap.
Add the following line to PLAN.md immediately after the `_Created:_` line:

```
_Phase: {roadmap_phase}_
```

{End of roadmap_phase conditional block.}
---

Wait for the planner to complete.

## Stage 4 — Record Planning Phase Token Usage

Once the planner completes, record token usage for the planning phase.

Run the following bash commands in order:

1. Derive the encoded project path from the current working directory (replace every `/` and `.` with `-`):
   ```bash
   printf '%s\n' "${PWD//[\/.]/-}"
   ```
   Store the output as `encoded_project_path`.

2. Aggregate token data for the session:
   ```bash
   python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path}
   ```
   Store the JSON output as `usage_json`. If the command fails or returns empty output, skip step 3.

3. Pipe the aggregated JSON to the append script:
   ```bash
   printf '%s' "{usage_json}" | bash ~/.claude/lib/pace/append-usage.sh plan orchestrator plan-orchestrator
   ```

If any of these commands fail, continue to Stage 5 without interrupting the user — token recording is non-blocking.

## Stage 5 — Approval

Once the planner completes, read `.pace/PLAN.md` and present it to the
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
Write `.pace/STATE.md` using this format. Task IDs use the part-prefixed
alphanumeric scheme from PLAN.md (e.g. `1a`, `1b`, `2a`). List tasks in
Implementation Order:

```markdown
# STATE
_Plan: {plan title}_
_Started: {ISO timestamp}_
_Session: {session_uuid}_

## Status
in_progress

## Tasks
- [ ] 1a: {task title} — @{agent}
- [ ] 1b: {task title} — @{agent}
- [ ] 2a: {task title} — @{agent}
- [ ] 2b: {task title} — @{agent}

## Completed
(none yet)

## Blockers
(none)
```

### Branch creation

After writing STATE.md, check the current branch:

```bash
git branch --show-current
```

If the current branch is `main` or `master`:
1. Derive the branch name:
   - If `roadmap_phase` is set: `pace/phase-{roadmap_phase}-{slugified roadmap_phase_title}`
   - Otherwise: `pace/{slugified plan title from PLAN.md}`
   - Slugify: lowercase, replace non-alphanumeric characters with hyphens,
     collapse consecutive hyphens, trim hyphens from ends, truncate to 50 characters
2. Create and switch to the branch:
   ```bash
   git checkout -b {branch-name}
   ```
3. If `roadmap_phase` is set, edit `.pace/ROADMAP.md`: change the matching phase's
   `**Status:** pending` to `**Status:** in_progress`.

If the current branch is not `main` or `master`, use it as-is.

Tell the user which branch is active, then: **"Plan approved. Run `/pace:execute` to start."**

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
The planner should omit `Allowed tools:` from tasks unless it has a specific reason
to restrict below this default. `Agent`, `TaskCreate`, `TaskUpdate`, and `AskUserQuestion`
are orchestrator-only tools and are never granted to specialist agents.

**Memory layers:** PACE maintains two memory layers in `.pace/memory/`:
- `episode.md` — what was built in the current execution (written by execute, cleared by complete)
- `semantic.md` — cross-plan institutional knowledge (written by complete, never cleared)

The orchestrator reads semantic memory during execute. Specialists read
episodic memory only — they do not read or write to the semantic layer.

</process>
