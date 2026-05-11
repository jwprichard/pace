#!/usr/bin/env python3
"""
token-usage.py — Token aggregation and formatting for PACE workflow.

Subcommands:
  aggregate <uuid> <project-path>  Parse session JSONL files and emit JSON totals
  format <mode> [file]             Format .pace/usage.md in detail or summary mode
"""

import json
import os
import sys
import glob
from pathlib import Path


# ---------------------------------------------------------------------------
# Pricing table (per token)
# ---------------------------------------------------------------------------

PRICING = {
    "opus": {
        "input":        0.000015,
        "output":       0.000075,
        "cache_read":   0.0000015,
        "cache_write":  0.00001875,
    },
    "sonnet": {
        "input":        0.000003,
        "output":       0.000015,
        "cache_read":   0.0000003,
        "cache_write":  0.00000375,
    },
    "haiku": {
        "input":        0.0000008,
        "output":       0.000004,
        "cache_read":   0.00000008,
        "cache_write":  0.000001,
    },
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def normalise_model(raw: str) -> str:
    """
    Normalise a raw model string to a family name.

    Examples:
      'claude-opus-4-6-20250415' -> 'opus'
      'claude-opus-4-6'         -> 'opus'
      'claude-sonnet-4-6'       -> 'sonnet'
      'claude-haiku-3-5'        -> 'haiku'
    """
    if not raw:
        return "unknown"
    lowered = raw.lower()
    # Strip trailing date suffix like -20250415 or -20260101
    if len(lowered) >= 9 and lowered[-9] == "-" and lowered[-8:].isdigit():
        lowered = lowered[:-9]
    for family in ("opus", "sonnet", "haiku"):
        if family in lowered:
            return family
    return "unknown"


def zero_totals() -> dict:
    return {
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_read_input_tokens": 0,
        "cache_creation_input_tokens": 0,
    }


def add_totals(dst: dict, src: dict) -> None:
    for key in zero_totals():
        dst[key] = dst.get(key, 0) + src.get(key, 0)


def max_totals(dst: dict, src: dict) -> None:
    """Merge src into dst by taking the per-field maximum (deduplication)."""
    for key in zero_totals():
        dst[key] = max(dst.get(key, 0), src.get(key, 0))


def compute_cost(totals: dict, model: str) -> float:
    pricing = PRICING.get(model, PRICING["sonnet"])
    return (
        totals.get("input_tokens", 0) * pricing["input"]
        + totals.get("output_tokens", 0) * pricing["output"]
        + totals.get("cache_read_input_tokens", 0) * pricing["cache_read"]
        + totals.get("cache_creation_input_tokens", 0) * pricing["cache_write"]
    )


# ---------------------------------------------------------------------------
# Aggregate subcommand
# ---------------------------------------------------------------------------

def parse_jsonl(path: str) -> list:
    """
    Parse a JSONL file and return a list of assistant entries that carry usage.
    Only entries of type='assistant' with message.usage present are returned.
    """
    entries = []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if obj.get("type") != "assistant":
                    continue
                msg = obj.get("message", {})
                if not msg.get("usage"):
                    continue
                entries.append(obj)
    except FileNotFoundError:
        pass
    return entries


def deduplicate(entries: list) -> dict:
    """
    Deduplicate entries by composite key message.id:requestId.
    For duplicate keys, per-field max is applied across token counts.
    Returns a dict keyed by composite key, value is merged entry data.
    """
    merged = {}
    for entry in entries:
        msg = entry.get("message", {})
        usage = msg.get("usage", {})
        msg_id = msg.get("id", "")
        req_id = entry.get("requestId", "")
        key = f"{msg_id}:{req_id}"

        model = normalise_model(msg.get("model", ""))
        tokens = {
            "input_tokens": usage.get("input_tokens", 0),
            "output_tokens": usage.get("output_tokens", 0),
            "cache_read_input_tokens": usage.get("cache_read_input_tokens", 0),
            "cache_creation_input_tokens": usage.get("cache_creation_input_tokens", 0),
        }

        if key not in merged:
            merged[key] = {"model": model, "tokens": tokens}
        else:
            max_totals(merged[key]["tokens"], tokens)
            # model should be consistent for the same key; keep existing

    return merged


def aggregate_file(path: str) -> tuple:
    """
    Aggregate a single JSONL file.
    Returns (totals_dict, model_str) where totals_dict contains summed token counts.
    If the file is missing or has no entries, returns (zero_totals(), 'unknown').
    """
    entries = parse_jsonl(path)
    if not entries:
        return zero_totals(), "unknown"

    deduped = deduplicate(entries)
    totals = zero_totals()
    model = "unknown"
    for record in deduped.values():
        add_totals(totals, record["tokens"])
        # Use the most common model (last wins for simplicity; all should be same)
        if record["model"] != "unknown":
            model = record["model"]

    return totals, model


def cmd_aggregate(args: list) -> None:
    if len(args) < 2:
        print(
            "Usage: token-usage.py aggregate <session-uuid> <project-path>",
            file=sys.stderr,
        )
        sys.exit(1)

    session_uuid = args[0]
    project_path = args[1]

    # Expand ~ in project path
    home = str(Path.home())
    claude_projects = os.path.join(home, ".claude", "projects")
    project_dir = os.path.join(claude_projects, project_path)

    # Main session JSONL
    main_jsonl = os.path.join(project_dir, f"{session_uuid}.jsonl")
    orch_totals, orch_model = aggregate_file(main_jsonl)
    orch_cost = compute_cost(orch_totals, orch_model)
    orch_totals["cost"] = orch_cost

    # Subagent JSONL files
    subagent_dir = os.path.join(project_dir, session_uuid, "subagents")
    subagent_pattern = os.path.join(subagent_dir, "agent-*.jsonl")
    subagent_files = sorted(glob.glob(subagent_pattern))

    subagents = []
    grand_totals = zero_totals()
    add_totals(grand_totals, orch_totals)
    grand_cost = orch_cost

    for sa_file in subagent_files:
        base = os.path.basename(sa_file)          # agent-XXXX.jsonl
        stem = base[:-6]                           # agent-XXXX  (strip .jsonl)
        meta_file = os.path.join(subagent_dir, f"{stem}.meta.json")

        # Read meta sidecar
        agent_type = "unknown"
        description = ""
        try:
            with open(meta_file, "r", encoding="utf-8") as mh:
                meta = json.load(mh)
            agent_type = meta.get("agentType", "unknown")
            description = meta.get("description", "")
        except (FileNotFoundError, json.JSONDecodeError):
            pass

        sa_totals, sa_model = aggregate_file(sa_file)
        sa_cost = compute_cost(sa_totals, sa_model)
        sa_totals["cost"] = sa_cost

        add_totals(grand_totals, sa_totals)
        grand_cost += sa_cost

        subagents.append(
            {
                "file": base,
                "agent_type": agent_type,
                "description": description,
                "model": sa_model,
                "totals": sa_totals,
                "cost": sa_cost,
            }
        )

    grand_totals["cost"] = grand_cost

    output = {
        "orchestrator": orch_totals,
        "subagents": subagents,
        "grand_total": grand_totals,
        "grand_cost": grand_cost,
    }
    print(json.dumps(output))


# ---------------------------------------------------------------------------
# Format subcommand
# ---------------------------------------------------------------------------

def fmt_tokens(n: int) -> str:
    """Format integer token count with comma separators."""
    return f"{n:,}"


def fmt_cost(amount: float, force_full: bool = False) -> str:
    """
    Format a cost value as a dollar string.
    Totals (>= $0.01) use $X.XX; small values use $X.XXXX.
    force_full forces $X.XX regardless of amount (for grand total rows).
    """
    if force_full or amount >= 0.01:
        return f"${amount:.2f}"
    return f"${amount:.4f}"


def parse_usage_md(content: str) -> dict:
    """
    Parse .pace/usage.md content into a structured dict:
    {
      "phases": {
        "plan": [
          {"task": "1", "agent": "...", "model": "...", "input": N, "output": N,
           "cache_read": N, "cache_write": N, "cost": X.XXXX},
          ...
        ],
        ...
      }
    }
    """
    phases = {}
    current_phase = None
    in_table = False

    for raw_line in content.splitlines():
        line = raw_line.strip()

        # Phase heading: ## Plan, ## Execute, etc.
        if line.startswith("## "):
            phase_name = line[3:].strip().lower()
            current_phase = phase_name
            if current_phase not in phases:
                phases[current_phase] = []
            in_table = False
            continue

        if current_phase is None:
            continue

        # Table header row
        if line.startswith("| Task |") or line.startswith("|---"):
            in_table = True
            continue

        # Table separator row
        if line.startswith("|---") or line.startswith("| ---"):
            continue

        # Data row
        if in_table and line.startswith("|"):
            parts = [p.strip() for p in line.split("|")]
            # parts[0] is empty (before first |), parts[-1] is empty (after last |)
            cols = parts[1:-1]
            if len(cols) < 8:
                continue
            try:
                task = cols[0]
                agent = cols[1]
                model = cols[2]
                input_t = int(cols[3].replace(",", ""))
                output_t = int(cols[4].replace(",", ""))
                cache_read = int(cols[5].replace(",", ""))
                cache_write = int(cols[6].replace(",", ""))
                cost_str = cols[7].lstrip("$")
                cost = float(cost_str)
                phases[current_phase].append(
                    {
                        "task": task,
                        "agent": agent,
                        "model": model,
                        "input": input_t,
                        "output": output_t,
                        "cache_read": cache_read,
                        "cache_write": cache_write,
                        "cost": cost,
                    }
                )
            except (ValueError, IndexError):
                continue

    return {"phases": phases}


def phase_subtotals(rows: list) -> dict:
    totals = {
        "input": 0,
        "output": 0,
        "cache_read": 0,
        "cache_write": 0,
        "cost": 0.0,
    }
    for row in rows:
        totals["input"] += row["input"]
        totals["output"] += row["output"]
        totals["cache_read"] += row["cache_read"]
        totals["cache_write"] += row["cache_write"]
        totals["cost"] += row["cost"]
    return totals


PHASE_ORDER = ["plan", "execute", "verify", "fix", "amend", "complete"]


def format_detail(data: dict) -> str:
    """Produce full per-task breakdown grouped by phase."""
    phases = data["phases"]
    lines = []

    grand = {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0, "cost": 0.0}

    for phase in PHASE_ORDER:
        rows = phases.get(phase)
        if not rows:
            continue

        lines.append(f"## {phase.capitalize()}")
        lines.append("")
        lines.append(
            "| Task | Agent | Model | Input | Output | Cache Read | Cache Write | Cost |"
        )
        lines.append(
            "|------|-------|-------|------:|-------:|-----------:|------------:|-----:|"
        )

        sub = {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0, "cost": 0.0}
        for row in rows:
            lines.append(
                f"| {row['task']} | {row['agent']} | {row['model']} "
                f"| {fmt_tokens(row['input'])} "
                f"| {fmt_tokens(row['output'])} "
                f"| {fmt_tokens(row['cache_read'])} "
                f"| {fmt_tokens(row['cache_write'])} "
                f"| {fmt_cost(row['cost'])} |"
            )
            sub["input"] += row["input"]
            sub["output"] += row["output"]
            sub["cache_read"] += row["cache_read"]
            sub["cache_write"] += row["cache_write"]
            sub["cost"] += row["cost"]

        # Phase subtotal row
        lines.append(
            f"| **Subtotal** | | "
            f"| **{fmt_tokens(sub['input'])}** "
            f"| **{fmt_tokens(sub['output'])}** "
            f"| **{fmt_tokens(sub['cache_read'])}** "
            f"| **{fmt_tokens(sub['cache_write'])}** "
            f"| **{fmt_cost(sub['cost'], force_full=True)}** |"
        )
        lines.append("")

        for key in ("input", "output", "cache_read", "cache_write"):
            grand[key] += sub[key]
        grand["cost"] += sub["cost"]

    if not lines:
        lines.append("No usage data available.")
        return "\n".join(lines)

    # Grand total
    lines.append("## Grand Total")
    lines.append("")
    lines.append(
        "| Input | Output | Cache Read | Cache Write | Total Cost |"
    )
    lines.append(
        "|------:|-------:|-----------:|------------:|-----------:|"
    )
    lines.append(
        f"| **{fmt_tokens(grand['input'])}** "
        f"| **{fmt_tokens(grand['output'])}** "
        f"| **{fmt_tokens(grand['cache_read'])}** "
        f"| **{fmt_tokens(grand['cache_write'])}** "
        f"| **{fmt_cost(grand['cost'], force_full=True)}** |"
    )

    return "\n".join(lines)


def format_summary(data: dict) -> str:
    """Produce compact one-row-per-phase summary table."""
    phases = data["phases"]
    lines = []

    lines.append("| Phase | Total Tokens | Cost |")
    lines.append("|-------|-------------:|-----:|")

    grand_tokens = 0
    grand_cost = 0.0
    has_data = False

    for phase in PHASE_ORDER:
        rows = phases.get(phase)
        if not rows:
            continue
        has_data = True
        sub = phase_subtotals(rows)
        total_tokens = sub["input"] + sub["output"] + sub["cache_read"] + sub["cache_write"]
        grand_tokens += total_tokens
        grand_cost += sub["cost"]
        lines.append(
            f"| {phase.capitalize()} "
            f"| {fmt_tokens(total_tokens)} "
            f"| {fmt_cost(sub['cost'], force_full=True)} |"
        )

    if not has_data:
        return "No usage data available."

    lines.append(
        f"| **Grand Total** "
        f"| **{fmt_tokens(grand_tokens)}** "
        f"| **{fmt_cost(grand_cost, force_full=True)}** |"
    )

    return "\n".join(lines)


def cmd_format(args: list) -> None:
    if len(args) < 1:
        print(
            "Usage: token-usage.py format <detail|summary> [file]",
            file=sys.stderr,
        )
        sys.exit(1)

    mode = args[0].lower()
    if mode not in ("detail", "summary"):
        print(
            f"Unknown format mode: {mode!r}. Expected 'detail' or 'summary'.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Read content from file argument or stdin
    if len(args) >= 2:
        file_path = args[1]
        try:
            with open(file_path, "r", encoding="utf-8") as fh:
                content = fh.read()
        except FileNotFoundError:
            print("No usage data found. Token tracking begins when you run /pace:plan.")
            return
    else:
        if sys.stdin.isatty():
            # No stdin piped and no file — treat as missing
            print("No usage data found. Token tracking begins when you run /pace:plan.")
            return
        content = sys.stdin.read()

    if not content.strip():
        print("No usage data found. Token tracking begins when you run /pace:plan.")
        return

    data = parse_usage_md(content)

    if mode == "detail":
        print(format_detail(data))
    else:
        print(format_summary(data))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    if len(sys.argv) < 2:
        print(
            "Usage: token-usage.py <aggregate|format> [args...]",
            file=sys.stderr,
        )
        sys.exit(1)

    subcmd = sys.argv[1].lower()
    rest = sys.argv[2:]

    if subcmd == "aggregate":
        cmd_aggregate(rest)
    elif subcmd == "format":
        cmd_format(rest)
    else:
        print(f"Unknown subcommand: {subcmd!r}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
