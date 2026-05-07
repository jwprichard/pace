---
name: pace:complete
description: Closes out a completed plan — full PROJECT.md refresh and .pace/ runtime cleanup
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Agent
---

<objective>
Close out a completed plan cleanly. Refresh the project map with a full rescan,
then delete runtime files that belong to this plan only. For roadmap phases,
handle PR creation, merge, and phase advancement automatically.

Preserve the persistent .pace/ artifacts (PROJECT.md, AGENT-REGISTRY.md, agents/).
Delete only the plan-specific runtime files.
</objective>

<process>

> **Agent spawning rule:** Every `Agent` spawned in this command must use `dangerouslySkipPermissions: true`.

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

### Session UUID

Scan STATE.md for a line matching `_Session: {uuid}_` (italicised metadata line written
by `/pace:plan`). Extract the UUID value and store it as `session_uuid`.

Also derive the encoded project path used by Claude Code's session store. Run:
```bash
pwd | sed 's|/|-|g' | sed 's|^-||'
```
Store the result as `encoded_project_path`.

If the `_Session:` line is absent, log a warning and set `session_uuid = null`:
```
Warning: No session UUID found in STATE.md. Token usage for this phase will not be recorded.
```

Make all usage recording in this command conditional on `session_uuid` being non-null.

### Model override

If `.pace/settings.md` exists, read it and look for an `execute-model:` line in the
`## Model` section. If the line has a non-empty value (e.g. `execute-model: sonnet`),
store that value as the **model override** for all specialist agent spawns during
this command.

If the file does not exist, the `execute-model:` line is missing, or its value is
blank (e.g. `execute-model:` with nothing after it), no model override is used —
agents will inherit the session model as normal.

The orchestrator's own model is never changed by this setting.

> **How to pass the model override:** `model` is a top-level parameter on the Agent tool,
> not text inside the prompt. Correct usage:
> `Agent(description: "...", prompt: "...", model: "{model_value}")`

### Phase detection

If `.pace/PLAN.md` exists, read the header lines and look for a `_Phase: {N}_` marker.
If found, set `roadmap_phase = {N}`. Otherwise set `roadmap_phase = null`.

Also check the current branch:
```bash
git branch --show-current
```
Store the result as `current_branch`.

## Step 2 — Synthesise episodic memory into semantic memory

If `.pace/memory/episode.md` does not exist, skip this step.

Read `.pace/memory/episode.md`.
Read `.pace/memory/semantic.md` if it exists (may be absent on first completion).

If a **model override** was read in Step 1, set the `model` parameter to `{model_value}` on
the Agent tool call. When no model override is set, omit the `model` parameter
entirely so the agent inherits the session default.

Spawn an agent using the Agent tool with `dangerouslySkipPermissions: true` and this prompt:

---
You are synthesising episodic memory into long-term semantic memory for a PACE project.

## Episodic Memory (this plan's execution log)

{full contents of .pace/memory/episode.md}

## Existing Semantic Memory

{full contents of .pace/memory/semantic.md, or "Empty — this is the first completion."}

## Your Task

Extract from the episodic memory anything worth remembering long-term:
- Architectural decisions that were made and why
- Patterns or conventions that were introduced or confirmed
- Lessons learned or problems encountered
- Dependencies or integrations added

Do NOT include:
- Task-specific implementation details (what line of code was changed)
- Ephemeral state (file was created, then deleted)
- Anything already present in the existing semantic memory

Append your findings to `.pace/memory/semantic.md` using this format:

```markdown
## {Plan title} — {ISO date}

### Decisions
- {decision} _(rationale)_

### Patterns
- {pattern}

### Lessons
- {lesson}
```

If there is nothing worth adding, write nothing — do not append empty sections.

Allowed tools: Read, Write
---

Wait for the task to complete.

If `session_uuid` is non-null, record the semantic memory agent's usage:
```bash
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} | \
  bash ~/.claude/lib/pace/append-usage.sh complete memory-synthesis memory-synthesiser
```

## Step 3 — Refresh PROJECT.md

If a **model override** was read in Step 1, set the `model` parameter to `{model_value}` on
the Agent tool call. When no model override is set, omit the `model` parameter
entirely so the agent inherits the session default.

