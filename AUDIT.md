# PACE Audit — Findings & Proposals

_Audit date: 2026-07-23. Scope: full read of all 15 commands, 4 agents, 3 lib scripts, installers, docs, examples, and live `.pace/` runtime state; every seed finding independently re-verified; key claims tested empirically (see Method). No code has been changed._

---

## Summary

Five things matter most — plus one maintainer-reported UX defect taken as first priority: **the plan-approval question arrives without the plan being displayed** (F0; the "present in full" step is structurally skippable and needs a hard gate). Beyond that: **(1) The token-usage pipeline double-counts** — every recording re-appends every subagent seen so far in the session, so a 6-task plan reports roughly 3× its true cost and the PR-embedded numbers are wrong; this was proven by running `append-usage.sh` against simulated aggregate output. **(2) The documented lifecycle is impossible to follow**: `/pace:complete` deletes `STATE.md`, then `/pace:create-pr` — which docs say to run next — hard-stops without it. **(3) Several commands physically cannot do what they say**: `resume.md` has only `Read` but must execute; `verify.md` lacks `Bash`/`Edit` for steps it performs; every command instructs a `dangerouslySkipPermissions` Agent-tool parameter that does not exist in Claude Code. **(4) The fix/amend subsystem is internally broken**: structured fixes are never committed, `fix` marks the whole plan complete while original tasks are pending, and "deferred" amendments can never actually run because `/pace:execute`'s heading matcher doesn't know their heading format. **(5) The swarm→single-agent migration left a trail of stale artifacts** — RISKS.md, the committed `.pace/PROJECT.md`, settings comments, the registry (which still routes to the deleted `@pace-synthesiser`), and sample files. Everything above is mechanical to fix; none of it requires changing a design principle.

---

## Method

- Read every file in the repo in full (commands, agents, libs, docs, examples, `.pace/` runtime).
- Verified each seed finding from the brief independently; line numbers below are from the current worktree.
- **Empirical tests** on this machine:
  - Ran `append-usage.sh` twice against simulated `aggregate` JSON (task 1a, then 1a+1b as the session accumulates) — the resulting `usage.md` contains task 1a's tokens **twice** (finding F1).
  - Inspected `~/.claude/projects/` — the session/subagent JSONL layout (`agent-*.jsonl` + `.meta.json` with `agentType`) matches `token-usage.py`'s assumptions, and `find-session.sh`'s path encoding matches Claude Code's (including worktrees). The lib scripts' structural assumptions are sound; the defect is purely the missing dedup.
  - Confirmed `~/.claude/agents/pace/` contains the four PACE agents → next `/pace:sync-agents` will index them as a routable division (F17).
- Checked PACE's conventions against current Claude Code documentation (code.claude.com): command/agent frontmatter fields, Agent-tool parameters, argument substitution, skills-vs-commands status.
- External research on comparable spec-driven tools (see Capability Gaps section).

**A note on severity for a prompt-code repo:** "Critical" here means *the feature's core promise is broken or the documented workflow cannot be completed* — even though nothing crashes, an LLM following these instructions produces wrong results or dead-ends the user.

---

## Bucket 1 — Fixes (clear defects; low controversy)

Ranked by severity × leverage ÷ effort. F0 is placed first at the maintainer's request.

### F0. Plan approval is requested without the plan being shown — **High (maintainer-reported)**, effort S

**Evidence:** `plan.md:459-461` — "read `.pace/PLAN.md` and present it to the user in full. Then use the AskUserQuestion tool…". Maintainer reports the approval question arrives *without* the plan. Two compounding causes: (1) the presentation is ordinary assistant text emitted **between tool calls** (Read → present → AskUserQuestion), which Claude Code renders least reliably mid-turn; (2) after a long planning flow an LLM readily compresses "present it in full" into a summary or skips straight to the question — there is no structural gate forcing the display to happen first. The identical fragile pattern exists at `roadmap.md:367-369` (present ROADMAP.md → ask) and `verify.md:127` ("Display the verification report in full" → ask).

**Why it matters:** Approval is PACE's single human checkpoint; approving an unseen plan defeats the entire spec-driven premise.

