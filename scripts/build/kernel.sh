#!/bin/bash
# Standalone kernel build script
# Builds mainline kernel with custom DTBs and creates .deb packages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Configuration
KERNEL_VERSION="${KERNEL_VERSION:-6.12}"
KERNEL_BRANCH="v${KERNEL_VERSION}"
KERNEL_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
KERNEL_DIR="${PROJECT_ROOT}/kernel-${KERNEL_VERSION}"
CORES=$(nproc)

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <board> <command>

Build mainline kernel ${KERNEL_VERSION} LTS for RK3568 boards.

Commands:
  build       Build kernel and create .deb packages
  clean       Clean kernel build artifacts
  info        Show build configuration

Options:
  -h, --help  Show this help

Boards:
$(list_boards | sed 's/^/  /')

Examples:
  $(basename "$0") sz3568-v1.2 build
  $(basename "$0") rk3568_sz3568 build    # alias works too
  $(basename "$0") sz3568-v1.2 info
EOF
}

# ============================================================================
# Docker auto-detection
# ============================================================================

run_in_docker_if_needed() {
    # Skip if already in container
    [[ -f /.dockerenv ]] || [[ -n "$CONTAINER" ]] && return 0

    # Skip if Docker not available
    command -v docker &>/dev/null || {
        warn "Docker not found, running on host (requires build dependencies)"
        return 0
    }

    local docker_image="rk3568-debian-builder"

    # Build Docker image if needed
    if ! docker image inspect "${docker_image}:latest" &>/dev/null 2>&1; then
        info "Building Docker image (one-time setup)..."
        DOCKER_BUILDKIT=1 docker build -t "${docker_image}:latest" \
            -f "${PROJECT_ROOT}/Dockerfile" "${PROJECT_ROOT}"
    fi

    # Re-exec in Docker
    local user_id="${SUDO_UID:-$(id -u)}"
    local group_id="${SUDO_GID:-$(id -g)}"
    local tty_flags="-i"
    [[ -t 0 ]] && tty_flags="-it"

    info "Running build in Docker container..."
    exec docker run --rm ${tty_flags} \
        -v "${PROJECT_ROOT}:/work" \
        -e CONTAINER=1 \
        -e SKIP_KERNEL_UPDATE="${SKIP_KERNEL_UPDATE:-1}" \
        -w /work \
        -u "${user_id}:${group_id}" \
        "${docker_image}:latest" \
        "/work/scripts/build/kernel.sh" "$@"
}

# ============================================================================
# Build functions
# ============================================================================

check_deps() {
    # Skip in Docker (dependencies pre-installed)
    [[ -f /.dockerenv ]] || [[ -n "$CONTAINER" ]] && return 0

    log "Checking dependencies..."
    local deps=(git make gcc g++ bison flex libssl-dev libelf-dev bc kmod debhelper)
    local missing=()

    for dep in "${deps[@]}"; do
        dpkg -l 2>/dev/null | grep -q "^ii  $dep " || missing+=("$dep")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}\nInstall with: sudo apt install ${missing[*]}"
    fi

    command -v aarch64-linux-gnu-gcc &>/dev/null || \
        error "Missing aarch64 cross-compiler\nInstall with: sudo apt install gcc-aarch64-linux-gnu"
}

clone_kernel() {
    log "Cloning kernel ${KERNEL_VERSION}..."

    if [[ ! -d "${KERNEL_DIR}" ]]; then
        git clone --depth=1 --single-branch --branch="${KERNEL_BRANCH}" \
            "${KERNEL_REPO}" "${KERNEL_DIR}"
    else
        log "Kernel already cloned at ${KERNEL_DIR}"
    fi
}

