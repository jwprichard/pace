---
name: pace:sync-agents
description: Scan installed agents and build the PACE agent registry
argument-hint: "[--force]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
---

<objective>
Scan global and local agent directories, parse agent metadata,
and write a two-tier agent registry that the planner uses for
task routing.

This is a utility command. It writes files but never delegates
to other agents or modifies any project code.
</objective>

<context>
**Flags:**
- `--force` — Rebuild registry even if no agent files have changed

**Scan directories (in priority order):**
1. `.claude/agents/` (local — wins dedup conflicts)
2. `~/.claude/agents/` (global)

**Output files:**
- `.pace/AGENT-REGISTRY.md` — Tier 1 division index
- `.pace/agents/{division}.md` — Tier 2 agent details per division
</context>

<process>
1. **Scan** — Glob both agent directories for `.md` files.
   Derive division from parent folder name (e.g. `engineering/ai-engineer.md` → division: `engineering`).
   Agents at the directory root get division: `general`.

2. **Parse** — Read each agent file's YAML frontmatter.
   Extract `name` and `description` fields.
   Skip any file missing either field and warn.

3. **Deduplicate** — If the same agent name appears in both
   local and global dirs, keep the local version.

4. **Group** — Group agents by division.

5. **Write Tier 2** — For each division, write `.pace/agents/{division}.md`:
```
   # {Division}

   | Name | Description |
   |---|---|
   | @agent-name | Description from frontmatter |
```

6. **Write Tier 1** — Write `.pace/AGENT-REGISTRY.md`:
```
   # PACE Agent Registry
   _Last synced: {ISO timestamp}_

   | Division | Agent Count | Covers |
   |---|---|---|
   | engineering | 24 | Summarise from descriptions |
```

   Generate the "Covers" summary by reading the descriptions
   in each division and producing a concise comma-separated
   list of capabilities.

7. **Report** — Print summary: divisions found, total agents,
   any skipped files, any dedup resolutions.
</process>
