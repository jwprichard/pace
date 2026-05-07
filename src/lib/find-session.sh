#!/usr/bin/env bash
# find-session.sh
# Outputs the UUID of the most recently modified Claude Code session for the
# current working directory.
#
# Usage:
#   bash src/lib/find-session.sh
#
# Exit codes:
#   0  — UUID printed to stdout
#   1  — No JSONL session files found for this project path

set -euo pipefail

# Encode the absolute path of the current working directory by replacing each
# '/' and '.' with '-', matching Claude Code's project directory naming.
# For example:
#   /home/ubuntu/repos/pace                        →  -home-ubuntu-repos-pace
#   /home/ubuntu/repos/app/.claude/worktrees/feat  →  -home-ubuntu-repos-app--claude-worktrees-feat
encoded_path="${PWD//[\/.]/-}"

project_dir="${HOME}/.claude/projects/${encoded_path}"

# Find the most recently modified *.jsonl file directly inside the project
# directory (not recursively).  ls -t sorts by modification time, newest first.
# The "|| true" prevents set -e from aborting when ls finds no matching files.
latest_file=$(ls -t "${project_dir}"/*.jsonl 2>/dev/null | head -1 || true)

if [[ -z "${latest_file}" ]]; then
    exit 1
fi

# Strip the directory prefix and the .jsonl extension to obtain the UUID.
filename=$(basename "${latest_file}")
uuid="${filename%.jsonl}"

printf '%s\n' "${uuid}"
