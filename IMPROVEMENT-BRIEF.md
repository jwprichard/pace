# Handoff Brief: Audit & Improve PACE

You are taking over an existing, working open-source project called **PACE** and improving it. This is a two-phase engagement:

1. **Audit** — do a deep, open-ended audit of the whole system and produce a ranked findings-and-proposals document.
2. **Implement** — after the maintainer approves a subset of your proposals, implement it.

There is **one mandatory checkpoint**: you present the ranked audit and **wait for the maintainer to approve scope before writing any code**. Do not skip it.

Nothing is off-limits, including PACE's core design principles — but see the "Ground rules" section for how to handle architectural challenges responsibly.

---

## 0. Orient yourself first (do not skip)

You are in the root of the PACE git repository. Before forming any opinion, read the whole system. It is small — a few thousand lines of Markdown and a little Python/Bash — so read it *all*, in full, not in skim:

- `CLAUDE.md` — project instructions and the canonical statement of design principles
- `docs/README.md`, `docs/architecture.md`, `docs/getting-started.md`, `docs/CONTRIBUTING.md`
- Every file in `src/commands/pace/*.md` (15 command files)
- Every file in `src/agents/pace/*.md` (4 agent files)
- `src/lib/token-usage.py`, `src/lib/find-session.sh`, `src/lib/append-usage.sh`
- `install.sh`, `uninstall.sh`
- `examples/*` (sample plan, registry, state)
- `RISKS.md`
- The live runtime state under `.pace/` (this repo dogfoods itself: `PROJECT.md`, `AGENT-REGISTRY.md`, `agents/`, `memory/semantic.md`, `settings.md`, etc.)
- `git log --oneline -30` and skim recent diffs — the project's direction lives in its history

**Critical framing you must internalize before auditing:** the command and agent files are **prompts interpreted by an LLM at runtime**, not code that a compiler checks. A `/pace:plan` "command" is a Markdown instruction sheet that an orchestrator LLM reads and follows, spawning sub-agents (also driven by Markdown instruction sheets). This means:

- "Correctness" = *an LLM following these instructions reliably produces the intended behavior.* Ambiguity, contradiction, and unstated assumptions are real defects even though nothing "breaks the build."
- There is essentially **no automated test suite**. Your validation tools are careful reading, cross-file consistency checking, and — where feasible — actually installing PACE into a throwaay project and running the lifecycle.
- The audience is dual: **human contributors** and the **orchestrator LLM**. A change that reads well to a human but introduces an instruction an LLM will mis-follow is a regression.

---

## 1. What PACE is and what it's trying to achieve (the north star)

PACE — **Plan, Assign, Coordinate, Execute** — is a spec-driven development workflow for Claude Code, distributed as a set of slash-commands and agents you install into `~/.claude/` (global) or `./.claude/` (project-local).

The core problem it exists to solve: **long single-session AI coding runs degrade.** Context fills up, the model loses the thread, quality drops, and one generalist session ends up doing work far outside its competence. PACE's answer is an **orchestrator that never implements** — it interviews, plans, and then delegates each atomic task to a fresh, specialist agent session, committing between tasks so state is durable.

The design principles as currently stated (from `CLAUDE.md`) — treat these as the *current* philosophy to understand deeply, **not** as constraints you must preserve (see Ground rules):