**Proposed fix:** Restructure Stage 5 into explicitly ordered, gated sub-steps: **5a** — output the full contents of `.pace/PLAN.md` in the reply (verbatim, rendered as markdown — plus a one-line pointer to the file path); **5b** — *only after 5a's text has been produced*, call AskUserQuestion, and restate in the question header where the plan was just displayed ("Full plan shown above — how would you like to proceed?"). Add a hard rule: "Never call AskUserQuestion for plan approval in a reply that does not contain the plan text." Apply the same 2-step gate to `roadmap.md` Stage 4 and `verify.md` Step 3. **Risk:** none — pure sequencing/prompt hardening.

### F1. Token-usage recording double-counts every prior agent — **Critical**, effort M

**Evidence:** `src/lib/token-usage.py:206-248` (`cmd_aggregate` globs **all** `agent-*.jsonl` under the session and emits one row per subagent, cumulatively); `src/lib/append-usage.sh:141-170` (emits a row for every subagent in the JSON, no comparison against rows already in `usage.md`); `src/commands/pace/execute.md:285-303` (runs this after **every** task).

**Why it matters:** After task N, the recording re-appends rows for all N agents spawned so far, labelled with task N's ID. Empirically verified: recording task 1b produced a second row of task 1a's agent tokens. Over a plan, rows grow O(N²) and the reported cost inflates ~(N+1)/2×. `/pace:usage` and the PR-embedded cost table — the flagship observability feature — systematically over-report. `docs/architecture.md:177` claims append-usage "deduplicates entries already recorded", which the code does not do (the `message.id:requestId` dedup at `token-usage.py:130-158` only dedups retries *within* one JSONL, not against previously recorded rows).

**Proposed fix:** Make recording incremental and idempotent. Cleanest: a ledger of consumed subagent files — `aggregate` gains a `--exclude-file <path>` (or `append-usage.sh` maintains `.pace/.usage-cursor` listing `agent-*.jsonl` stems already recorded and filters incoming rows against it). Orchestrator-facing behaviour and the command prose stay identical. Also fold in F13 (quoting) and correct `docs/architecture.md`. **Risk:** low — the pipeline is already non-blocking by design.

### F2. Documented lifecycle is impossible: `/pace:complete` destroys what `/pace:create-pr` requires — **Critical**, effort S–M

**Evidence:** `src/commands/pace/complete.md:277-282` deletes `PLAN.md`, `STATE.md`, `episode.md`, `requirements/`; `src/commands/pace/create-pr.md:90-93` hard-stops without `STATE.md` (and builds its body from PLAN/brief/episode — all gone). Docs order complete → create-pr: `docs/README.md:33` (`CP` then `PR` via `complete --> createpr` in `docs/architecture.md:33`), `docs/getting-started.md:175-189`.

**Why it matters:** For standalone (non-roadmap) plans the documented final step always dead-ends. (Roadmap phases dodge it because `complete` creates the PR itself.)

**Proposed fix (pick one, my recommendation first):** (a) Re-order the documented lifecycle to verify → **create-pr** → complete, and have `complete` warn if the branch has no PR yet; or (b) have `complete` archive plan artifacts to `.pace/archive/{plan-slug}/` instead of deleting, and point `create-pr` there as fallback; or (c) fold PR creation into `complete` for standalone plans too. (a) is the smallest, least-surprising change. **Risk:** low; docs + one warning branch.

### F3. Phantom `dangerouslySkipPermissions` parameter instructed on every Agent spawn — **High**, effort S

**Evidence:** 20 occurrences across 9 command files (e.g. `plan.md:24`, `execute.md:27`, `fix.md:34`, `roadmap.md:25`, `scan.md:18`, `verify.md:19`, `amend.md:37`, `complete.md:23`, `agent.md:22`).

**Why it matters:** Current Claude Code documentation confirms the Agent tool has no such parameter (valid inputs: `description`, `prompt`, `subagent_type`, `model`, `run_in_background`, …). Subagent permissions are inherited from the session / set via `permissionMode` in the agent definition. At best the orchestrator silently drops it; at worst the tool call fails validation. Either way, every command's very first rule is an instruction the LLM cannot follow — which trains it to treat other instructions loosely.

**Proposed fix:** Delete the rule from all 9 files. If frictionless spawning is the goal, document the supported route instead (run the session in `acceptEdits`/bypass, or add `permissionMode` to the four PACE agent definitions). **Risk:** none — the parameter never worked.

### F4. `resume.md` cannot do what it says (seed finding, confirmed) — **High**, effort S

