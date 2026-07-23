#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
  cat <<EOF
${BOLD}PACE Uninstaller${NC}

Usage: ./uninstall.sh [--global | --local] [--include-runtime]

Options:
  --global           Remove from ~/.claude/ [default]
  --local            Remove from ./.claude/
  --include-runtime  Also remove .pace/ directory (registry, plans, state)
  --help             Show this message
EOF
  exit 0
}

TARGET="global"
INCLUDE_RUNTIME=false

for arg in "$@"; do
  case "$arg" in
    --global)          TARGET="global" ;;
    --local)           TARGET="local" ;;
    --include-runtime) INCLUDE_RUNTIME=true ;;
    --help)            usage ;;
    *)
      echo -e "${RED}Unknown option: $arg${NC}"
      usage
      ;;
  esac
done

if [ "$TARGET" = "local" ]; then
  DEST="$(pwd)/.claude"
else
  DEST="$HOME/.claude"
fi

# Legacy top-level agent files that older PACE versions shipped directly under
# agents/ (current versions namespace everything under agents/pace/). Kept in
# sync with the same list in install.sh so upgrades and removals stay clean.
LEGACY_AGENT_FILES=(
  "pace-synthesiser.md"
)

echo -e "${BOLD}PACE Uninstaller${NC}"
echo -e "Target: ${YELLOW}${DEST}${NC}"
echo ""

REMOVED=0

# --- Remove PACE commands ---
COMMANDS_DIR="$DEST/commands/pace"
if [ -d "$COMMANDS_DIR" ]; then
  while IFS= read -r file; do
    rel="${file#$COMMANDS_DIR/}"
    rm "$file"
    echo -e "  ${RED}✗${NC} commands/pace/$rel"
    REMOVED=$((REMOVED + 1))
  done < <(find "$COMMANDS_DIR" -name "*.md" -type f)
  find "$COMMANDS_DIR" -type d -empty -delete 2>/dev/null || true
else
  echo "  No PACE commands found at ${COMMANDS_DIR}"
fi

# --- Remove PACE agents (PACE owns the agents/pace/ namespace) ---
AGENTS_DIR="$DEST/agents/pace"
if [ -d "$AGENTS_DIR" ]; then
  while IFS= read -r file; do
    rel="${file#$DEST/agents/}"
    rm "$file"
    echo -e "  ${RED}✗${NC} agents/$rel"
    REMOVED=$((REMOVED + 1))
  done < <(find "$AGENTS_DIR" -name "*.md" -type f)
  find "$AGENTS_DIR" -type d -empty -delete 2>/dev/null || true
fi

# Legacy top-level PACE agent files from older versions
for legacy in "${LEGACY_AGENT_FILES[@]}"; do
  if [ -e "$DEST/agents/$legacy" ]; then
    rm "$DEST/agents/$legacy"
    echo -e "  ${RED}✗${NC} agents/$legacy"
    REMOVED=$((REMOVED + 1))
  fi
done

# --- Remove PACE lib scripts ---
LIB_DIR="$DEST/lib/pace"
if [ -d "$LIB_DIR" ]; then
  rm -rf "$LIB_DIR"
  echo -e "  ${RED}✗${NC} lib/pace/ (token-usage.py, find-session.sh, append-usage.sh)"
  REMOVED=$((REMOVED + 1))
fi

# --- Optional runtime cleanup ---
if [ "$INCLUDE_RUNTIME" = true ]; then
  PACE_DIR="$(pwd)/.pace"
  if [ -d "$PACE_DIR" ]; then
    rm -rf "$PACE_DIR"
    echo -e "  ${RED}✗${NC} .pace/ (registry, plans, state)"
    REMOVED=$((REMOVED + 1))
  fi
fi

echo ""
if [ "$REMOVED" -gt 0 ]; then
  echo -e "${GREEN}${BOLD}Done.${NC} Removed ${REMOVED} items."
else
  echo "Nothing to remove."
fi
