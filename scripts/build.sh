#!/bin/bash
# Debian Build System Orchestrator for RK3568
# Thin orchestrator - delegates to scripts in build/ and device/

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Configuration
KERNEL_VERSION="${KERNEL_VERSION:-6.12}"

# ============================================================================
# Usage
# ============================================================================

usage() {
    cat <<EOF
${BOLD}Debian Build System for RK3568${NC}

${BOLD}USAGE:${NC}
    $(basename "$0") [OPTIONS] [BOARD]

${BOLD}BOARDS:${NC}
$(list_boards | sed 's/^/    /')

${BOLD}OPTIONS:${NC}
    --auto                Auto mode: build only what's missing, flash to SD card
    --clean               Delete all build artifacts before starting
    --quiet               Quiet mode: hide verbose build output
    --non-interactive     Skip all prompts, rebuild everything
    --kernel-only         Build kernel only
    --rootfs-only         Build rootfs only
    --uboot-only          Build U-Boot only
    --image-only          Assemble image only (skip builds)
    --with-uboot          Include U-Boot in image
    --device /dev/sdX     SD card device (for --auto mode)
    --help, -h            Show this help

${BOLD}EXAMPLES:${NC}
    # Interactive build (recommended for first time)
    $(basename "$0") sz3568-v1.2

    # Auto mode: build what's needed, flash to SD card
    $(basename "$0") --auto --device /dev/sdX sz3568-v1.2

    # Clean rebuild
    $(basename "$0") --clean sz3568-v1.2

    # Build kernel only
    $(basename "$0") --kernel-only sz3568-v1.2

    # Assemble image from existing artifacts
    $(basename "$0") --image-only sz3568-v1.2

${BOLD}STANDALONE SCRIPTS:${NC}
    Build scripts can also be run directly:

    ./scripts/build/kernel.sh sz3568-v1.2 build
    ./scripts/build/uboot.sh sz3568-v1.2 build
    ./scripts/build/rootfs.sh sz3568-v1.2 build
    ./scripts/device/assemble.sh sz3568-v1.2 build
    ./scripts/device/flash-sd.sh sz3568-v1.2 flash
EOF
}

# ============================================================================
# Argument Parsing
# ============================================================================

BOARD=""
AUTO_MODE=false
CLEAN_MODE=false
QUIET_MODE=false
NON_INTERACTIVE=false
KERNEL_ONLY=false
ROOTFS_ONLY=false
UBOOT_ONLY=false
IMAGE_ONLY=false
WITH_UBOOT=false
SD_DEVICE=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto)
                AUTO_MODE=true
                NON_INTERACTIVE=true
                shift
                ;;
            --clean)
                CLEAN_MODE=true
                shift
                ;;
            --quiet)
                QUIET_MODE=true
                shift
                ;;
            --device)
                SD_DEVICE="$2"
                shift 2
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --kernel-only)
                KERNEL_ONLY=true
                shift
                ;;
            --rootfs-only)
                ROOTFS_ONLY=true
                shift
                ;;
            --uboot-only)
                UBOOT_ONLY=true
                shift
                ;;
            --image-only)
                IMAGE_ONLY=true
                shift
                ;;
            --with-uboot)
                WITH_UBOOT=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            -*)
                error "Unknown option: $1\nRun '$(basename "$0") --help' for usage"
                ;;
            *)
                BOARD="$1"
                shift
                ;;
        esac
    done
}

# ============================================================================
# Interactive Prompts (orchestrator's responsibility)
# ============================================================================

ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        echo "$default"
        return
    fi

    local yn
    if [[ "$default" == "y" ]]; then
        read -p "$(echo -e "${prompt} [Y/n]: ")" -r yn
        yn="${yn:-y}"
    else
        read -p "$(echo -e "${prompt} [y/N]: ")" -r yn
        yn="${yn:-n}"
    fi

    echo "$yn"
}

# ============================================================================
# Sudo Session Management (orchestrator's responsibility)
# ============================================================================

setup_sudo() {
    local needs_sudo=false

    # Image assembly and flashing need sudo
    if [[ "$IMAGE_ONLY" == "true" ]] || [[ "$AUTO_MODE" == "true" ]] || \
       [[ "$KERNEL_ONLY" != "true" && "$ROOTFS_ONLY" != "true" && "$UBOOT_ONLY" != "true" ]]; then
        needs_sudo=true
    fi

    [[ "$needs_sudo" == "false" ]] && return 0

    info "Establishing sudo session..."
    sudo -v || error "Failed to establish sudo session"

    # Keep sudo session alive
    ( while true; do sudo -v; sleep 60; done; ) &
    SUDO_REFRESH_PID=$!
    trap "kill $SUDO_REFRESH_PID 2>/dev/null || true" EXIT

    log "Sudo session established"
}