**Evidence:** `src/commands/pace/resume.md:5-6` grants `allowed-tools: [Read]`; lines 59-64 say "proceed exactly as `/pace:execute` would" — spawn agents, edit STATE.md, run git commits.

**Proposed fix:** Make it genuinely thin: after the status checks, instruct the user to run `/pace:execute` (its stated objective already says execute handles resume natively). Alternatively grant the full execute toolset — but that duplicates execute's contract in a second file, which is the disease, not the cure. **Risk:** none.

### F5. `verify.md` missing `Bash` and `Edit`; `execute.md` missing `Write`; `scan.md` missing `Read` — **High**, effort S

**Evidence:** `verify.md:4-8` grants `[Read, Agent, AskUserQuestion]` but Step 1 runs `find-session.sh`/`printf` (Bash) and edits STATE.md's `_Session:` line (Edit), and Steps 2/4/5 run usage-recording bash. `execute.md:4-11` has no `Write`, but Stage 3d must *create* `.pace/memory/episode.md` (Edit can't create files). `scan.md:4-7` grants `[Bash, Agent]` but Step 2 reads `settings.md` and Step 1 reads package files ("check, then read").

**Why it matters:** Same defect class as F4 — the command's own steps are unexecutable with its grants; behaviour degrades to permission prompts or silent skips depending on session mode.

**Proposed fix:** `verify.md` += Bash, Edit; `execute.md` += Write; `scan.md` += Read. While there, sweep all 15 files for grant/step mismatches. **Risk:** none.

### F6. Structured and light fixes are never committed — **High**, effort S

**Evidence:** `fix.md` has no commit step in either mode (compare `amend.md:272-287` L7 and `amend.md:515-540` Stage 8, which both commit). The fix-agent prompts (`fix.md:151-183`, `364-392`) also never request a `## Files Modified` section, so there is nothing to stage from.

**Why it matters:** Breaks the "each task committed" invariant. Fix changes sit uncommitted; the next command that hits the `git add -A` fallback sweeps them into an unrelated commit with a wrong message.

**Proposed fix:** Mirror amend's commit steps into fix (both modes) and add the `## Files Modified` requirement to fix-agent prompts. **Risk:** low.

### F7. `/pace:fix` marks the plan `complete` even when original tasks are pending — **High**, effort S

**Evidence:** `fix.md:253-256` allows queuing fixes while status is `in_progress` ("they'll be appended after the existing tasks" — which Stage 6 then contradicts by dispatching immediately); `fix.md:465` then unconditionally sets `## Status` to `complete`.

**Why it matters:** A plan with pending tasks gets its status wiped to `complete`; `/pace:execute` then refuses to continue ("plan is already finished") and `/pace:complete` will happily close out a half-done plan.

**Proposed fix:** In Stage 8, set status back to what pre-flight found (or `complete` only if no `[ ]`/`[~]`/`[!]` tasks remain). Also reconcile the Stage 1 wording with Stage 6's actual dispatch-now behaviour. **Risk:** low.

### F8. Deferred amendments (and blocked fixes) can never be executed by `/pace:execute` — **High**, effort M

**Evidence:** `amend.md:442-449` defers dependent amendments to "the next `/pace:execute` or `/pace:resume`"; but `execute.md:105-121` builds the run order from PLAN.md's `## Implementation Order` (A/F tasks aren't in it — triggering the warn-and-fallback path at best), and `execute.md:155-158` extracts task context by matching the heading `### {id}. {title}` — while amendments are written as `### Amendment {N}: {title}` (`amend.md:405-416`) and fixes as `### Fix {N}: {short title}` (`fix.md:316-327`).

**Why it matters:** The handoff amend promises structurally cannot happen: execute either skips the task or fails to find its block, with no defined behaviour.

