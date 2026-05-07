# PACE Architecture

## Command Lifecycle

```mermaid
flowchart TD
    scan["/pace:scan"]
    plan["/pace:plan"]
    roadmap["/pace:roadmap"]
    execute["/pace:execute"]
    agent["/pace:agent"]
    verify["/pace:verify"]
    fix["/pace:fix"]
    amend["/pace:amend"]
    complete["/pace:complete"]
    resume["/pace:resume"]
    status["/pace:status"]
    createpr["/pace:create-pr"]
    settings["/pace:settings"]
    usage["/pace:usage"]

    scan -->|PROJECT.md ready| plan
    roadmap -->|ROADMAP.md ready| plan
    plan -->|PLAN.md + STATE.md approved| execute
    execute -->|all tasks done| verify
    verify -->|work confirmed| complete
    verify -->|needs work| fix
    fix -->|fixes applied| verify
    execute -->|extra scope needed| amend
    amend -->|amendments applied| execute
    execute -->|task blocked| resume
    resume --> execute
    complete --> createpr

    agent -.->|one-shot shortcut| complete
    fix -.->|"--light (no state tracking)"| complete
    amend -.->|"--light (minimal tracking)"| verify
    status -.->|read-only view| execute
    settings -.->|configure models| plan
    usage -.->|read-only view| execute
```

## Agent Roster

```mermaid
flowchart LR
    subgraph pace-agents["PACE Agents (agents/pace/)"]
        analyst["pace-codebase-analyst\nGenerates PROJECT.md"]
        synthesiser["pace-synthesiser\nMerges draft plans → PLAN.md"]
        docspec["pace-documentation-specialist\nPatches PROJECT.md after tasks"]
        verifier["pace-verification-specialist\nChecks work vs success criteria"]
    end

    subgraph specialists["Specialist Agents (registry)"]
        fe["@Frontend Developer"]
        be["@Backend Architect"]
        dv["@DevOps Automator"]
        etc["@... (any installed agent)"]
    end

    analyst -->|writes| project[".pace/PROJECT.md"]
    synthesiser -->|writes| plan[".pace/PLAN.md"]
    docspec -->|patches| project
    verifier -->|reads| plan

    fe & be & dv & etc -->|report back to orchestrator| docspec
```

## Execute Wave Flow

```mermaid
flowchart TD
    start(["pace:execute"]) --> preflight["Pre-flight\nRead PLAN.md + STATE.md"]
    preflight --> stale{"PROJECT.md\nstale?"}
    stale -->|yes| warn["Warn user\n(commits since last scan)"]
    stale -->|no| waves
    warn --> waves

    waves["Build wave schedule\n(dependency graph)"]
    waves --> wave1

    subgraph wave1["Wave N"]
        mark["Mark tasks in_progress\n(STATE.md + Claude task UI)"]
        spawn["Spawn specialist agents\nin parallel"]
        mark --> spawn
        spawn --> outcomes["Record outcomes per task\n(STATE.md + Claude task UI)"]
        outcomes --> commit["Per-task commit\n(if changes exist)"]
        commit --> doc["pace-documentation-specialist\npatches PROJECT.md"]
    end

    doc --> more{"More\nwaves?"}
    more -->|yes| wave1
    more -->|no| done["Mark complete\nRun /pace:verify"]

    outcomes -->|any failure| blocked["Mark blocked\nSurface to user\n→ /pace:resume"]
```

## Data Flow

