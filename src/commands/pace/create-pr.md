---
name: pace:create-pr
description: Creates a PR from the PACE workflow — summarising what was requested, what was delivered, and what was verified
argument-hint: "[--auto-review]"
allowed-tools:
  - Read
  - Bash
  - Glob
---

<objective>
Generate a pull request that gives the reviewer a clear picture of what was asked
for, what was built, and what verification found. Pull the data from PACE runtime
files — requirements brief, PLAN.md, STATE.md, VERIFICATION.md, and episodic
memory — and compile it into a structured PR body.

Optionally tag the PR with `@claude review` to trigger automated review.
</objective>

<process>

## Stage 0 — Parse Flags

Read the full argument string.

- If the argument contains `--auto-review`: set `auto_review = true`, strip the flag
- Otherwise set `auto_review = false`

## Stage 1 — Pre-flight

### Check 1: Git state

Run:
```bash
git status --porcelain
```

If there are uncommitted changes, warn:
```
Warning: You have uncommitted changes. The PR will be created from the current
branch state. Consider committing first.
```
Continue — this is a warning, not a blocker.

### Check 2: Branch

Run:
```bash
git branch --show-current
```

If the branch is `main` or `master`, stop:
```
You are on the default branch ({branch}). Create a feature branch first.
```

Store the branch name as `{branch}`.

### Check 3: Remote tracking

Run:
```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
```

If this fails (no upstream), the branch needs pushing. Store `needs_push = true`.
Otherwise store `needs_push = false`.

### Check 4: PACE artifacts

Read `.pace/STATE.md`. If it does not exist, stop:
```
No STATE.md found. Run the PACE workflow first (/pace:plan → /pace:execute).
```

Check `## Status` in STATE.md:
- If `in_progress` → warn: "Plan is still in progress. PR will reflect partial work."
- If `blocked` → warn: "Plan has blocked tasks. PR will reflect partial work."
- If `complete` → proceed without warning

## Stage 2 — Gather context

Read the following files. If a file does not exist, note it as unavailable and
continue — the PR body adapts to what is available.

1. `.pace/requirements/brief.md` — what was requested
2. `.pace/PLAN.md` — the plan (objective, task list)
3. `.pace/STATE.md` — task completion status
4. `.pace/VERIFICATION.md` — verification findings (may not exist if verify hasn't run)
5. `.pace/memory/episode.md` — execution log of what agents built

Also gather git context:

```bash
git log main..HEAD --oneline
```

Store the commit list as `{commits}`. If `main` doesn't exist, try `master`.
If neither works, use `git log -20 --oneline` and note that the diff base is approximate.

## Stage 3 — Build PR body

Compile the PR body using this structure. Adapt each section based on what data
is available — omit sections cleanly when the source file is missing rather than
showing "N/A" placeholders.

```markdown
## What was requested

{Content from .pace/requirements/brief.md — the What, Success criteria, Domain,
Constraints, and Scope sections. Reproduce faithfully but trim any verbose
research sections down to a bullet summary.}

## What was delivered

{From PLAN.md objective + STATE.md task list. Show each task with its status
marker and agent:}

- [x] Task 1: {title} — @{agent}
- [x] Task 2: {title} — @{agent}
- [ ] Task 3: {title} — @{agent} _(incomplete)_

{If episode.md exists, add a brief narrative summary (3-5 sentences max)
of what was actually built, synthesised from the episodic memory. Do not
dump the raw episode log.}

## What was checked

{If VERIFICATION.md exists: show the verdict and a summary of what was
verified. List any criteria that failed.}

{If VERIFICATION.md does not exist:}
> Verification has not been run. Consider running `/pace:verify` before merging.

## Commits

{commit list from git log}

---
🤖 Generated with [PACE](https://github.com/jwprichard/pace) — Plan, Assign, Coordinate, Execute
```

### PR title

Derive the PR title from the PLAN.md objective line. Keep it under 70 characters.
If the objective is too long, summarise it.

## Stage 4 — Push and create PR

If `needs_push = true`:
```bash
git push -u origin {branch}
```

Create the PR:
```bash
gh pr create --title "{pr_title}" --body "$(cat <<'EOF'
{compiled PR body}
EOF
)"
```

If `gh` is not available, fall back to displaying the PR body and telling the
user to create the PR manually:
```
gh CLI not found. Here is the PR body — create the PR manually:

{PR body}
```

## Stage 5 — Auto-review (optional)

If `auto_review = true`:

Get the PR number from the `gh pr create` output, then post a review-trigger comment:
```bash
gh pr comment {pr_number} --body "@claude review"
```

Tell the user:
```
PR created: {pr_url}
Automated review triggered via @claude review comment.
```

If `auto_review = false`:
```
PR created: {pr_url}
```

</process>
