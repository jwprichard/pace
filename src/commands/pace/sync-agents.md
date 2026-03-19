---
name: pace:sync-agents
description: Scan installed agents and build the PACE agent registry
argument-hint: "[--force]"
allowed-tools:
  - Bash
  - Write
---

<objective>
Scan global and local agent directories, parse agent metadata,
and write a two-tier agent registry that the planner uses for
task routing.

This is a utility command. It writes files but never delegates
to other agents or modifies any project code.
</objective>

<process>

Run the following bash script to scan, parse, deduplicate, and write the
registry. All file parsing happens in the shell — do not read agent files
directly into context.

```bash
python3 << 'PYEOF'
import os, re, json
from datetime import datetime, timezone
from collections import defaultdict

LOCAL_DIR  = os.path.join(os.getcwd(), ".claude/agents")
GLOBAL_DIR = os.path.expanduser("~/.claude/agents")
OUT_DIR    = os.path.join(os.getcwd(), ".pace")

SKIP_NAMES   = {"README.md", "CONTRIBUTING.md", "EXECUTIVE-BRIEF.md", "QUICKSTART.md"}
SKIP_TOP_DIRS = {"examples", "integrations", "strategy"}

def parse_frontmatter(path):
    try:
        with open(path) as f:
            content = f.read(4096)  # Only read first 4KB — frontmatter is always near the top
    except Exception as e:
        return None, f"read error: {e}"
    if not content.startswith("---"):
        return None, "no frontmatter"
    end = content.find("---", 3)
    if end == -1:
        return None, "unclosed frontmatter"
    fm = content[3:end]
    name = re.search(r'^name:\s*(.+)$', fm, re.MULTILINE)
    desc = re.search(r'^description:\s*(.+)$', fm, re.MULTILINE)
    if not name or not desc:
        return None, f"missing {'name' if not name else 'description'}"
    return {"name": name.group(1).strip().strip('"'), "description": desc.group(1).strip().strip('"')}, None

def scan_dir(base, source_label):
    results, skipped = [], []
    if not os.path.isdir(base):
        return results, skipped
    for root, dirs, files in os.walk(base):
        rel_root = os.path.relpath(root, base)
        top = rel_root.split(os.sep)[0] if rel_root != "." else "."
        if top in SKIP_TOP_DIRS:
            dirs.clear()
            continue
        for fname in sorted(files):
            if not fname.endswith(".md") or fname in SKIP_NAMES:
                continue
            fpath = os.path.join(root, fname)
            rel = os.path.relpath(fpath, base)
            parts = rel.split(os.sep)
            division = parts[0] if len(parts) > 1 else "general"
            meta, err = parse_frontmatter(fpath)
            if err:
                skipped.append({"file": f"{source_label}:{rel}", "reason": err})
                continue
            meta["division"] = division
            meta["source"] = source_label
            results.append(meta)
    return results, skipped

global_agents, global_skipped = scan_dir(GLOBAL_DIR, "global")
local_agents,  local_skipped  = scan_dir(LOCAL_DIR,  "local")
all_skipped = global_skipped + local_skipped

# Deduplicate: local wins
registry = {}
dedup_log = []
for agent in global_agents:
    registry[agent["name"]] = agent
for agent in local_agents:
    if agent["name"] in registry:
        dedup_log.append(agent["name"])
    registry[agent["name"]] = agent

agents = list(registry.values())

# Group by division
by_division = defaultdict(list)
for a in agents:
    by_division[a["division"]].append(a)

# Write Tier 2 files
os.makedirs(os.path.join(OUT_DIR, "agents"), exist_ok=True)
for division, div_agents in sorted(by_division.items()):
    div_agents_sorted = sorted(div_agents, key=lambda x: x["name"])
    lines = [f"# {division.replace('-', ' ').title()}\n",
             "| Name | Description |", "|---|---|"]
    for a in div_agents_sorted:
        desc = a["description"].replace("|", "\\|")
        lines.append(f"| @{a['name']} | {desc} |")
    with open(os.path.join(OUT_DIR, "agents", f"{division}.md"), "w") as f:
        f.write("\n".join(lines) + "\n")

# Build covers summary
def summarise(div_agents):
    caps = []
    for a in div_agents:
        first = re.split(r'[,.]', a["description"])[0].strip()
        first = re.sub(r'\bspecializ(ing|ed) in\b.*', '', first, flags=re.I).strip()
        first = re.sub(r'\bexpert (in|at)\b', '', first, flags=re.I).strip()
        if first and first not in caps:
            caps.append(first)
    summary = ", ".join(caps[:4])
    if len(caps) > 4:
        summary += f" (+{len(caps)-4} more)"
    return summary

# Write Tier 1
timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
lines = ["# PACE Agent Registry", f"_Last synced: {timestamp}_", "",
         "| Division | Agent Count | Covers |", "|---|---|---|"]
for division in sorted(by_division.keys()):
    div_agents = by_division[division]
    covers = summarise(div_agents)
    lines.append(f"| [{division}](.pace/agents/{division}.md) | {len(div_agents)} | {covers} |")
with open(os.path.join(OUT_DIR, "AGENT-REGISTRY.md"), "w") as f:
    f.write("\n".join(lines) + "\n")

# Output summary for Claude to report
print(json.dumps({
    "timestamp": timestamp,
    "divisions": len(by_division),
    "total_agents": len(agents),
    "global": len(global_agents),
    "local": len(local_agents),
    "dedup": dedup_log,
    "skipped": all_skipped,
    "division_counts": {d: len(v) for d, v in sorted(by_division.items())}
}))
PYEOF
```

Capture the JSON output and report a summary to the user:
- Divisions found and agent count per division
- Total agents
- Any dedup resolutions (local overrode global)
- Any skipped files and why

If the script exits with an error, show the error and stop.

</process>
