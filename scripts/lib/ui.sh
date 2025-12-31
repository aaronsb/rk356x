#!/bin/bash
# UI helpers: colors, icons, logging functions
# Source this file, don't execute it directly

# Guard against multiple sourcing
[[ -n "${_LIB_UI_LOADED:-}" ]] && return 0
_LIB_UI_LOADED=1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Icons
ICON_CHECK="✓"
ICON_CROSS="✗"
ICON_WARN="⚠"
ICON_INFO="ℹ"
ICON_BUILD="🔨"
ICON_SKIP="⏭"

# Logging functions
log()    { echo -e "${GREEN}${ICON_CHECK}${NC} $*"; }
warn()   { echo -e "${YELLOW}${ICON_WARN}${NC} $*"; }
info()   { echo -e "${CYAN}${ICON_INFO}${NC} $*"; }
error()  { echo -e "${RED}${ICON_CROSS}${NC} $*" >&2; exit 1; }
header() { echo -e "\n${BOLD}${BLUE}━━━ $* ━━━${NC}\n"; }

# Print a key-value pair for info display
kv() {
    local key="$1"
    local value="$2"
    printf "  ${BOLD}%-12s${NC} %s\n" "${key}:" "$value"
}
