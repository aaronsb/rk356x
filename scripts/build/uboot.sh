#!/bin/bash
# Standalone U-Boot build script
# Builds mainline U-Boot for RK3568 boards

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Configuration
UBOOT_DIR="${PROJECT_ROOT}/u-boot-mainline"
RKBIN_DIR="${PROJECT_ROOT}/rkbin"
UBOOT_REPO="https://source.denx.de/u-boot/u-boot.git"
UBOOT_BRANCH="master"
DEFAULT_BOOTCMD="run distro_bootcmd"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <board> <command>

Build mainline U-Boot for RK3568 boards.

Commands:
  build       Build U-Boot and create binary
  clean       Clean U-Boot build artifacts
  info        Show build configuration

Options:
  --bootcmd CMD   Custom bootcmd (default: "run distro_bootcmd")
  -h, --help      Show this help

Boards:
$(list_boards | sed 's/^/  /')

Examples:
  $(basename "$0") sz3568-v1.2 build
  $(basename "$0") rk3568_sz3568 build    # alias works too
  $(basename "$0") --bootcmd "run mmc_boot" sz3568-v1.2 build

Output:
  output/uboot/u-boot-rockchip.bin   Unified U-Boot image (TPL+SPL+ATF+U-Boot)
EOF
}

# ============================================================================
# Docker auto-detection
# ============================================================================

run_in_docker_if_needed() {
    [[ -f /.dockerenv ]] || [[ -n "$CONTAINER" ]] && return 0

    command -v docker &>/dev/null || {
        warn "Docker not found, running on host"
        return 0
    }

    local docker_image="rk3568-debian-builder"

    if ! docker image inspect "${docker_image}:latest" &>/dev/null 2>&1; then
        info "Building Docker image (one-time setup)..."
        DOCKER_BUILDKIT=1 docker build -t "${docker_image}:latest" \
            -f "${PROJECT_ROOT}/Dockerfile" "${PROJECT_ROOT}"
    fi

    local user_id="${SUDO_UID:-$(id -u)}"
    local group_id="${SUDO_GID:-$(id -g)}"
    local tty_flags="-i"
    [[ -t 0 ]] && tty_flags="-it"

    info "Running build in Docker container..."
    exec docker run --rm ${tty_flags} \
        -v "${PROJECT_ROOT}:${PROJECT_ROOT}" \
        -w "${PROJECT_ROOT}" \
        -u "${user_id}:${group_id}" \
        -e CONTAINER=1 \
        -e BOOTCMD="${BOOTCMD}" \
        "${docker_image}:latest" \
        "${SCRIPT_DIR}/uboot.sh" "$@"
}

# ============================================================================
# Build functions
# ============================================================================

clone_uboot() {
    log "Cloning U-Boot from ${UBOOT_REPO}..."

    if [[ -d "${UBOOT_DIR}" ]]; then
        log "U-Boot directory exists"
        cd "${UBOOT_DIR}"
        git fetch origin "${UBOOT_BRANCH}" || true
    else
        git clone --depth 1 -b "${UBOOT_BRANCH}" "${UBOOT_REPO}" "${UBOOT_DIR}"
        cd "${UBOOT_DIR}"
    fi

    log "U-Boot source ready: $(git describe --tags 2>/dev/null || git rev-parse --short HEAD)"
    cd "${PROJECT_ROOT}"
}

