# PACE Architecture

## Command Lifecycle

```mermaid
flowchart TD
    scan["/pace:scan"]
    plan["/pace:plan"]
    execute["/pace:execute"]
    agent["/pace:agent"]
    verify["/pace:verify"]
    fix["/pace:fix"]
    amend["/pace:amend"]
    complete["/pace:complete"]
    resume["/pace:resume"]
    status["/pace:status"]

    scan -->|PROJECT.md ready| plan
    plan -->|PLAN.md + STATE.md approved| execute
    execute -->|all tasks done| verify
    verify -->|work confirmed| complete
    verify -->|needs work| fix
    fix -->|fixes applied| verify
    execute -->|extra scope needed| amend
    amend -->|amendments applied| execute
    execute -->|task blocked| resume
    resume --> execute

    agent -.->|one-shot shortcut| complete
    fix -.->|"--light (no state tracking)"| complete
    amend -.->|"--light (minimal tracking)"| verify
```

## Agent Roster

```mermaid
flowchart LR
    subgraph pace-agents["PACE Agents (agents/pace/)"]
        scanner["pace-scanner\nGenerates PROJECT.md"]
        synthesiser["pace-synthesiser\nMerges draft plans → PLAN.md"]
        documenter["pace-documenter\nPatches PROJECT.md after tasks"]
        verifier["pace-verifier\nChecks work vs success criteria"]
    end

    subgraph specialists["Specialist Agents (registry)"]
        fe["@Frontend Developer"]
        be["@Backend Architect"]
        dv["@DevOps Automator"]
        etc["@... (any installed agent)"]
    end

    scanner -->|writes| project[".pace/PROJECT.md"]
    synthesiser -->|writes| plan[".pace/PLAN.md"]
    documenter -->|patches| project
    verifier -->|reads| plan

    fe & be & dv & etc -->|report back to orchestrator| documenter
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
        spawn --> outcomes["Record outcomes\n(STATE.md + Claude task UI)"]
        outcomes --> doc["pace-documenter\npatches PROJECT.md"]
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
    end

    subgraph outputs["Codebase"]
        code["Project files"]
    end

    user -->|"/pace:scan"| project
    user -->|"/pace:plan"| plan
    plan -->|approved| state
    project & registry & plan & state -->|context| orchestrator["Orchestrator"]
    settings -->|plan-model / execute-model| orchestrator
    orchestrator -->|tailored brief| specialists["Specialist Agents"]
    specialists -->|completion summary| documenter["pace-documenter"]
    specialists -->|implementation| code
    documenter -->|patch| project
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

    subgraph display["Read-only commands"]
        usage["/pace:usage\nPipes usage.md through\ntoken-usage.py format detail"]
        pr["/pace:create-pr\nPipes usage.md through\ntoken-usage.py format summary\n→ embedded in PR body"]
    end

    session --> agents
    clear --> append
    agents --> append
    append -->|per wave / per phase| append
    append --> usage
    append --> pr
```

**Token tracking lifecycle**: At plan time, `find-session.sh` identifies the current Claude Code session UUID from the process tree and writes it to `STATE.md`. `/pace:plan` also clears `.pace/usage.md` so each plan starts with a fresh ledger. After each agent completes — in `/pace:execute` (per wave), `/pace:verify`, `/pace:fix`, and `/pace:amend` — `append-usage.sh` calls `token-usage.py aggregate` to parse the session's JSONL file, deduplicate entries already recorded, and append a new phase row to `usage.md`. `/pace:usage` reads the accumulated `usage.md` and pipes it through `token-usage.py format detail` to render a per-task breakdown table. `/pace:create-pr` pipes the same file through `token-usage.py format summary` to embed a cost summary in the PR body. `/pace:complete` preserves `usage.md` during cleanup so the record survives plan finalisation.

## PROJECT.md Freshness

```mermaid
flowchart LR
    scan["/pace:scan"] -->|stores commit hash| project["PROJECT.md"]
    execute["/pace:execute\n/pace:plan"] -->|git rev-parse HEAD| check{"Hash\nmatches?"}
    check -->|yes| proceed["Proceed normally"]
    check -->|no| warn["Warn: PROJECT.md is N commits old\nSuggest /pace:scan"]
    warn --> proceed

    complete["/pace:complete"] -->|full re-scan| documenter["pace-documenter"]
    documenter -->|rewrites| project
```
