#!/bin/bash
# Backward compatibility wrapper for build.sh
# Redirects to new modular orchestrator at scripts/build.sh
#
# NOTE: This wrapper exists for backward compatibility.
# The canonical location is now: scripts/build.sh
#
# Standalone scripts can also be run directly:
#   ./scripts/build/kernel.sh <board> build
#   ./scripts/build/uboot.sh <board> build
#   ./scripts/build/rootfs.sh <board> build
#   ./scripts/device/assemble.sh <board> build
#   ./scripts/device/flash-sd.sh <board> flash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Map old board names to new canonical names
map_board_name() {
    case "$1" in
        rk3568_sz3568) echo "sz3568-v1.2" ;;
        rk3568_custom) echo "dc-a568-v06" ;;
        *) echo "$1" ;;
    esac
}

# Transform arguments, mapping old board names
args=()
for arg in "$@"; do
    case "$arg" in
        rk3568_*) args+=("$(map_board_name "$arg")") ;;
        *) args+=("$arg") ;;
    esac
done

exec "${SCRIPT_DIR}/scripts/build.sh" "${args[@]}"
