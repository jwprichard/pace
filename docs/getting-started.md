# Getting Started with PACE

This guide walks you through installing PACE and completing your first full plan cycle — from installation to a merged PR.

**What you will have after completing this guide:**
- PACE installed and connected to your specialist agents
- A scanned project with a codebase map in `.pace/PROJECT.md`
- A completed plan executed by specialist agents
- Optional: model overrides tuned for your cost and quality preferences

**Prerequisites:**
- Claude Code with agent and command support
- Specialist agents installed in `~/.claude/agents/` or `./.claude/agents/` (for example, [Agency Agents](https://github.com/wshobson/agents) or your own custom agents)
- A git repository to work in

If you do not have specialist agents installed, PACE will flag tasks as unroutable rather than falling back to direct implementation. Install agents first.

---

## Step 1: Install PACE

Clone the PACE repository and run the installer from its root directory.

**Global install** — available in all your projects:

```bash
./install.sh
```

**Project-scoped install** — committed to the repo and shared with your team:

```bash
./install.sh --local
```

**Force-overwrite an existing install:**

```bash
./install.sh --force
# or for a local install
./install.sh --local --force
```

The installer copies commands into `~/.claude/commands/pace/` (global) or `./.claude/commands/pace/` (local), agents into the corresponding `agents/` directory, and utility scripts into `lib/pace/`.

After the installer finishes, you will see a list of installed files and a next-steps prompt.

---

## Step 2: Build the Agent Registry

PACE needs to know which specialist agents you have installed. Run this once after installing PACE, and again any time you install, remove, or update agents:

```
/pace:sync-agents
```

This scans `~/.claude/agents/` and `./.claude/agents/`, parses each agent's frontmatter, and writes a two-tier registry:

- `.pace/AGENT-REGISTRY.md` — a division-level index always loaded during planning
- `.pace/agents/{division}.md` — full agent lists per division, loaded only when that division is relevant

The output tells you how many agents were found per division and flags any agent files that could not be parsed.

If you skip this step, `/pace:plan` and `/pace:roadmap` will stop immediately and ask you to run it first.

---

## Step 3: Scan Your Codebase

Before planning, PACE needs a map of your project. Run:

```
/pace:scan
```

This collects the directory tree, commit hash, and any package or config files it finds, then passes everything to the `pace-codebase-analyst` agent, which writes `.pace/PROJECT.md`.

Planning agents use `PROJECT.md` to understand your stack, structure, and conventions. Without it, they plan against nothing — `/pace:plan` will prompt you to run the scan if the file is missing.

You should re-run `/pace:scan` after significant structural changes to your project (new services, moved directories, changed stack). PACE warns you at plan time if `PROJECT.md` is out of date relative to the current commit.

---

## Step 4: Plan Your Work

For standard features and changes, start planning directly:

```
/pace:plan
```

`/pace:plan` conducts a short structured interview — it asks what you are building, what done looks like, and any constraints or scope decisions that are genuinely unclear. It will not ask you things it can already infer from your description.

After the interview, PACE assembles a team of domain planning agents matched to your work, runs them in parallel to produce draft plans, then synthesises the drafts into a single `PLAN.md`. It presents the plan to you for approval before any execution begins.

**Available flags for `/pace:plan`:**

- `--tdd` — adds a testing peer agent to the planning team; all test tasks are inserted as prerequisites before their paired implementation tasks
- `--research` — spawns a web research agent before planning; findings are injected into the planning context as background for the domain agents
- `--abandon` — discards the current in-progress plan and starts fresh; asks for confirmation before deleting anything

You can combine flags: `/pace:plan --tdd --research`.

**For large features that span multiple plan cycles**, use `/pace:roadmap` instead of jumping straight to `/pace:plan`. The roadmap command interviews you about a large initiative, decomposes it into ordered phases, and produces `ROADMAP.md`. Each phase is then planned separately via `/pace:plan`, which reads the next pending phase automatically when a roadmap exists.

```
/pace:roadmap
```

Use `/pace:roadmap` when the work is too large for a single plan — for example, building an entire new service, migrating a stack, or rolling out a multi-sprint feature. If the scope fits in 2–6 tasks, go straight to `/pace:plan`.

---

## Step 5: Execute the Plan

Once a plan is approved, execute it:

```
/pace:execute
```

Each task in the plan is delegated to its assigned specialist agent in a fresh, isolated context. Independent tasks run in parallel; dependent tasks wait for their prerequisites. The orchestrator never implements anything itself — it routes.

As tasks complete, PACE records outcomes in `STATE.md` and patches `PROJECT.md` to reflect what changed.

If the session is interrupted mid-execution, resume from the last incomplete task:

```
/pace:resume
```

**Adding scope mid-execution:**

If you discover extra work that belongs with the current plan, use `/pace:amend`:

```
/pace:amend
```

`/pace:amend` interviews you about the addition, appends tasks to `PLAN.md`, updates `STATE.md`, and dispatches agents immediately. For a quick one-shot addition without structured task tracking, use the `--light` flag:

```
/pace:amend --light add a loading state to the submit button
```

---

## Step 6: Verify the Work

After execution completes, check the work against the plan's success criteria:

```
/pace:verify
```

This spawns the `pace-verification-specialist` agent, which reads `PLAN.md` and checks each task's success criteria against the current codebase state. You get a per-task pass/fail report.

**If verification finds failures**, use `/pace:fix`:

```
/pace:fix
```

`/pace:fix` interviews you about what needs correcting, appends fix tasks to `PLAN.md`, and dispatches agents. For a quick targeted fix without modifying the plan, use the `--light` flag:

```
/pace:fix --light the button text is still "Submit" instead of "Save"
```

After fixes are applied, re-run `/pace:verify` to confirm all criteria pass.

---

## Step 7: Complete the Plan

When verification passes, close out the plan:

```
/pace:complete
```

This reconciles branch state, updates `PROJECT.md` with a full post-execution refresh, archives episodic memory, and prepares for PR creation. When the current plan corresponds to a roadmap phase, it marks that phase as complete in `ROADMAP.md`.

To create a pull request summarising what was planned, built, and verified:

```
/pace:create-pr
```

---

## Optional: Configure Model Overrides

By default, all PACE agents inherit the model of your current Claude Code session. You can override the model independently for planning agents and execution agents.

Run the settings command to view and change your configuration interactively:

```
/pace:settings
```

Or set values directly:

```
/pace:settings set plan-model opus
/pace:settings set execute-model sonnet
```

Settings are saved to `.pace/settings.md` and persist across plan cycles. `/pace:complete` never clears this file.

| Setting | Controls | Accepted values |
|---|---|---|
| `plan-model` | Domain planners, synthesiser, research agents, codebase analyst | `sonnet`, `opus`, `haiku` |
| `execute-model` | Specialist implementers, verification, fix agents, documentation patches | `sonnet`, `opus`, `haiku` |

A common pattern is to run planning on `opus` (where architectural reasoning matters most) and execution on `sonnet` (for faster, cheaper task implementation). The orchestrator session model is never changed by these settings.

To clear an override and revert to session-model inheritance:

```
/pace:settings set plan-model none
```

---

## First-Run Sequence Summary

```
./install.sh              # Install PACE (--local for project-scoped)
/pace:sync-agents         # Build the agent registry
/pace:scan                # Map the codebase
/pace:plan                # Interview + produce PLAN.md
/pace:execute             # Delegate tasks to specialist agents
/pace:verify              # Check work against success criteria
/pace:fix                 # (if needed) Apply targeted fixes
/pace:complete            # Close out the plan
/pace:create-pr           # Open the pull request
```

---

## Checking Plan Status

At any point during or after execution, you can check where things stand without triggering any work:

```
/pace:status
```

This reads `PLAN.md` and `STATE.md` and shows you completed tasks, pending tasks, any blockers, and the suggested next command.

---

## Next Steps

- [Architecture](architecture.md) — how PACE orchestrates agents, tracks state, and routes work
- [CONTRIBUTING.md](CONTRIBUTING.md) — how to add commands, extend agents, and contribute to PACE itself