# ============================================================================
# Clean Function
# ============================================================================

clean_all() {
    header "Cleaning Build Artifacts"

    # Call each script's clean command
    "${SCRIPT_DIR}/build/kernel.sh" "${BOARD_NAME}" clean 2>/dev/null || true
    "${SCRIPT_DIR}/build/uboot.sh" "${BOARD_NAME}" clean 2>/dev/null || true
    "${SCRIPT_DIR}/build/rootfs.sh" "${BOARD_NAME}" clean 2>/dev/null || true
    "${SCRIPT_DIR}/device/assemble.sh" "${BOARD_NAME}" clean 2>/dev/null || true

    # Clean Docker image
    if command -v docker &>/dev/null; then
        if docker image inspect rk3568-debian-builder:latest &>/dev/null 2>&1; then
            info "Removing Docker build image..."
            docker rmi -f rk3568-debian-builder:latest 2>/dev/null || true
        fi
        docker image prune -f 2>/dev/null || true
    fi

    log "Clean complete"
}

# ============================================================================
# Build Stages (delegate to standalone scripts)
# ============================================================================

stage_kernel() {
    header "Stage 1: Kernel Build"

    local status
    status=$(check_kernel_artifacts | head -1)

    if [[ "$status" == "FOUND" ]]; then
        check_kernel_artifacts | tail -n +2
        echo ""

        if [[ "$AUTO_MODE" == "true" ]]; then
            log "Using existing kernel artifacts"
            return 0
        fi

        local answer
        answer=$(ask_yes_no "Rebuild kernel?" "n")
        [[ $answer =~ ^[Yy]$ ]] || { log "Skipping kernel build"; return 0; }
    fi

    info "Building kernel..."
    "${SCRIPT_DIR}/build/kernel.sh" "${BOARD_NAME}" build
}

stage_rootfs() {
    header "Stage 2: Rootfs Build"

    local status
    status=$(check_rootfs_artifact | head -1)

    if [[ "$status" == "FOUND" ]]; then
        check_rootfs_artifact | tail -n +2
        echo ""

        if [[ "$AUTO_MODE" == "true" ]]; then
            log "Using existing rootfs"
            return 0
        fi

        local answer
        answer=$(ask_yes_no "Rebuild rootfs?" "n")
        [[ $answer =~ ^[Yy]$ ]] || { log "Skipping rootfs build"; return 0; }
    fi

    info "Building rootfs..."
    "${SCRIPT_DIR}/build/rootfs.sh" "${BOARD_NAME}" build
}

stage_uboot() {
    [[ "$WITH_UBOOT" == "true" ]] || return 0

    header "Stage 2.5: U-Boot Build"

    local status
    status=$(check_uboot_artifacts | head -1)

    if [[ "$status" == "FOUND" ]]; then
        check_uboot_artifacts | tail -n +2
        echo ""

        if [[ "$AUTO_MODE" == "true" ]]; then
            log "Using existing U-Boot"
            return 0
        fi

        local answer
        answer=$(ask_yes_no "Rebuild U-Boot?" "n")
        [[ $answer =~ ^[Yy]$ ]] || { log "Skipping U-Boot build"; return 0; }
    fi

    info "Building U-Boot..."
    "${SCRIPT_DIR}/build/uboot.sh" "${BOARD_NAME}" build
}

stage_image() {
    header "Stage 3: Image Assembly"

    # Check dependencies
    local kernel_status rootfs_status
    kernel_status=$(check_kernel_artifacts | head -1)
    rootfs_status=$(check_rootfs_artifact | head -1)

    [[ "$kernel_status" == "FOUND" ]] || error "Kernel not found. Run: ./scripts/build/kernel.sh ${BOARD_NAME} build"
    [[ "$rootfs_status" == "FOUND" ]] || error "Rootfs not found. Run: ./scripts/build/rootfs.sh ${BOARD_NAME} build"

    local status
    status=$(check_image_artifacts | head -1)

    if [[ "$status" == "FOUND" ]]; then
        check_image_artifacts | tail -n +2
        echo ""

        if [[ "$AUTO_MODE" == "true" ]]; then
            log "Using existing image"
            return 0
        fi

        local answer
        answer=$(ask_yes_no "Rebuild image?" "n")
        [[ $answer =~ ^[Yy]$ ]] || { log "Skipping image assembly"; return 0; }
    fi

    info "Assembling image..."
    local args=""
    [[ "$WITH_UBOOT" == "true" ]] && args="--with-uboot"
    sudo "${SCRIPT_DIR}/device/assemble.sh" $args "${BOARD_NAME}" build
}