- **Orchestrator never implements.** Every task is delegated to a specialist agent. The orchestrator routes; it doesn't code.
- **One agent per stage.** Planning, execution, and review each run a *single* agent. One planner writes the plan; one specialist executes each task in turn; one verifier checks the work. (This is recent — PACE previously used a multi-agent "swarm" with parallel "waves" and a "synthesiser" that merged draft plans. That was deliberately removed. See commit `ac5f864` "Replace agent swarm with singular agents." Watch for documentation that still describes the old model.)
- **Agent routing is native.** The planner discovers installed agents and assigns an agent to each task at plan time.
- **Bring your own agents.** PACE ships no specialist agents of its own — it routes to whatever is installed (e.g. the wshobson/agents "Agency Agents" set, or the user's own). If nothing fits a task, the planner *flags* it rather than falling back to direct implementation.
- **Tasks are atomic.** One owner, completable in one session, observable success criteria. Plan size is not artificially capped.
- **Execution is sequential.** Tasks run one at a time in a defined Implementation Order, each in a fresh agent context, each committed before the next.
- **State is simple.** A single `STATE.md`, no state machine.
- **Verification is goal-backward.** Success criteria describe what must be *true*, not what was done.

### The lifecycle

`/pace:sync-agents` (build a two-tier registry of installed agents) → `/pace:scan` (map the codebase into `PROJECT.md`) → optionally `/pace:roadmap` (decompose a big initiative into phases) → `/pace:plan` (interview + single planner writes `PLAN.md`) → `/pace:execute` (dispatch each task to its specialist, one at a time, committing between) → `/pace:verify` (evidence-based check against success criteria) → `/pace:fix` / `/pace:amend` (targeted corrections / added scope, each with a `--light` one-shot mode) → `/pace:complete` (synthesize memory, refresh `PROJECT.md`, clean up, advance roadmap phase) → `/pace:create-pr`. Supporting commands: `/pace:status`, `/pace:resume`, `/pace:settings`, `/pace:usage`, `/pace:agent`.

### Key subsystems to understand

- **Two-tier agent registry** — `.pace/AGENT-REGISTRY.md` (Tier 1, division index) + `.pace/agents/{division}.md` (Tier 2, full lists). Built by a Python script embedded in `sync-agents.md`. Exists so the planner doesn't load 100+ agent descriptions at once.
- **Runtime files** under `.pace/` — `PLAN.md`, `STATE.md`, `PROJECT.md`, `ROADMAP.md`, `settings.md`, `usage.md`, `memory/episode.md` (per-plan), `memory/semantic.md` (cross-plan, never cleared), `requirements/brief.md` + `research.md`.
- **Token-usage tracking** — `find-session.sh` locates the session UUID; `token-usage.py` parses the session JSONL and computes cost; `append-usage.sh` appends per-phase/per-task rows to `usage.md`. Surfaced by `/pace:usage` and embedded in the PR body.
- **Model override** — `.pace/settings.md` holds `plan-model` and `execute-model`; planning-phase vs execution-phase commands read the respective one and pass it as the `model` param when spawning agents. The orchestrator's own model is never changed.
- **Memory layers** — episodic (what was built this plan) synthesized into semantic (durable decisions/patterns) at completion.

Spend real effort here. The maintainer explicitly wants the improving agent to have a *deep* understanding of what PACE is for — not a surface reading.

---

## 2. Ground rules for this engagement

- **Everything is on the table**, including the core design principles above. If you believe a principle is actively harming the tool (e.g. "one agent per stage" leaves parallelizable work on the floor, or "orchestrator never implements" adds ceremony to trivial changes), you may propose changing it. **But:** the maintainer only just removed the swarm architecture on purpose. Any proposal that reverses a recent deliberate decision, or that changes a stated principle, must be filed as a distinct **"Architectural"** proposal with: the evidence that the current principle hurts, the specific alternative, the migration cost, and the risk. Do not bundle principle-changes in with routine fixes, and do not implement any of them until the maintainer explicitly greenlights that specific proposal at the checkpoint.
- **Audit is open-ended.** Do not limit yourself to the seed findings below — they are a starting point to prove the audit is grounded, not a checklist. Find what I missed.
- **One checkpoint, hard stop.** Produce the ranked proposal doc, present it, and wait. No code changes before approval.
- **After approval, implement only the approved subset.** If during implementation you discover the approved fix is wrong or reveals something bigger, stop and re-check with the maintainer rather than expanding scope silently.

---

## 3. Phase A — Research (to inform the audit)

Do some external research before/while auditing, and fold genuinely applicable ideas into your findings. Suggested threads (not exhaustive, don't cargo-cult):

- **Spec-driven / agentic dev workflows** — how comparable tools structure the same problem: GitHub's spec-kit, Amazon Kiro, Cline/Roo memory-bank patterns, Claude Code's own subagent + slash-command guidance. What do they do that PACE doesn't, and vice-versa?
- **Claude Code command & subagent best practices** — current conventions for command frontmatter, `allowed-tools`, argument hints, when/how to spawn subagents, and how skills relate to commands. Verify PACE's patterns against current guidance rather than assuming they're optimal.
- **Reliability of LLM-followed procedural instructions** — techniques that make multi-step instruction sheets robust (explicit state, idempotency, avoiding brittle string-matching, reducing branching, single-source-of-truth). This directly informs the fragility findings.

Keep research proportionate — it should sharpen the audit, not become the deliverable.

---

## 4. Phase B — The audit

Evaluate PACE across (at least) these dimensions. For each finding capture: **what**, **where** (`file:line`), **why it matters**, **severity**, **proposed fix**, **effort**, **risk/blast-radius**.

Dimensions:
1. **Correctness & reliability** — will an LLM following this instruction reliably do the right thing? Contradictions, impossible steps, wrong tool grants, broken cross-command handoffs.
2. **Maintainability / DRY** — duplicated instruction blocks that will drift out of sync.
3. **Robustness of LLM-followed steps** — brittle parsing, fragile heading string-matching, unstated assumptions, silent-failure branches.
4. **Documentation & architecture consistency** — docs vs. actual command behavior vs. stated principles; leftovers from the swarm→single-agent migration.
5. **UX & output quality** — interview quality, plan readability, verification signal, user-facing messaging, error/recovery paths.
6. **Capability gaps** — things a spec-driven workflow arguably should have and PACE doesn't.
7. **The design principles themselves** — held up against how the tool actually gets used.

### Seed findings (verify each independently, then go well beyond them)

These were spotted in a quick read and are almost certainly a fraction of what's there. Confirm with your own eyes (line numbers drift):

- **Missing referenced file.** `CLAUDE.md` opens by telling the reader to "load `CONTEXT.md`" for full project context, but no `CONTEXT.md` exists in the repo. Either it was deleted in a refactor or never created. (The auto-memory index also references a `CONTEXT.md`-style build-order doc.)
- **Stale architecture doc.** `RISKS.md` describes "wave-based parallel task execution," "the synthesiser," and parallel-agent resource conflicts — all artifacts of the *removed* swarm design. It documents a risk that no longer exists and proposes a fix for a subsystem that's gone.
- **`resume.md` cannot do what it says.** Its frontmatter grants `allowed-tools: [Read]` only, but its Step 2 instructs it to "proceed exactly as `/pace:execute` would" — spawn specialist agents, edit `STATE.md`, run git commits. With only `Read`, it structurally cannot. Either it must delegate back to `/pace:execute` cleanly, or it needs the full toolset.
- **Large-scale prompt duplication.** The **model-override reading block**, the **session-UUID detection block**, and the **"with override / without override" token-usage recording snippet** are copy-pasted near-verbatim across `execute.md`, `verify.md`, `fix.md`, `amend.md`, `complete.md`, `plan.md`, `scan.md`, `agent.md`. Any change to token recording or model handling means editing ~8 files in lockstep — a live divergence risk. (Note: Claude Code command files have no `include` mechanism, so "DRY" here is not trivial — part of your proposal should be *how* to deduplicate: a shared lib doc the commands reference, a canonical snippet block, pushing logic into the `lib/` scripts, or a documented single-source-of-truth that the others point to. Weigh the options.)
- **Brittle runtime parsing.** Execution depends on the orchestrator string-matching task headings like `### {id}. {title}` out of `PLAN.md`, and on parsing a `## Files Modified` section out of each specialist's free-text summary to decide what to `git add`. Both are single points of failure driven by LLM formatting discipline. The `git add -A` fallback can commit unrelated working-tree changes.
- **Inconsistent conventions across commands** — e.g. how the model override is read (`scan.md`/`agent.md` phrase it differently from the others), varying pre-flight/session-UUID handling, and `/pace:agent`'s ad-hoc argument parsing ("agent name is the first 1–3 words").
- **`complete.md` does heavy, irreversible git work** (creates a PR, squash-merges, deletes the branch, checks out and pulls `main`) inline for roadmap phases — audit its failure/partial-completion handling and whether that belongs in `complete` at all.

Also actively look for: gaps between `docs/` and the commands; success-criteria quality guidance vs. what the verifier actually checks; whether `--light` modes are consistent between `fix` and `amend`; the interview's "minimum 3 questions" rule vs. genuinely simple requests; and anything in the lib scripts that assumes a path/format that could break.

---

## 5. Phase B deliverable — the proposal doc (then STOP)

Write a single Markdown document — suggested path `AUDIT.md` at the repo root (or propose a better home) — structured as:

- **Summary** — the 3–5 highest-leverage things, in one paragraph.
- **Findings**, ranked by (severity × leverage ÷ effort), each with: title, severity (Critical/High/Medium/Low), evidence (`file:line`), why it matters, proposed fix, effort (S/M/L), risk.
- **Grouped into three buckets:**
  - **Fixes** — clear defects / drift, low controversy.
  - **Improvements** — quality/UX/maintainability enhancements within the current architecture.
  - **Architectural** — anything that changes a stated design principle. Each needs the extra justification described in Ground rules.
- A short **recommended scope** for round one.

Then **present it to the maintainer and stop.** Ask them to approve which findings to action (they may take all Fixes, some Improvements, and defer Architectural — or any mix). Do not write code until they respond.

---

## 6. Phase C — Implementation (only after approval)

- Work on a feature branch. Make small, logically-scoped commits (ideally one finding or one coherent group per commit) with clear messages.
- When editing prompt files: **preserve the established voice and structure**, keep every instruction unambiguous for an LLM to follow, and prefer removing ambiguity/branching over adding it. If you introduce a deduplication mechanism, apply it consistently and document it in `docs/CONTRIBUTING.md`.
- **Keep everything in sync:** if you change a command's behavior, update `docs/`, `CLAUDE.md`, `README`, the mermaid diagrams, and `install.sh`/`uninstall.sh` (e.g. the `LEGACY_AGENT_FILES` list and namespace cleanup) as needed. Drift is the exact disease you're curing — don't add more.
- **Validate** as well as the medium allows: re-read changed files for internal and cross-file consistency; trace each lifecycle handoff end-to-end; and if feasible, install PACE into a scratch project (`./install.sh --local` in a throwaway repo) and actually run the commands. State clearly in your final report what you validated and how.
- Open a **draft PR** summarizing what was changed, mapped back to the approved findings, and what remains deferred.

---

## 7. Definition of done

- A ranked `AUDIT.md` existed, was presented, and scope was explicitly approved.
- Every approved finding is either implemented or explicitly deferred with a reason.
- No new documentation drift introduced; existing drift within approved scope is fixed.
- Any principle-level change was approved as a distinct Architectural proposal before implementation.
- A draft PR is open, with a summary that a maintainer can review against the approved scope.
- Your final report states what you changed, what you validated and how, and what you deliberately left for a future pass.

Work autonomously through the audit; the only place you must pause for input is the approval checkpoint in §5 (and any mid-implementation discovery that expands scope).