Spawn `pace-documentation-specialist` using the Agent tool in full mode:

---
Full mode. The current plan has just completed.

Run a fresh codebase scan and rewrite `.pace/PROJECT.md` entirely.
Capture the current commit hash and timestamp.
---

Wait for the task to complete.

If `session_uuid` is non-null, record the documentation specialist's usage:
```bash
python3 ~/.claude/lib/pace/token-usage.py aggregate {session_uuid} {encoded_project_path} | \
  bash ~/.claude/lib/pace/append-usage.sh complete doc-refresh documentation-specialist
```

## Step 3b — PR, merge, and phase advancement (roadmap phases only)

If `roadmap_phase` is `null`, skip this step entirely.

If `roadmap_phase` is set:

### Create PR

Check if a PR already exists for the current branch:
```bash
gh pr view --json number 2>/dev/null
```

If no PR exists, create one. Gather context for the PR body:
- Read `.pace/requirements/brief.md` (if exists) for what was requested
- Read `.pace/PLAN.md` for the objective and task list
- Read `.pace/STATE.md` for task completion status
- Read `.pace/memory/episode.md` (if exists) for what was built
- Run `git log main..HEAD --oneline` for the commit list

Create the PR:
```bash
gh pr create --title "{plan title}" --body "$(cat <<'EOF'
## Summary
{2-3 sentence summary of what this phase delivered}

## Tasks completed
{task list from STATE.md with status markers}

## Commits
{commit list}

---
🤖 Generated with [PACE](https://github.com/jwprichard/pace) — Plan, Assign, Coordinate, Execute
EOF
)"
```

If `gh` is not available, tell the user:
```
gh CLI not found. Create a PR manually for branch {current_branch}, then run /pace:complete again.
```
Then stop.

### Merge PR

Attempt to merge:
```bash
gh pr merge --squash --delete-branch
```

If the merge fails (e.g., branch protection requires reviews), tell the user:
```
PR created but could not be auto-merged (likely requires review).
Merge the PR manually, then run /pace:complete again to finish cleanup.
```
Then stop.

### Switch to main

After successful merge:
```bash
git checkout main
git pull origin main
```

### Update ROADMAP.md

Read `.pace/ROADMAP.md`. Change Phase {roadmap_phase}'s `**Status:** in_progress`
to `**Status:** complete`.

Check if any phases still have `**Status:** pending`:
- If yes: store `next_phase = {next pending phase number and title}`
- If no: store `next_phase = null` (roadmap complete)

## Step 4 — Clean up runtime files

Delete the plan-specific runtime files:

```bash
rm -f .pace/PLAN.md
rm -f .pace/STATE.md
rm -f .pace/memory/episode.md
rm -rf .pace/requirements/
rm -rf .pace/drafts/
```

Do NOT delete:
- `.pace/PROJECT.md` — preserve (just refreshed)
- `.pace/AGENT-REGISTRY.md` — preserve (registry is persistent)
- `.pace/agents/` — preserve (registry tier 2 files)
- `.pace/memory/semantic.md` — preserve (persistent cross-plan knowledge)
- `.pace/usage.md` — preserve (usage data must persist for `/pace:create-pr` to read; cleared by the next `/pace:plan` run)

## Step 5 — Confirm

If `roadmap_phase` is `null` (standalone plan):

```
Plan closed.

Episodic memory synthesised into semantic memory.
PROJECT.md refreshed with latest codebase state.
Runtime files cleaned up (PLAN.md, STATE.md, episode.md, requirements/, drafts/).

Ready for the next plan. Run /pace:plan to start.
```

If `roadmap_phase` is set and `next_phase` exists:

```
Phase {roadmap_phase} complete. PR merged to main.

Episodic memory synthesised into semantic memory.
PROJECT.md refreshed with latest codebase state.
Runtime files cleaned up.

Next up: Phase {next_phase number} — {next_phase title}
Run /pace:plan to start planning it.
```

If `roadmap_phase` is set and `next_phase` is `null`:

```
Phase {roadmap_phase} complete. PR merged to main.
All roadmap phases are now complete.

Episodic memory synthesised into semantic memory.
PROJECT.md refreshed with latest codebase state.
Runtime files cleaned up.
```

</process>
