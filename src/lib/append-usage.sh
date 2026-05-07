#!/usr/bin/env bash
# append-usage.sh
# Appends token usage entries to .pace/usage.md.
#
# Usage:
#   bash src/lib/append-usage.sh <phase> <task> <agent_type> [json-file]
#   echo '...' | bash src/lib/append-usage.sh <phase> <task> <agent_type>
#
# Arguments:
#   phase       Phase name, e.g. "plan", "execute", "verify". Written as ## Plan heading.
#   task        Task number or the literal "orchestrator".
#   agent_type  Agent type label written into the Agent column.
#   json-file   Optional path to JSON file from token-usage.py aggregate.
#               If omitted, JSON is read from stdin.
#
# Exit codes:
#   0  Success
#   1  Missing required arguments or unreadable JSON input
#
# Dependencies: python3 (stdlib only), awk, bash builtins

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

if [[ $# -lt 3 ]]; then
    printf 'Usage: append-usage.sh <phase> <task> <agent_type> [json-file]\n' >&2
    exit 1
fi

PHASE="$1"
TASK="$2"
AGENT_TYPE="$3"
JSON_SOURCE="${4:-}"   # optional path; empty means read stdin

# Capitalise first letter of the phase name for the ## heading
PHASE_CAP="$(printf '%s' "${PHASE}" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')"

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

USAGE_FILE=".pace/usage.md"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIND_SESSION="${LIB_DIR}/find-session.sh"

# Temp file for the JSON payload (needed so Python can read it without
# conflicting with any heredoc or process-substitution stdin)
JSON_TMP="$(mktemp /tmp/pace-usage-XXXXXX.json)"
PY_TMP="$(mktemp /tmp/pace-rows-XXXXXX.py)"
trap 'rm -f "${JSON_TMP}" "${PY_TMP}"' EXIT

# ---------------------------------------------------------------------------
# Read JSON input
# ---------------------------------------------------------------------------

if [[ -n "${JSON_SOURCE}" ]]; then
    if [[ ! -f "${JSON_SOURCE}" ]]; then
        printf 'append-usage.sh: JSON file not found: %s\n' "${JSON_SOURCE}" >&2
        exit 1
    fi
    cp "${JSON_SOURCE}" "${JSON_TMP}"
else
    if [[ -t 0 ]]; then
        printf 'append-usage.sh: No JSON input — provide a file argument or pipe JSON via stdin.\n' >&2
        exit 1
    fi
    cat > "${JSON_TMP}"
fi

if [[ ! -s "${JSON_TMP}" ]]; then
    printf 'append-usage.sh: Empty JSON input.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Create .pace/usage.md with session header if it does not exist
# ---------------------------------------------------------------------------

if [[ ! -f "${USAGE_FILE}" ]]; then
    mkdir -p "$(dirname "${USAGE_FILE}")"

    SESSION_UUID="unknown"
    if [[ -x "${FIND_SESSION}" ]]; then
        SESSION_UUID="$(bash "${FIND_SESSION}" 2>/dev/null || true)"
        [[ -z "${SESSION_UUID}" ]] && SESSION_UUID="unknown"
    fi

    printf '# Token Usage\n'         > "${USAGE_FILE}"
    printf '_Session: %s_\n' "${SESSION_UUID}" >> "${USAGE_FILE}"
    printf '\n'                      >> "${USAGE_FILE}"
fi

# ---------------------------------------------------------------------------
# Write the Python row-extraction script to a temp file
# ---------------------------------------------------------------------------
# Reads the aggregate JSON from the file path given as argv[1] and prints one
# TSV line per subagent (or one orchestrator line when there are no subagents).
# Columns: task  agent  model  input  output  cache_read  cache_write  cost

cat > "${PY_TMP}" << 'PYEOF'
import json
import sys

json_file   = sys.argv[1]
task_label  = sys.argv[2]
agent_label = sys.argv[3]

with open(json_file, "r", encoding="utf-8") as fh:
    raw = fh.read()

try:
    data = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"append-usage.sh: invalid JSON: {exc}", file=sys.stderr)
    sys.exit(1)


def fmt_tokens(n):
    return f"{int(n):,}"


def fmt_cost(amount):
    amount = float(amount)
    if amount >= 0.01:
        return f"${amount:.2f}"
    return f"${amount:.4f}"


def row(*cols):
    print("\t".join(str(c) for c in cols))


subagents = data.get("subagents", [])

if not subagents:
    # No subagents recorded — emit one row for the orchestrator itself
    orch  = data.get("orchestrator", {})
    model = orch.get("model", "unknown")
    row(
        task_label,
        agent_label,
        model,
        fmt_tokens(orch.get("input_tokens", 0)),
        fmt_tokens(orch.get("output_tokens", 0)),
        fmt_tokens(orch.get("cache_read_input_tokens", 0)),
        fmt_tokens(orch.get("cache_creation_input_tokens", 0)),
        fmt_cost(orch.get("cost", 0.0)),
    )
else:
    for sa in subagents:
        totals = sa.get("totals", {})
        row(
            task_label,
            sa.get("agent_type", agent_label),
            sa.get("model", "unknown"),
            fmt_tokens(totals.get("input_tokens", 0)),
            fmt_tokens(totals.get("output_tokens", 0)),
            fmt_tokens(totals.get("cache_read_input_tokens", 0)),
            fmt_tokens(totals.get("cache_creation_input_tokens", 0)),
            fmt_cost(sa.get("cost", 0.0)),
        )
PYEOF

# ---------------------------------------------------------------------------
# Run Python to get TSV rows
# ---------------------------------------------------------------------------

ROWS="$(python3 "${PY_TMP}" "${JSON_TMP}" "${TASK}" "${AGENT_TYPE}")"

if [[ -z "${ROWS}" ]]; then
    # Nothing to append
    exit 0
fi

# ---------------------------------------------------------------------------
# Ensure the phase heading and table header exist in the file
# ---------------------------------------------------------------------------

HEADING="## ${PHASE_CAP}"
TABLE_HEADER="| Task | Agent | Model | Input | Output | Cache Read | Cache Write | Cost |"
TABLE_SEP="|------|-------|-------|------:|-------:|-----------:|------------:|-----:|"

if ! grep -qF "${HEADING}" "${USAGE_FILE}"; then
    # Ensure the file ends with a newline before appending the new section
    if [[ -s "${USAGE_FILE}" ]]; then
        last_line="$(tail -1 "${USAGE_FILE}")"
        [[ -n "${last_line}" ]] && printf '\n' >> "${USAGE_FILE}"
    fi
    printf '%s\n' "${HEADING}"      >> "${USAGE_FILE}"
    printf '%s\n' "${TABLE_HEADER}" >> "${USAGE_FILE}"
    printf '%s\n' "${TABLE_SEP}"    >> "${USAGE_FILE}"
fi

# ---------------------------------------------------------------------------
# Append each TSV row as a markdown table row into the correct section
# ---------------------------------------------------------------------------
# Each row is inserted after the last existing data row under the phase
# heading, or directly after the separator if the section has no data rows yet.
# awk buffers the entire file, locates the insertion point, then rewrites.

FILE_TMP="${USAGE_FILE}.tmp.$$"

while IFS= read -r ROW_TSV; do
    [[ -z "${ROW_TSV}" ]] && continue

    # Split TSV into named fields
    IFS=$'\t' read -r r_task r_agent r_model r_input r_output r_cache_read r_cache_write r_cost \
        <<< "${ROW_TSV}"

    MD_ROW="| ${r_task} | ${r_agent} | ${r_model} | ${r_input} | ${r_output} | ${r_cache_read} | ${r_cache_write} | ${r_cost} |"

    # awk: buffer all lines, find last data row (or separator) under heading,
    # insert new_row immediately after it, then print the full file.
    awk -v heading="${HEADING}" -v new_row="${MD_ROW}" '
    {
        lines[NR] = $0
    }
    END {
        n = NR

        # Locate the target section
        sec_start = -1
        for (i = 1; i <= n; i++) {
            if (lines[i] == heading) { sec_start = i; break }
        }

        if (sec_start == -1) {
            # Heading not found — print file unchanged (should not happen)
            for (i = 1; i <= n; i++) print lines[i]
            exit
        }

        # Find the last table data row and the separator within the section
        # A data row starts with "|" but is NOT the header ("| Task |") or
        # a separator row ("|---" or "| ---")
        last_data = -1
        sep_line  = -1
        in_sec    = 0
        for (i = sec_start + 1; i <= n; i++) {
            if (lines[i] ~ /^## /) { break }   # next section ends ours
            if (lines[i] ~ /^\|---/ || lines[i] ~ /^\| ---/) {
                if (sep_line == -1) sep_line = i
                continue
            }
            if (lines[i] ~ /^\|/ && lines[i] !~ /^\| Task /) {
                last_data = i
            }
        }

        # Choose insertion point
        insert_after = (last_data != -1) ? last_data : sep_line

        # Print file with insertion
        for (i = 1; i <= n; i++) {
            print lines[i]
            if (i == insert_after) print new_row
        }

        # If neither data rows nor separator were found, just append at EOF
        if (insert_after == -1) {
            print new_row
        }
    }
    ' "${USAGE_FILE}" > "${FILE_TMP}"

    mv "${FILE_TMP}" "${USAGE_FILE}"

done <<< "${ROWS}"