**Proposed fix:** Teach `execute.md` Stage 2/3b the two extra section types: run order = Implementation Order, then pending `F{N}`/`A{N}` in numeric order; heading matchers `### Fix {N}:` / `### Amendment {N}:` mapped from the `F`/`A` ID prefix. One paragraph in execute.md; no format changes elsewhere. **Risk:** low-medium (touches execute's core loop — needs a careful re-read pass).

### F9. Blocked-state recovery is circular — no command can actually unblock a plan — **High**, effort S–M

**Evidence:** `resume.md:37-44` (blocked → "fix the issue, then run `/pace:resume`" — which re-shows the same blocker forever); `status.md:91-94` (same advice); `execute.md:38-40` says "ask whether they want to retry or skip" but nothing anywhere says how to reset `[!]` → `[ ]` or `blocked` → `in_progress`, and `execute.md:113-114` marks `[!]` as "stop — surface to user" in the very parsing table the retry would rely on.

**Why it matters:** The failure path — the one place users most need clear instructions — dead-ends. An orchestrator LLM will improvise, differently each time.

**Proposed fix:** Define recovery once, in `execute.md` pre-flight: on `blocked`, ask retry/skip (grant `AskUserQuestion`); *retry* = flip that task `[!]`→`[ ]`, clear its blocker line, set status `in_progress`, continue; *skip* = leave `[!]`, exclude from run order, continue, and report it as skipped at the end. Point `resume.md`/`status.md` at `/pace:execute` for the blocked case. **Risk:** low.

### F10. `--local` installs have dead lib paths — usage tracking and session detection silently never work — **High**, effort S–M

**Evidence:** `install.sh:162-174` installs lib scripts to `$DEST/lib/pace/` (i.e. `./.claude/lib/pace/` for `--local`), but every command references the global path only: `bash ~/.claude/lib/pace/find-session.sh` (`plan.md:180`, `execute.md:47`, `verify.md:43`, `fix.md:65`, `amend.md:68`, `complete.md:44`, plus all `token-usage.py`/`append-usage.sh` calls).

**Why it matters:** A team doing the documented project-scoped install (`docs/README.md:70-74`) without a parallel global install gets zero token tracking and zero session detection — all silently, because every call site is "non-blocking, continue on failure".

**Proposed fix:** Resolve once: prefer `./.claude/lib/pace/` if present, else `~/.claude/lib/pace/`. Best done inside the shared preflight/recording script proposed in I1 so it's written once, not nine times. **Risk:** low.

### F11. `pace-planner`'s tool restriction is silently ignored (wrong frontmatter key) — **Medium**, effort S

**Evidence:** `src/agents/pace/pace-planner.md:4-8` uses `allowed-tools:` — a *command* field. Agent frontmatter uses `tools:` (confirmed against current sub-agents docs). The other three PACE agents declare no tool restriction at all but do declare `emoji:`/`vibe:`, which are not recognized fields.

**Why it matters:** The planner runs with **all tools** (including Bash, Agent, Write-anywhere) despite the file's clear intent to restrict it. And CONTRIBUTING.md (`docs/CONTRIBUTING.md:104-124`) tells contributors `color`/`emoji`/`vibe` are *required* agent fields while omitting `tools` — codifying the mistake.

**Proposed fix:** `allowed-tools:` → `tools:` on the planner (add Bash if the inline verification in Step 8 needs it — it doesn't; Read/Write/Glob/Grep suffice). Decide intentionally for the other three agents (verifier arguably should be read-only + Write for VERIFICATION.md + Bash for checks). Fix the CONTRIBUTING.md field table (`emoji`/`vibe` optional decoration at most; document `tools`). **Risk:** low; behaviour only tightens.

### F12. `pace-documentation-specialist` full mode silently drops the `## Services` section — **Medium**, effort S

**Evidence:** analyst writes conditional `## Services` for monorepos (`pace-codebase-analyst.md:82-96, 118-123`) and `pace-planner.md:229-231` depends on it for `**Service:**` fields; but the doc-specialist's full-mode template (`pace-documentation-specialist.md:89-120`) has no `## Services` section and no monorepo detection step, and patch mode's section map (`:55-62`) never mentions it.

**Why it matters:** Every `/pace:complete` on a monorepo erases the Services table; the next plan loses service awareness. (The semantic memory file even records the two-signal rule this violates.)

**Proposed fix:** Add the conditional Services section + two-signal rule to full mode; add "changes to service layout → Services" to patch mode's map. **Risk:** none.

### F13. Usage-recording invocations break on agent names with spaces — **Medium**, effort S

**Evidence:** command templates pass placeholders unquoted, e.g. `append-usage.sh execute {id} {agent}` (`execute.md:292-298`); registry agent names are multi-word (`@Backend Architect`). Word-splitting shifts `Architect` into the `json-file` positional, so `append-usage.sh` exits 1 ("JSON file not found") and the row is silently lost. Same latent hazard in `plan.md:450-453`'s `printf '%s' "{usage_json}"` re-quoting of raw JSON (every other command pipes directly).

**Proposed fix:** Quote all substituted args in every template (`"{agent}"`, `"" "{model_value}"`); align plan.md to the direct-pipe pattern. Subsumed by I1 if adopted. **Risk:** none.

### F14. Stale swarm-era artifacts (seed findings, confirmed and extended) — **Medium**, effort S

**Evidence:**
- `RISKS.md:7-31` — documents wave-based parallel execution and "the synthesiser"; neither exists.
- `.pace/PROJECT.md` (committed) — `:15` "top-level agent definitions (pace-synthesiser)", `:23` ".pace/drafts/ — intermediate draft plans from parallel domain planners", `:28` "/pace:plan — spawns domain planner agents in parallel".
- `.pace/agents/general.md:18` — the registry still lists `@pace-synthesiser` as a routable agent; the agent file was deleted. A planner consulting the registry can assign a task to a nonexistent agent.
- `.pace/settings.md:10-12` (committed) — comments describe "domain planners, synthesiser".
- `.gitignore:5-8` — ignores swarm-era `.pace/DECISIONS.md` and `.pace/drafts/` but none of the current runtime files (`usage.md`, `VERIFICATION.md`, `memory/episode.md`, `requirements/`, `ROADMAP.md`); meanwhile `.pace/requirements/brief.md` is *tracked*, so every `/pace:complete` (which deletes it) dirties the repo.
- `CLAUDE.md:5` — "load `CONTEXT.md`" points at a gitignored, local-only file that doesn't exist for anyone who clones the repo (seed finding; the file is deliberately untracked).

**Proposed fix:** Rewrite RISKS.md around the *current* risks (usage inflation until F1 lands, `git add -A` fallback, session misdetection, LLM heading-parsing); refresh the committed `.pace/PROJECT.md` and settings comments; re-run `/pace:sync-agents` (after F17); update `.gitignore` to current runtime file set; untrack `requirements/brief.md`; qualify the CLAUDE.md pointer ("optional, local-only, not in the repo") or drop it. **Risk:** none.

### F15. `/pace:complete` roadmap path: irreversible git work with no confirmation, dirty main afterwards, `main` hardcoded (seed finding, confirmed) — **Medium**, effort M

**Evidence:** `complete.md:198-271` creates a PR, squash-merges with `--delete-branch`, checks out `main`, pulls — inline, with no user confirmation, and `complete.md:4-9` doesn't even grant `AskUserQuestion` so it *couldn't* ask. After the merge it edits `ROADMAP.md` and deletes `.pace/` files on `main` **without committing** (`:264-282`) — leaving main dirty; the next `/pace:plan` branch inherits the mess. `git checkout main` / `git log main..HEAD` assume `main` (`create-pr.md:120-125` at least falls back to `master`).

**Why it matters:** This is the single most destructive sequence in PACE (squash-merge + branch delete) executed on autopilot, and its aftermath leaves the default branch dirty every time.

**Proposed fix:** Gate the merge behind an AskUserQuestion (merge now / leave PR open); commit the ROADMAP.md status flip (and any non-ignored cleanup) after merge; detect the default branch instead of assuming `main`. Pairs with I3 (`.pace/.gitignore`), which makes the runtime-file deletions invisible to git in user projects. **Risk:** medium — touches the most dangerous path; needs a full trace re-read after editing.

### F16. Interview rules contradict themselves (seed finding, confirmed) — **Medium**, effort S

**Evidence:** `plan.md:280-284` — "Identify **at least 3** genuine unknowns … You must ask a minimum of 3 questions … even if the prompt seems comprehensive" directly against `plan.md:286-288` "**Do not ask about things already answered by the prompt**" and `docs/getting-started.md:93` "It will not ask you things it can already infer". `roadmap.md:219-231` uses a different rule (2–4 questions) and instructs adding an "Other" option that AskUserQuestion already provides automatically (`roadmap.md:230`).

**Why it matters:** When the prompt is complete, the orchestrator must violate one instruction or the other — it will pad with filler questions (annoying) or skip the minimum (unpredictable). Cross-command inconsistency compounds it.

**Proposed fix:** One rule in both files: "Ask every genuine unknown that materially affects the plan (typically 2–4). If fewer than 2 exist, present your assumptions for confirmation instead of inventing questions." Drop roadmap's redundant "Other". Keep the deeper-dive loop (2c-bis) as is — it's good. **Risk:** low; this is a UX-behaviour change the maintainer should explicitly bless.

### F17. PACE's own agents pollute the routing registry — **Medium**, effort S

**Evidence:** PACE installs its agents to `~/.claude/agents/pace/` (`install.sh:156-159`); `sync-agents.md`'s scanner (`:35-36`) skips only `examples`/`integrations`/`strategy`, so the next sync creates a routable `pace` division — `examples/sample-registry.md:12` already shows exactly that ("pace | 4 | Codebase analysis…").

**Why it matters:** The planner's contract is "these are the only valid agent names" (`pace-planner.md:26-27`); offering it PACE-internal agents invites routing implementation tasks to the verifier or doc-specialist.

**Proposed fix:** Add `"pace"` to `SKIP_TOP_DIRS` in sync-agents; regenerate `examples/sample-registry.md` without the pace row; re-sync the dogfood registry (also clears the stale `@pace-synthesiser`, F14). **Risk:** none — PACE agents are always spawned by explicit name, never via registry lookup.

### F18. Small mechanical defects — **Low**, effort S (batch)

- `status.md:37` extracts the plan title from "the `# {title}` heading" — STATE.md's h1 is the literal `# STATE`; the title lives in `_Plan:_` (`plan.md:481-483`). Status would display "STATE" as the plan name.
- `sync-agents.md:4` advertises `[--force]`; the body never mentions it. Remove (or implement).
- `examples/sample-state.md` uses numeric task IDs (`1`, `2`, `4`), agents that don't match `sample-plan.md`, and a `## Completed` line format matching neither `plan.md:481-501` nor `execute.md:256-261`. Regenerate from the current formats.
- `append-usage.sh:192` — `grep -qF "## Complete"` is a substring match; a line like `## Completed tasks` in `usage.md` would satisfy it while the awk exact-match insert then silently drops the row. Use `grep -qxF`.
- `complete.md:85-86` reads `_Phase:` from PLAN.md correctly *before* deleting it — fine — but the roadmap-phase PR body (`complete.md:220-233`) omits the Token Usage summary that `create-pr.md:166-170` includes. Unify by piping `token-usage.py format summary` into complete's PR body too.
- `VERIFICATION.md` is never cleaned up: `complete.md:277-289` and plan's `--abandon` (`plan.md:131-137`) both leave it behind; a stale failure report then feeds `fix.md:107`/`267-270` context in the *next* plan. Add it to both cleanup lists.
- `agent.md:24-35` "agent name is the first 1–3 words" (seed finding) — replace with: quoted name, or greedy match against the registry (read `AGENT-REGISTRY.md`, match longest prefix against known names; ask if no match). agent.md never validates the name today.
- Commands never use `$ARGUMENTS`: arguments are auto-appended when no placeholder exists, so the prose pattern works, but the documented-reliable form is the explicit placeholder. Add `$ARGUMENTS` to the argument-taking commands' first line ("The argument string: $ARGUMENTS").
- Command frontmatter `name:` fields (`plan.md:2` etc.) are not a supported field — names come from the file path. Harmless; keep or drop, but CONTRIBUTING.md (`:70-77`) should stop calling it required.
- `token-usage.py:47-66` — unknown model families (e.g. a future default) silently price as sonnet (`:90`). Emit `unknown` pricing as $0.00 with a footnote row, or at least keep — but document the fallback. Low.

---

## Bucket 2 — Improvements (within the current architecture)

### I1. Consolidate the duplicated pre-flight/usage machinery into lib scripts — **High leverage**, effort M

This is the answer I propose to the brief's DRY question. The three copy-pasted blocks — model-override reading (9 files), session-UUID detection (6 files), encoded-path derivation (6 files), and the with/without-override usage-recording pair (~14 sites) — should not be deduplicated with prose pointers (a referenced doc isn't reliably loaded at runtime) but by **moving the mechanics into the scripts and shrinking the prose to one call each**:

- `lib/pace/preflight.sh [plan|execute]` → prints one JSON object: `{session_uuid, encoded_path, model_override}` (reads `.pace/settings.md` itself, resolves local-vs-global lib per F10). Command prose becomes: *"Run `preflight.sh execute`; capture the three fields; if `model_override` is non-empty pass it as the Agent tool's `model` parameter."*
- `lib/pace/record-usage.sh <phase> <task> <agent> [model]` → internally runs find-session + aggregate + dedup-filter (F1) + append, fully quoted (F13), silently no-ops when session detection fails. Every usage-recording site becomes one line, and the with/without-override branching disappears (empty model = no override).

This removes ~350 lines of near-identical instruction prose across 9 files, eliminates the live divergence risk the brief called out, and fixes F1/F10/F13 at their root. Document the pattern in CONTRIBUTING.md. **Risk:** medium — every command changes at once; mitigate by tracing each command end-to-end after the edit (validation plan below).

### I2. Replace the `git add -A` fallback with a working-tree diff snapshot — effort S–M

`execute.md:247-252` / `amend.md:282-287`'s fallback can sweep unrelated dirty files into a task commit (seed finding). Since execution is strictly sequential, the dispatcher can snapshot `git status --porcelain` before the spawn and stage **only paths that changed during the task** (post-run status minus pre-run dirty set), keeping `## Files Modified` as the primary source and demoting `-A` entirely. Also covers agents that forget the section (the exact case the fallback exists for).

### I3. Auto-manage `.pace/.gitignore` — effort S

PACE creates `.pace/` in user repos but never tells git what's runtime vs persistent; docs push that burden to users (`docs/README.md:193`). Have `/pace:scan` (and the inline scans) write `.pace/.gitignore` once: ignore `PLAN.md`, `STATE.md`, `usage.md`, `VERIFICATION.md`, `memory/episode.md`, `requirements/` — keep registry, PROJECT.md, settings.md, memory/semantic.md visible. Kills the F15 dirty-main aftermath in user projects and the "which files do I commit?" question.

### I4. A self-check script for the repo (the missing test suite) — effort M

A `scripts/check.sh` that mechanically enforces what this audit found by hand: every tool referenced in a command body appears in its `allowed-tools`; every `bash ~/.claude/lib/pace/...` target exists in `src/lib/`; heading formats referenced by one file exist in the writer's template (e.g. execute's `### {id}. {title}` vs planner/fix/amend templates); `shellcheck` + `python3 -m py_compile` on libs; no `dangerouslySkipPermissions` regressions. Cheap to run in CI; converts this audit's cross-file invariants into guardrails. (This is how a prompt-code repo gets a test suite.)

