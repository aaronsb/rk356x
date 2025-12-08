#!/bin/bash

# Git Lock File Monitor
# Watches for .git/index.lock creation and shows what created it

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WATCH_DIR="${PROJECT_ROOT}/.git"

echo "=== Git Lock File Monitor ==="
echo "Watching: ${WATCH_DIR}"
echo "Press Ctrl+C to stop"
echo ""

# Clean up on exit
cleanup() {
    echo ""
    echo "Monitor stopped"
    exit 0
}
trap cleanup INT TERM

# Function to show detailed info about lock file
show_lock_info() {
    local lock_file="$1"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔒 LOCK FILE CREATED: $(date '+%Y-%m-%d %H:%M:%S.%N')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # File info
    if [ -f "$lock_file" ]; then
        echo "File: $lock_file"
        ls -lh "$lock_file"
        echo ""

        # Try to find what process has it open
        echo "Process holding lock:"
        if lsof "$lock_file" 2>/dev/null; then
            echo ""
            # Get the PID and show full process tree
            local pid=$(lsof -t "$lock_file" 2>/dev/null | head -1)
            if [ -n "$pid" ]; then
                echo "Process tree:"
                pstree -p "$pid" 2>/dev/null || ps -f -p "$pid"
                echo ""
                echo "Command line:"
                ps -f -p "$pid" 2>/dev/null
                echo ""
                echo "Working directory:"
                pwdx "$pid" 2>/dev/null || echo "  (unavailable)"
            fi
        else
            echo "  No process has it open (created and released quickly)"
            echo ""
            # Try fuser as backup
            echo "Recent access (fuser):"
            fuser -v "$lock_file" 2>&1 || echo "  No info available"
        fi
    else
        echo "Lock file disappeared before we could check it!"
    fi

    echo ""
    echo "Waiting for next lock file..."
    echo ""
}

# Monitor using inotifywait
echo "Starting monitor..."
inotifywait -m -e create,moved_to "${WATCH_DIR}" 2>/dev/null | while read -r directory event filename; do
    if [[ "$filename" == "index.lock" ]]; then
        show_lock_info "${directory}${filename}"
    fi
done
