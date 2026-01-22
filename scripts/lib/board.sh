#!/bin/bash
# Board configuration loader
# Source this file, don't execute it directly

# Guard against multiple sourcing
[[ -n "${_LIB_BOARD_LOADED:-}" ]] && return 0
_LIB_BOARD_LOADED=1

# Find project root (parent of scripts/)
_find_project_root() {
    local script_path="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    # If sourced from another script, BASH_SOURCE[1] is the sourcing script
    # Walk up to find directory containing 'boards/' and 'scripts/'
    local dir
    dir="$(cd "$(dirname "$script_path")" && pwd)"

    # Try going up from lib/ -> scripts/ -> project root
    local candidate="${dir}/../.."
    if [[ -d "${candidate}/boards" ]] && [[ -d "${candidate}/scripts" ]]; then
        cd "$candidate" && pwd
        return 0
    fi

    # Fallback: walk up until we find boards/
    while [[ "$dir" != "/" ]]; do
        if [[ -d "${dir}/boards" ]] && [[ -d "${dir}/scripts" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    echo "Error: Could not find project root" >&2
    return 1
}

PROJECT_ROOT="${PROJECT_ROOT:-$(_find_project_root)}"
BOARDS_DIR="${PROJECT_ROOT}/boards"

# List all available boards (directory names)
list_boards() {
    local board_dir
    for board_dir in "${BOARDS_DIR}"/*/; do
        if [[ -f "${board_dir}board.conf" ]]; then
            basename "$board_dir"
        fi
    done
}

# List all board aliases (for help text)
list_board_aliases() {
    local board_dir
    for board_dir in "${BOARDS_DIR}"/*/; do
        if [[ -f "${board_dir}board.conf" ]]; then
            local aliases=""
            # shellcheck disable=SC1090
            aliases=$(grep -E '^BOARD_ALIASES=' "${board_dir}board.conf" 2>/dev/null | cut -d= -f2- | tr -d '"')
            if [[ -n "$aliases" ]]; then
                echo "$(basename "$board_dir"): $aliases"
            fi
        fi
    done
}

# Resolve board name (handles aliases)
# Returns canonical board directory name or empty if not found
resolve_board() {
    local query="$1"
    local board_dir board_name aliases

    # First, check for exact directory match
    if [[ -f "${BOARDS_DIR}/${query}/board.conf" ]]; then
        echo "$query"
        return 0
    fi

    # Search aliases in each board.conf
    for board_dir in "${BOARDS_DIR}"/*/; do
        if [[ -f "${board_dir}board.conf" ]]; then
            board_name=$(basename "$board_dir")
            # shellcheck disable=SC1090
            aliases=$(grep -E '^BOARD_ALIASES=' "${board_dir}board.conf" 2>/dev/null | cut -d= -f2- | tr -d '"')

            # Check if query matches any alias
            for alias in $aliases; do
                if [[ "$alias" == "$query" ]]; then
                    echo "$board_name"
                    return 0
                fi
            done
        fi
    done

    # Not found
    return 1
}

# Load board configuration
# Sets: BOARD_NAME, BOARD_DESC, DTB_NAME, and other board.conf variables
# Dies with error if board not found or config invalid
load_board() {
    local query="$1"
    local resolved

    if [[ -z "$query" ]]; then
        echo "Error: No board specified" >&2
        echo "Available boards: $(list_boards | tr '\n' ' ')" >&2
        return 1
    fi

    resolved=$(resolve_board "$query")
    if [[ -z "$resolved" ]]; then
        echo "Error: Unknown board '$query'" >&2
        echo "Available boards: $(list_boards | tr '\n' ' ')" >&2
        return 1
    fi

    local conf="${BOARDS_DIR}/${resolved}/board.conf"

    # Source the board config
    # shellcheck disable=SC1090
    source "$conf"

    # Validate required fields
    if [[ -z "${BOARD_NAME:-}" ]]; then
        echo "Error: BOARD_NAME not set in $conf" >&2
        return 1
    fi
    if [[ -z "${BOARD_DTB:-}" ]]; then
        echo "Error: BOARD_DTB not set in $conf" >&2
        return 1
    fi

    # Derive DTB_NAME (without .dtb extension) for convenience
    DTB_NAME="${BOARD_DTB%.dtb}"

    # Export for subprocesses
    export BOARD_NAME BOARD_DESCRIPTION BOARD_DTB DTB_NAME
    export BOARD_DIR="${BOARDS_DIR}/${resolved}"
    export BOARD_CONF="$conf"

    return 0
}

# Show board info (for --info command)
show_board_info() {
    local board="${1:-$BOARD_NAME}"

    if [[ -z "$board" ]]; then
        echo "Error: No board loaded or specified" >&2
        return 1
    fi

    # Load if not already loaded
    if [[ -z "${BOARD_NAME:-}" ]] || [[ "$BOARD_NAME" != "$board" ]]; then
        load_board "$board" || return 1
    fi

    echo "Board: ${BOARD_NAME}"
    echo "  Description: ${BOARD_DESCRIPTION:-N/A}"
    echo "  DTB:         ${BOARD_DTB}"
    echo "  Config:      ${BOARD_CONF}"
    [[ -n "${BOARD_ALIASES:-}" ]] && echo "  Aliases:     ${BOARD_ALIASES}"
    [[ -n "${UBOOT_DEFCONFIG:-}" ]] && echo "  U-Boot:      ${UBOOT_DEFCONFIG}"
    [[ -n "${CONSOLE:-}" ]] && echo "  Console:     ${CONSOLE}"
}