### I5. Semantic-memory hygiene at synthesis time — effort S

`.pace/memory/semantic.md` is append-only and already contains statements that are now false ("planners and synthesiser both respect this"; "session UUID captured once … subsequent commands read it from there" — contradicted by the re-detect change). Since the whole file is already in the synthesis prompt (`complete.md:107-149`), extend that prompt: *"If an existing entry is contradicted by this plan's changes, rewrite or delete it — semantic memory must describe the present."* Also refresh the current file's stale entries once, manually.

### I6. Registry Tier-1 "Covers" summaries are noisy — effort S

`sync-agents.md:116-127`'s first-clause heuristic produces fragments like "collecting," and "Terminal emulation," (visible in the live `.pace/AGENT-REGISTRY.md:13,16`). Cheap improvement: take the first sentence up to ~80 chars instead of comma-splitting, and drop empty/stopword fragments. Cosmetic but this is the planner's primary routing signal.

### I7. Record usage for the remaining spawning commands — effort S

`/pace:roadmap`, `/pace:scan`, `/pace:agent` spawn agents but record nothing, so `/pace:usage` under-reports real plan-cycle cost (roadmap especially). With I1's one-liner this becomes trivial; add `roadmap`/`scan`/`agent` to `PHASE_ORDER` in `token-usage.py:374`.