```mermaid
flowchart LR
    subgraph inputs["User Intent"]
        user(["User"])
    end

    subgraph runtime[".pace/"]
        project["PROJECT.md\n(codebase map + commit hash)"]
        registry["AGENT-REGISTRY.md\n(agent index)"]
        plan["PLAN.md\n(tasks + agents + dependencies)"]
        state["STATE.md\n(execution progress)"]
        settings["settings.md\n(plan-model / execute-model)"]
        usagemd["usage.md\n(token usage ledger)"]
        roadmapmd["ROADMAP.md\n(phase decomposition)"]
        episode["memory/episode.md\n(episodic memory)"]
        semantic["memory/semantic.md\n(semantic memory)"]
        brief["requirements/brief.md\n(interview requirements)"]
        research["requirements/research.md\n(research findings)"]
    end

    subgraph outputs["Codebase"]
        code["Project files"]
    end

    user -->|"/pace:scan"| project
    user -->|"/pace:roadmap"| roadmapmd
    user -->|"/pace:plan"| plan
    user -->|"/pace:plan"| brief
    plan -->|approved| state
    project & registry & plan & state -->|context| orchestrator["Orchestrator"]
    settings -->|plan-model / execute-model| orchestrator
    orchestrator -->|tailored brief| specialists["Specialist Agents"]
    specialists -->|completion summary| docspec["pace-documentation-specialist"]
    specialists -->|implementation| code
    docspec -->|patch| project
    specialists -->|usage events| usagemd
    episode -->|synthesised by /pace:complete| semantic
```

**Settings override**: The orchestrator reads `settings.md` at command time and passes the appropriate model parameter to specialist agent spawns. Planning commands (`/pace:plan`, `/pace:roadmap`, `/pace:scan`) read `plan-model`. Execution commands (`/pace:execute`, `/pace:verify`, `/pace:fix`, `/pace:amend`, `/pace:complete`, `/pace:agent`) read `execute-model`. This allows planning agents to run on a stronger model for architectural reasoning while execution agents run on a faster, cheaper model for bounded work. The orchestrator's own model always matches the session model.

## Token Usage Tracking

```mermaid
flowchart LR
    subgraph plan_time["Plan time (/pace:plan)"]
        session["find-session.sh\nCaptures session UUID → STATE.md"]
        clear["Clear .pace/usage.md"]
    end

    subgraph exec_time["Execution time"]
        agents["Specialist agents complete"]
        append["append-usage.sh\nReads JSONL, deduplicates,\nappends phase entry to usage.md"]
    end

    subgraph lifecycle["Lifecycle commands that record usage"]
        execphase["/pace:execute\n(per wave)"]
        verifyphase["/pace:verify"]
        fixphase["/pace:fix"]
        amendphase["/pace:amend"]
        completephase["/pace:complete\n(memory-synthesis + doc-refresh)"]
    end

    subgraph display["Read-only commands"]
        usage["/pace:usage\nPipes usage.md through\ntoken-usage.py format detail"]
        pr["/pace:create-pr\nPipes usage.md through\ntoken-usage.py format summary\n→ embedded in PR body"]
    end

    session --> agents
    clear --> append
    agents --> append
    execphase & verifyphase & fixphase & amendphase & completephase --> append
    append -->|per wave / per phase| append
    append --> usage
    append --> pr
```

**Token tracking lifecycle**: At plan time, `find-session.sh` identifies the current Claude Code session UUID from the process tree and writes it to `STATE.md`. `/pace:plan` also clears `.pace/usage.md` so each plan starts with a fresh ledger. After each agent completes, `append-usage.sh` calls `token-usage.py aggregate` to parse the session's JSONL file, deduplicate entries already recorded, and append a new phase row to `usage.md`. The five lifecycle commands that record usage are: `/pace:execute` (per wave), `/pace:verify`, `/pace:fix`, `/pace:amend`, and `/pace:complete` — the last of which records two sub-phases: `memory-synthesis` (the memory-synthesiser agent) and `doc-refresh` (the documentation-specialist full-rescan). `/pace:usage` reads the accumulated `usage.md` and pipes it through `token-usage.py format detail` to render a per-task breakdown table. `/pace:create-pr` pipes the same file through `token-usage.py format summary` to embed a cost summary in the PR body. `/pace:complete` preserves `usage.md` during cleanup so the record survives plan finalisation.

## PROJECT.md Freshness

```mermaid
flowchart LR
    scan["/pace:scan"] -->|stores commit hash| project["PROJECT.md"]
    execute["/pace:execute\n/pace:plan"] -->|git rev-parse HEAD| check{"Hash\nmatches?"}
    check -->|yes| proceed["Proceed normally"]
    check -->|no| warn["Warn: PROJECT.md is N commits old\nSuggest /pace:scan"]
    warn --> proceed

    complete["/pace:complete"] -->|full re-scan| docspec["pace-documentation-specialist"]
    docspec -->|rewrites| project
```
