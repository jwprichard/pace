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
  # Remove the pace/ directory if now empty
  find "$COMMANDS_DIR" -type d -empty -delete 2>/dev/null || true
else
  echo "  No PACE commands found at ${COMMANDS_DIR}"
fi

# --- Optional runtime cleanup ---
if [ "$INCLUDE_RUNTIME" = true ]; then
  PACE_DIR="$(pwd)/.pace"
  if [ -d "$PACE_DIR" ]; then
    rm -rf "$PACE_DIR"
    echo -e "  ${RED}✗${NC} .pace/ (registry, plans, state)"
    ((REMOVED++))
  fi
fi

echo ""
if [ "$REMOVED" -gt 0 ]; then
  echo -e "${GREEN}${BOLD}Done.${NC} Removed ${REMOVED} items."
else
  echo "Nothing to remove."
fi