### I8. Capability gaps vs. comparable tools — candidates for a later round, effort varies

Researched GitHub spec-kit, Amazon Kiro, Cline/Roo memory banks, Claude Task Master, and published agent-reliability guidance (12-Factor Agents, GitHub's agentic-primitives post, Anthropic's Building Effective Agents). PACE already embodies several of their core ideas (fresh context per stage, orchestrator-workers, evaluator-optimizer as verify→fix, memory files). The gaps genuinely worth considering:

- **`[NEEDS CLARIFICATION]` markers with an approval gate** (spec-kit): instead of the planner guessing at ambiguities, it marks them inline and the Stage-5 approval presentation must show zero unresolved markers (or surface them as explicit questions). Small change to `pace-planner.md` Step 8 + `plan.md` Stage 5; directly attacks silent wrong guesses. *(Effort S — the strongest candidate.)*
- **Brief→task traceability** (Kiro): number the success criteria in `brief.md`; tasks annotate `_Requirements: 1, 3_`; the planner's self-check and `/pace:verify` gain a mechanical coverage test ("every brief criterion maps to ≥1 task"). *(Effort S–M.)*
- **Planner reads the project's own instruction files**: spec-kit's "constitution" concept, adapted — PACE's planner never reads the target repo's `CLAUDE.md`, where teams already state their non-negotiables. One line in the planner prompt. *(Effort S.)*
- **Sync-from-code reconciliation** (Kiro "Sync Files"): after an interrupted session, `/pace:status` trusts STATE.md blindly; an optional flag could have the verifier spot-check `[x]` tasks against the codebase before resuming. *(Effort M.)*
- **EARS-style acceptance criteria** (Kiro): a stricter WHEN/SHALL grammar for success criteria. PACE's "observable, checkable state" guidance is close already; adopt only if verification quality proves insufficient. *(Effort S, low urgency.)*