stage_flash() {
    [[ "$AUTO_MODE" == "true" ]] || return 0

    header "Stage 4: Flash to SD Card"

    local args="--yes"
    [[ -n "$SD_DEVICE" ]] && args="$args --device $SD_DEVICE"

    sudo "${SCRIPT_DIR}/device/flash-sd.sh" $args "${BOARD_NAME}" flash
}

# ============================================================================
# Banner and Summary
# ============================================================================

show_banner() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║     Debian Build System for Rockchip RK3568                   ║"
    printf "║     Kernel %-4s LTS + Debian 12 + XFCE Desktop             ║\n" "${KERNEL_VERSION}"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    info "Board: ${BOARD_DESC:-$BOARD_NAME}"
    if [[ "$AUTO_MODE" == "true" ]]; then
        info "Mode:  Auto (build missing, flash to SD)"
        info "Device: ${SD_DEVICE:-Auto-detect}"
    else
        info "Mode:  $([ "$NON_INTERACTIVE" == "true" ] && echo "Non-interactive" || echo "Interactive")"
    fi
    echo ""
}

show_summary() {
    header "Build Summary"

    echo -e "${BOLD}Artifacts:${NC}"
    echo ""

    echo -e "${BOLD}1. Kernel${NC}"
    check_kernel_artifacts | tail -n +2 || echo "   Not found"
    echo ""

    echo -e "${BOLD}2. Rootfs${NC}"
    check_rootfs_artifact | tail -n +2 || echo "   Not found"
    echo ""

    echo -e "${BOLD}3. Final Image${NC}"
    check_image_artifacts | tail -n +2 || echo "   Not found"
    echo ""

    local final_image
    final_image=$(ls -1t "${OUTPUT_DIR}"/rk3568-debian-*.img 2>/dev/null | grep -v '\.xz$' | head -1)

    if [[ -n "$final_image" ]]; then
        echo -e "${BOLD}Next Steps:${NC}"
        echo "  Flash to SD:  sudo ./scripts/device/flash-sd.sh ${BOARD_NAME} flash"
        echo "  Flash to eMMC: sudo ./scripts/device/flash-emmc.sh --latest"
        echo ""
        echo "  Default credentials: rock/rock (user), root/root (admin)"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    parse_args "$@"

    # Show help if no arguments
    if [[ -z "$BOARD" ]] && [[ "$CLEAN_MODE" != "true" ]]; then
        usage
        exit 0
    fi

    # Load board (use default if only --clean specified)
    BOARD="${BOARD:-sz3568-v1.2}"
    load_board "$BOARD" || exit 1

    # Clean only mode
    if [[ "$CLEAN_MODE" == "true" ]] && \
       [[ "$KERNEL_ONLY" != "true" ]] && \
       [[ "$ROOTFS_ONLY" != "true" ]] && \
       [[ "$UBOOT_ONLY" != "true" ]] && \
       [[ "$IMAGE_ONLY" != "true" ]] && \
       [[ "$AUTO_MODE" != "true" ]]; then
        setup_sudo
        clean_all
        exit 0
    fi

    show_banner
    setup_sudo

    # Clean before build if requested
    [[ "$CLEAN_MODE" == "true" ]] && clean_all

    # Single-stage builds
    if [[ "$KERNEL_ONLY" == "true" ]]; then
        stage_kernel
        log "Done!"
        exit 0
    fi

    if [[ "$ROOTFS_ONLY" == "true" ]]; then
        stage_rootfs
        log "Done!"
        exit 0
    fi

    if [[ "$UBOOT_ONLY" == "true" ]]; then
        WITH_UBOOT=true
        stage_uboot
        log "Done!"
        exit 0
    fi

    if [[ "$IMAGE_ONLY" == "true" ]]; then
        stage_image
        show_summary
        exit 0
    fi

    # Full workflow
    stage_kernel
    echo ""
    stage_rootfs
    echo ""
    stage_uboot
    echo ""
    stage_image
    echo ""
    stage_flash
    echo ""

    show_summary
    log "Build complete!"
}

main "$@"