apply_patches() {
    local patch_dir="${PROJECT_ROOT}/external/custom/patches/u-boot"
    [[ -d "$patch_dir" ]] || return 0
    [[ -n "$(ls -A "$patch_dir"/*.patch 2>/dev/null)" ]] || return 0

    cd "${UBOOT_DIR}"

    # Reset to clean state
    git checkout -- . 2>/dev/null || true
    git clean -fdx 2>/dev/null || true

    log "Applying U-Boot patches..."
    for patch in "$patch_dir"/*.patch; do
        [[ -f "$patch" ]] || continue
        local name="$(basename "$patch")"
        log "Applying: ${name}"
        git apply "$patch" || warn "Failed to apply: ${name}"
    done

    cd "${PROJECT_ROOT}"
}

merge_config() {
    local config_dir="${PROJECT_ROOT}/external/custom/board/rk3568/u-boot"
    local video_config="${config_dir}/video.config"

    [[ -f "$video_config" ]] || return 0

    cd "${UBOOT_DIR}"
    log "Merging U-Boot config fragments..."

    if [[ -f "scripts/kconfig/merge_config.sh" ]]; then
        KCONFIG_CONFIG=.config scripts/kconfig/merge_config.sh -m .config "$video_config"
        make olddefconfig
    else
        cat "$video_config" >> .config
        make olddefconfig
    fi

    cd "${PROJECT_ROOT}"
}

build_uboot() {
    log "Building U-Boot..."

    # Verify rkbin exists
    if [[ ! -d "${RKBIN_DIR}" ]]; then
        error "rkbin directory not found. Run: git submodule update --init"
    fi

    cd "${UBOOT_DIR}"

    # Clean previous build
    make distclean 2>/dev/null || git clean -fdx 2>/dev/null || true

    # Apply patches
    apply_patches

    # Configure - use UBOOT_DEFCONFIG from board.conf
    local defconfig="${UBOOT_DEFCONFIG:-evb-rk3568}_defconfig"
    log "Using defconfig: ${defconfig}"
    make "${defconfig}"

    # Merge custom config
    merge_config

    # Set ATF and DDR blobs
    export BL31="${RKBIN_DIR}/bin/rk35/rk3568_bl31_ultra_v2.17.elf"
    export ROCKCHIP_TPL="${RKBIN_DIR}/bin/rk35/rk3568_ddr_1560MHz_v1.23.bin"

    [[ -f "${BL31}" ]] || error "BL31 blob not found: ${BL31}"
    [[ -f "${ROCKCHIP_TPL}" ]] || error "DDR init blob not found: ${ROCKCHIP_TPL}"

    log "Using blobs:"
    info "  BL31: $(basename ${BL31})"
    info "  DDR:  $(basename ${ROCKCHIP_TPL})"

    # Build
    make -j$(nproc) CROSS_COMPILE=aarch64-linux-gnu-

    [[ -f "u-boot-rockchip.bin" ]] || error "Build failed - u-boot-rockchip.bin not found"

    log "U-Boot compiled: u-boot-rockchip.bin ($(du -h u-boot-rockchip.bin | cut -f1))"
    cd "${PROJECT_ROOT}"
}

install_output() {
    log "Installing U-Boot to output directory..."

    mkdir -p "${OUTPUT_DIR}/uboot"
    cp "${UBOOT_DIR}/u-boot-rockchip.bin" "${OUTPUT_DIR}/uboot/"

    # Create flash script
    cat > "${OUTPUT_DIR}/uboot/flash-uboot.sh" << 'FLASHEOF'
#!/bin/bash
# Flash mainline U-Boot to SD card or eMMC
set -e

if [ $# -ne 1 ]; then
    echo "Usage: sudo $0 /dev/sdX"
    exit 1
fi

DEVICE=$1
[ -b "$DEVICE" ] || { echo "Error: $DEVICE is not a block device"; exit 1; }

echo "WARNING: This will flash U-Boot to $DEVICE"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

echo "Flashing u-boot-rockchip.bin to sector 64..."
dd if=u-boot-rockchip.bin of=$DEVICE seek=64 conv=fsync
sync

echo "Done! U-Boot flashed to $DEVICE"
FLASHEOF

    chmod +x "${OUTPUT_DIR}/uboot/flash-uboot.sh"

    log "U-Boot installed to ${OUTPUT_DIR}/uboot/"
}

# ============================================================================
# Commands
# ============================================================================

cmd_build() {
    header "Building U-Boot for ${BOARD_NAME}"
    info "Bootcmd: ${BOOTCMD}"

    run_in_docker_if_needed "$BOARD_NAME" build

    clone_uboot
    build_uboot
    install_output

    log "U-Boot build complete!"
}

cmd_clean() {
    header "Cleaning U-Boot Artifacts"

    if [[ -d "${UBOOT_DIR}" ]]; then
        info "Removing ${UBOOT_DIR}..."
        rm -rf "${UBOOT_DIR}"
    fi

    if [[ -d "${OUTPUT_DIR}/uboot" ]]; then
        info "Removing output/uboot/..."
        rm -rf "${OUTPUT_DIR}/uboot"
    fi

    log "Clean complete"
}

cmd_info() {
    header "U-Boot Build Configuration"

    show_board_info

    echo ""
    info "U-Boot Configuration:"
    kv "Source" "${UBOOT_DIR}"
    kv "Repo" "${UBOOT_REPO}"
    kv "Branch" "${UBOOT_BRANCH}"
    kv "Defconfig" "${UBOOT_DEFCONFIG:-evb-rk3568}_defconfig"
    kv "Bootcmd" "${BOOTCMD}"

    echo ""
    info "Artifact Status:"
    check_uboot_artifacts || true
}

# ============================================================================
# Main
# ============================================================================

main() {
    local board=""
    local command=""
    BOOTCMD="${BOOTCMD:-$DEFAULT_BOOTCMD}"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --bootcmd)
                BOOTCMD="$2"
                shift 2
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