None of these are in the recommended round-one scope — listed so the roadmap conversation can happen deliberately.

---

## Bucket 3 — Architectural (changes to stated principles)

One proposal filed for completeness, with a recommendation to defer; everything else I examined survives scrutiny.

### A1. Structured task state (would change "State is simple — a single STATE.md, no state machine") — **recommendation: defer**

**Evidence the current principle has costs:** the prose-parsed dual bookkeeping (PLAN.md task blocks + STATE.md checkbox lines + `## Completed` moves) is where a disproportionate share of this audit's defects live — F7 (status wiped), F8 (heading-format mismatch), F9 (no defined `[!]` reset), F18 (title extraction) — and both Task Master and 12-Factor Agents (Factor 5: unify execution state and business state) argue for a single machine-readable status store with a status enum and dependency array, from which any prose view is generated.

**Specific alternative:** `.pace/state.json` (id, title, agent, status enum, depends_on, timestamps) as the single source of truth; STATE.md becomes a generated view or is dropped; a tiny lib script validates transitions and dangling/circular dependencies.

**Migration cost & risk:** touches every lifecycle command; LLM orchestrators are *better* at editing checkbox markdown than at safe JSON surgery, so this may trade visible drift for subtle corruption; and it directly reverses a stated, recently reaffirmed principle.