apply_patches() {
    local patch_dir="${PROJECT_ROOT}/external/custom/patches/linux"
    [[ -d "$patch_dir" ]] || return 0

    log "Applying kernel patches..."
    cd "${KERNEL_DIR}"

    # Reset to clean state
    git checkout -- . 2>/dev/null || true
    git clean -fd 2>/dev/null || true

    for patch in "${patch_dir}"/*.patch; do
        [[ -f "$patch" ]] || continue
        local name="$(basename "$patch")"
        log "Applying: ${name}"

        if patch -p1 --dry-run < "$patch" &>/dev/null; then
            patch -p1 < "$patch"
        elif patch -p1 -F3 --dry-run < "$patch" &>/dev/null; then
            warn "Using fuzzy matching for ${name}"
            patch -p1 -F3 < "$patch"
        else
            error "Patch ${name} FAILED to apply"
        fi
    done

    cd "${PROJECT_ROOT}"
}

copy_custom_files() {
    log "Copying custom DTBs and drivers..."

    local dts_src="${PROJECT_ROOT}/external/custom/board/rk3568/dts/rockchip"
    local dts_dst="${KERNEL_DIR}/arch/arm64/boot/dts/rockchip"

    # Copy device trees
    if [[ -d "$dts_src" ]]; then
        cp -v "${dts_src}"/*.dts "${dts_dst}/" 2>/dev/null || true
        cp -v "${dts_src}"/*.dtsi "${dts_dst}/" 2>/dev/null || true

        # Add to Makefile
        local makefile="${dts_dst}/Makefile"
        for dts in "${dts_src}"/*.dts; do
            [[ -f "$dts" ]] || continue
            local dtb_name="$(basename "$dts" .dts)"
            if ! grep -q "${dtb_name}.dtb" "$makefile" 2>/dev/null; then
                echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += ${dtb_name}.dtb" >> "$makefile"
                log "Added ${dtb_name}.dtb to Makefile"
            fi
        done
    fi

    # Copy dt-bindings
    if [[ -d "${PROJECT_ROOT}/external/custom/board/rk3568/dt-bindings" ]]; then
        cp -rv "${PROJECT_ROOT}/external/custom/board/rk3568/dt-bindings"/* \
            "${KERNEL_DIR}/include/dt-bindings/"
    fi

    # Copy MAXIO PHY driver
    local maxio_src="${PROJECT_ROOT}/external/custom/board/rk3568/drivers/maxio.c"
    if [[ -f "$maxio_src" ]]; then
        log "Copying MAXIO PHY driver..."
        cp -v "$maxio_src" "${KERNEL_DIR}/drivers/net/phy/"

        # Add to Kconfig
        local kconfig="${KERNEL_DIR}/drivers/net/phy/Kconfig"
        if ! grep -q "config MAXIO_PHY" "$kconfig" 2>/dev/null; then
            sed -i '/config MOTORCOMM_PHY/,/Currently supports/{
                /Currently supports/a\
\
config MAXIO_PHY\
\ttristate "Maxio PHYs"\
\thelp\
\t  Enables support for Maxio network PHYs.\
\t  Currently supports the MAE0621A Gigabit PHY.
            }' "$kconfig"
        fi

        # Add to Makefile
        local phy_makefile="${KERNEL_DIR}/drivers/net/phy/Makefile"
        if ! grep -q "maxio.o" "$phy_makefile" 2>/dev/null; then
            sed -i '/motorcomm.o/a\obj-$(CONFIG_MAXIO_PHY)\t\t+= maxio.o' "$phy_makefile"
        fi
    fi
}

configure_kernel() {
    log "Configuring kernel..."
    cd "${KERNEL_DIR}"

    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- mrproper || true
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig

    # Apply config fragment
    local fragment="${PROJECT_ROOT}/external/custom/board/rk3568/kernel.config"
    if [[ -f "$fragment" ]]; then
        log "Merging kernel config fragment..."
        cat "$fragment" >> .config
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
    fi

    cd "${PROJECT_ROOT}"
}

build_kernel() {
    log "Building kernel with ${CORES} cores..."
    cd "${KERNEL_DIR}"

    make -j"${CORES}" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        Image dtbs modules || error "Kernel build failed"

    # Verify DTB was built
    if [[ -f "arch/arm64/boot/dts/rockchip/${DTB_NAME}.dtb" ]]; then
        log "DTB built: ${DTB_NAME}.dtb"
    else
        warn "DTB ${DTB_NAME}.dtb not found!"
    fi

    cd "${PROJECT_ROOT}"
}

build_deb_packages() {
    log "Creating .deb packages..."
    cd "${KERNEL_DIR}"

    # Clean previous artifacts
    rm -f ../linux-*.deb ../linux-*.changes ../linux-*.buildinfo 2>/dev/null || true

    local version
    version=$(make -s kernelrelease)
    local pkg_version="1.0.0-rockchip-${BOARD_NAME//_/-}"

    log "Kernel version: ${version}"
    log "Package version: ${pkg_version}"

    KDEB_PKGVERSION="${pkg_version}" \
    DPKG_FLAGS="-d" \
    make -j"${CORES}" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        bindeb-pkg || error "Package build failed"

    cd "${PROJECT_ROOT}"

    # Move packages to output
    mkdir -p "${PROJECT_ROOT}/output/kernel-debs"
    mv -v linux-*.deb "${PROJECT_ROOT}/output/kernel-debs/" 2>/dev/null || true

    log "Kernel .deb packages created in output/kernel-debs/"
    ls -lh "${PROJECT_ROOT}/output/kernel-debs/"

    # Write checksum for build tracking
    local image_deb
    image_deb=$(ls -1t "${PROJECT_ROOT}/output/kernel-debs"/linux-image-*.deb 2>/dev/null | head -1)
    if [[ -n "$image_deb" ]]; then
        local checksum
        checksum=$(write_component_checksum "kernel" "$image_deb")
        log "Kernel checksum: ${checksum:0:16}..."
    fi
}

# ============================================================================
# Commands
# ============================================================================

cmd_build() {
    header "Building Kernel ${KERNEL_VERSION} for ${BOARD_NAME}"
    info "DTB: ${DTB_NAME}.dtb"

    run_in_docker_if_needed "$BOARD_NAME" build

    check_deps
    clone_kernel
    apply_patches
    copy_custom_files
    configure_kernel
    build_kernel
    build_deb_packages

    log "Kernel build complete!"
}

cmd_clean() {
    header "Cleaning Kernel Artifacts"

    if [[ -d "${KERNEL_DIR}" ]]; then
        info "Removing ${KERNEL_DIR}..."
        rm -rf "${KERNEL_DIR}"
    fi

    if [[ -d "${PROJECT_ROOT}/output/kernel-debs" ]]; then
        info "Removing output/kernel-debs/..."
        rm -rf "${PROJECT_ROOT}/output/kernel-debs"
    fi

    rm -f "${PROJECT_ROOT}"/linux-*.deb 2>/dev/null || true
    rm -f "${PROJECT_ROOT}"/linux-*.changes 2>/dev/null || true
    rm -f "${PROJECT_ROOT}"/linux-*.buildinfo 2>/dev/null || true

    log "Clean complete"
}

cmd_info() {
    header "Kernel Build Configuration"

    show_board_info

    echo ""
    info "Kernel Configuration:"
    kv "Version" "${KERNEL_VERSION}"
    kv "Branch" "${KERNEL_BRANCH}"
    kv "Source" "${KERNEL_DIR}"
    kv "DTB" "${DTB_NAME}.dtb"

    echo ""
    info "Artifact Status:"
    check_kernel_artifacts || true
}

# ============================================================================
# Main
# ============================================================================

main() {
    local board=""
    local command=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
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
