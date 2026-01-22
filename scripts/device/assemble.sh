#!/bin/bash
# Standalone image assembly script
# Assembles kernel, rootfs, and optionally U-Boot into bootable image

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Configuration
IMAGE_SIZE="6144"  # 6GB
BOOT_SIZE="256"    # 256MB boot partition
KERNEL_VERSION="${KERNEL_VERSION:-6.12}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <board> <command>

Assemble bootable Debian image for RK3568 boards.

Commands:
  build       Assemble the image
  clean       Remove image work files
  info        Show configuration and artifact status

Options:
  --with-uboot    Include U-Boot in image (requires sudo)
  -h, --help      Show this help

Boards:
$(list_boards | sed 's/^/  /')

Examples:
  sudo $(basename "$0") sz3568-v1.2 build
  sudo $(basename "$0") --with-uboot sz3568-v1.2 build
  $(basename "$0") sz3568-v1.2 info

Output:
  output/rk3568-debian-YYYYMMDDHHMM.img      Raw image (6GB)
  output/rk3568-debian-YYYYMMDDHHMM.img.xz   Compressed (~400MB)
EOF
}

# ============================================================================
# Commands
# ============================================================================

cmd_build() {
    header "Assembling Image for ${BOARD_NAME}"

    # Check if running as root (required for loopback mounts)
    if [[ $EUID -ne 0 ]] && [[ ! -f /.dockerenv ]]; then
        error "Image assembly requires root. Run with: sudo $(basename "$0") $BOARD_NAME build"
    fi

    # Check dependencies
    local kernel_output rootfs_output kernel_status rootfs_status
    kernel_output=$(check_kernel_artifacts 2>/dev/null) || true
    rootfs_output=$(check_rootfs_artifact 2>/dev/null) || true
    kernel_status=$(echo "$kernel_output" | head -1)
    rootfs_status=$(echo "$rootfs_output" | head -1)

    [[ "$kernel_status" == "FOUND" ]] || error "Kernel artifacts not found. Run: ./scripts/build/kernel.sh $BOARD_NAME build"
    [[ "$rootfs_status" == "FOUND" ]] || error "Rootfs not found. Run: ./scripts/build/rootfs.sh $BOARD_NAME build"

    if [[ "$WITH_UBOOT" == "true" ]]; then
        local uboot_output uboot_status
        uboot_output=$(check_uboot_artifacts 2>/dev/null) || true
        uboot_status=$(echo "$uboot_output" | head -1)
        [[ "$uboot_status" == "FOUND" ]] || error "U-Boot not found. Run: ./scripts/build/uboot.sh $BOARD_NAME build"
        info "U-Boot will be included in image"
    fi

    # Delegate to existing assembler
    local args=""
    [[ "$WITH_UBOOT" == "true" ]] && args="--with-uboot"

    KERNEL_VERSION="${KERNEL_VERSION}" "${PROJECT_ROOT}/scripts/assemble-debian-image.sh" $args "${BOARD_NAME}"

    log "Image assembly complete!"
}

cmd_clean() {
    header "Cleaning Image Artifacts"

    local work_dir="${PROJECT_ROOT}/output/image-work"
    if [[ -d "$work_dir" ]]; then
        info "Removing ${work_dir}..."
        sudo rm -rf "$work_dir"
    fi

    # List images but don't delete them automatically
    local images
    images=$(ls -1 "${PROJECT_ROOT}/output"/rk3568-debian-*.img* 2>/dev/null | wc -l)
    if [[ $images -gt 0 ]]; then
        info "Found $images image file(s) in output/"
        ls -lh "${PROJECT_ROOT}/output"/rk3568-debian-*.img* 2>/dev/null | head -5
        warn "Images not deleted automatically. Remove manually if needed."
    fi

    log "Clean complete"
}

cmd_info() {
    header "Image Assembly Configuration"

    show_board_info

    echo ""
    info "Image Configuration:"
    kv "Size" "${IMAGE_SIZE}MB (${BOOT_SIZE}MB boot + rootfs)"
    kv "Kernel" "${KERNEL_VERSION}"
    kv "U-Boot" "$([ "$WITH_UBOOT" == "true" ] && echo "INCLUDED" || echo "Not included")"

    echo ""
    info "Required Artifacts:"
    local ko ro uo
    ko=$(check_kernel_artifacts 2>/dev/null) || true
    ro=$(check_rootfs_artifact 2>/dev/null) || true
    uo=$(check_uboot_artifacts 2>/dev/null) || true
    echo "  Kernel: $(echo "$ko" | head -1)"
    echo "  Rootfs: $(echo "$ro" | head -1)"
    echo "  U-Boot: $(echo "$uo" | head -1)"

    echo ""
    info "Output Images:"
    check_image_artifacts 2>/dev/null || true
}

# ============================================================================
# Main
# ============================================================================

main() {
    local board=""
    local command=""
    WITH_UBOOT=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --with-uboot)
                WITH_UBOOT=true
                shift
                ;;
            -*)
                error "Unknown option: $1"
                ;;
            *)
                if [[ -z "$board" ]]; then
                    board="$1"
                elif [[ -z "$command" ]]; then
                    command="$1"
                else
                    error "Too many arguments"
                fi
                shift
                ;;
        esac
    done

    # Require board and command
    if [[ -z "$board" ]] || [[ -z "$command" ]]; then
        usage
        exit 1
    fi

    # Load board configuration
    load_board "$board" || exit 1

    # Execute command
    case "$command" in
        build) cmd_build ;;
        clean) cmd_clean ;;
        info)  cmd_info ;;
        *)     error "Unknown command: $command" ;;
    esac
}

main "$@"