**Why defer:** F7/F8/F9/F18 are all fixable *within* the markdown design by specifying the line grammar and recovery transitions precisely (they're in Bucket 1). If state bugs persist after round one, this proposal has its evidence; adopting it now would be reversing a principle without first exhausting the cheap fix.

### Considered and not proposed:

- **Sequential-only execution** (the swarm removal): I found no evidence in the current design that sequentiality is hurting outcomes — and it removed the shared-resource conflict class RISKS.md worried about. Re-introducing parallelism would reverse a fresh, deliberate decision without data. Not proposed.
- **Orchestrator never implements**: the ceremony cost for trivial changes is real but already mitigated by `--light` modes and `/pace:agent`. Not proposed.
- **Migrating commands → skills**: Claude Code has folded commands into skills (commands still work; skills add bundled supporting files, `context: fork`, dynamic context injection). This is the natural *eventual* home for PACE — bundled scripts and injected context would dissolve much of the duplication I1 addresses — but it changes the distribution surface for every user and deserves its own cycle after this round stabilises. Flagged for round two, not proposed now.

---

## Recommended round-one scope

**Take:** F0–F18 (all Fixes) + I1 (it's the load-bearing mechanism for F1/F10/F13) + I3 + I5.
**Defer:** I2, I4, I6, I7 (worthy, independent, no urgency), I8 candidates, skills migration, A1.

Sequenced roughly: **F0 first** (maintainer priority, small and isolated), then I1 scripts (F1's dedup + F10's path resolution + F13's quoting land inside them), then the per-command grant/logic fixes (F3–F9, F16), then lifecycle order F2 + F15, then the staleness sweep F11, F12, F14, F17, F18, with docs (`CLAUDE.md`, `docs/*`, examples) updated in the same commits as the behaviour they describe.

Every change stays inside the current architecture and voice; each finding lands as its own commit (or small coherent group), validated by re-reading every touched file end-to-end and tracing the four lifecycle handoffs (plan→execute, execute→verify, verify→fix, complete→create-pr) before the PR.

---

_Waiting for maintainer approval before any implementation. Approve any subset — each finding is independently actionable unless noted (F1/F10/F13 are cleanest inside I1)._
