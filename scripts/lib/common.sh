#!/bin/bash
# Common library loader
# Source this file at the start of any script to get all shared functionality
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/../lib/common.sh"  # adjust path as needed

# Guard against multiple sourcing
[[ -n "${_LIB_COMMON_LOADED:-}" ]] && return 0
_LIB_COMMON_LOADED=1

# Find the lib directory
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all library files
source "${_LIB_DIR}/ui.sh"
source "${_LIB_DIR}/board.sh"
source "${_LIB_DIR}/artifacts.sh"

# Common setup
set -e
set -o pipefail

# Cleanup function for git lock files (created by interrupted Docker git operations)
cleanup_git_locks() {
    rm -f "${PROJECT_ROOT}/.git/index.lock" 2>/dev/null || true
}

# Set up trap to clean locks on exit/interrupt
trap cleanup_git_locks EXIT INT TERM

# Clean any existing locks from previous interrupted runs
cleanup_git_locks
