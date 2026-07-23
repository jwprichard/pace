#!/bin/bash
set -euo pipefail

VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
  cat <<EOF
${BOLD}PACE Installer v${VERSION}${NC}

Usage: ./install.sh [--global | --local] [--force]

Options:
  --global    Install to ~/.claude/ (available in all projects) [default]
  --local     Install to ./.claude/ (project-scoped, committable)
  --force     Overwrite existing files without prompting
  --help      Show this message

Examples:
  ./install.sh                  # Global install
  ./install.sh --local          # Install into current project
  ./install.sh --local --force  # Overwrite existing project install
EOF
  exit 0
}

# --- Parse arguments ---
TARGET="global"
FORCE=false

for arg in "$@"; do
  case "$arg" in
    --global) TARGET="global" ;;
    --local)  TARGET="local" ;;
    --force)  FORCE=true ;;
    --help)   usage ;;
    *)
      echo -e "${RED}Unknown option: $arg${NC}"
      usage
      ;;
  esac
done

# --- Set destination ---
if [ "$TARGET" = "local" ]; then
  DEST="$(pwd)/.claude"
else
  DEST="$HOME/.claude"
fi

# Legacy top-level agent files that older PACE versions shipped directly under
# agents/ (current versions namespace everything under agents/pace/). These are
# removed on install/uninstall so a rename or retirement never leaves a stale
# file behind. Add a filename here whenever a top-level agent is retired.
LEGACY_AGENT_FILES=(
  "pace-synthesiser.md"
)

echo -e "${BOLD}PACE Installer v${VERSION}${NC}"
echo -e "Target: ${GREEN}${DEST}${NC}"
echo ""

# --- Validate source ---
if [ ! -d "$SRC_DIR/commands" ]; then
  echo -e "${RED}Error: src/commands/ not found.${NC}"
  echo "Run this script from the PACE repo root."
  exit 1
fi

# --- Check for existing files ---
CONFLICTS=()

check_conflict() {
  local src="$1"
  local dest="$2"
  if [ -e "$dest" ] && [ "$FORCE" = false ]; then
    CONFLICTS+=("$dest")
  fi
}

while IFS= read -r file; do
  rel="${file#$SRC_DIR/commands/}"
  check_conflict "$file" "$DEST/commands/$rel"
done < <(find "$SRC_DIR/commands" -name "*.md" -type f)

if [ -d "$SRC_DIR/agents" ]; then
  while IFS= read -r file; do
    rel="${file#$SRC_DIR/agents/}"
    check_conflict "$file" "$DEST/agents/$rel"
  done < <(find "$SRC_DIR/agents" -name "*.md" -type f)
fi

if [ ${#CONFLICTS[@]} -gt 0 ]; then
  echo -e "${YELLOW}The following files already exist:${NC}"
  for f in "${CONFLICTS[@]}"; do
    echo "  $f"
  done
  echo ""
  read -p "Overwrite? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
fi

# --- Clean stale PACE files ---
# Runs only after the conflict prompt is resolved, so an aborted install
# never deletes anything. PACE owns the commands/pace/ and agents/pace/
# namespaces entirely, so clearing their *.md before copying fresh makes
# install idempotent — any command or agent retired in a newer version is
# removed rather than left orphaned. The shared top-level agents/ directory
# is touched only for the explicit LEGACY_AGENT_FILES list.
clean_stale() {
  for ns in "commands/pace" "agents/pace"; do
    if [ -d "$DEST/$ns" ]; then
      find "$DEST/$ns" -name "*.md" -type f -delete
    fi
  done
  for legacy in "${LEGACY_AGENT_FILES[@]}"; do
    if [ -e "$DEST/agents/$legacy" ]; then
      rm -f "$DEST/agents/$legacy"
      echo -e "  ${YELLOW}−${NC} removed stale agents/$legacy"
    fi
  done
}

clean_stale

# --- Install ---
INSTALLED=0

install_files() {
  local src_base="$1"
  local dest_base="$2"
  local label="$3"

  while IFS= read -r file; do
    rel="${file#$src_base/}"
    dest="$dest_base/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$file" "$dest"
    echo -e "  ${GREEN}✓${NC} $label/$rel"
    INSTALLED=$((INSTALLED + 1))
  done < <(find "$src_base" -name "*.md" -type f)
}

install_files "$SRC_DIR/commands" "$DEST/commands" "commands"
if [ -d "$SRC_DIR/agents" ]; then
  install_files "$SRC_DIR/agents" "$DEST/agents" "agents"
fi

# --- Install lib scripts ---
if [ -d "$SRC_DIR/lib" ]; then
  LIB_DEST="$DEST/lib/pace"
  mkdir -p "$LIB_DEST"
  for script in token-usage.py find-session.sh append-usage.sh; do
    src_file="$SRC_DIR/lib/$script"
    if [ -f "$src_file" ]; then
      cp "$src_file" "$LIB_DEST/$script"
      chmod +x "$LIB_DEST/$script"
      echo -e "  ${GREEN}✓${NC} lib/pace/$script"
      INSTALLED=$((INSTALLED + 1))
    fi
  done
fi

# --- Summary ---
echo ""
echo -e "${GREEN}${BOLD}Done.${NC} Installed ${INSTALLED} files to ${DEST}"
echo ""
if [ "$TARGET" = "local" ]; then
  echo "Next steps:"
  echo "  1. Commit .claude/ to your repo"
  echo "  2. Run /pace:sync-agents to build the agent registry"
else
  echo "Next steps:"
  echo "  1. cd into a project"
  echo "  2. Run /pace:sync-agents to build the agent registry"
fi
