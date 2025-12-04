#!/bin/bash
set -e

# Rockchip Kernel Build Script
# Builds mainline kernel 6.12 LTS with custom DTBs and creates .deb packages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Auto-use Docker if not already in container
if [ ! -f /.dockerenv ] && [ -z "$CONTAINER" ]; then
    if command -v docker &>/dev/null; then
        # Build Docker image if needed
        DOCKER_IMAGE="rk3568-debian-builder"
        if ! docker image inspect "${DOCKER_IMAGE}:latest" &>/dev/null 2>&1; then
            echo "==> Building Docker image (one-time setup, with apt caching)..."
            DOCKER_BUILDKIT=1 docker build -t "${DOCKER_IMAGE}:latest" -f "${PROJECT_ROOT}/Dockerfile" "${PROJECT_ROOT}"
        fi

        # Re-exec this script in Docker
        # Use SUDO_UID/SUDO_GID if running via sudo, otherwise use current user
        USER_ID="${SUDO_UID:-$(id -u)}"
        GROUP_ID="${SUDO_GID:-$(id -g)}"

        echo "==> Running build in Docker container..."
        exec docker run --rm -t \
            -v "${PROJECT_ROOT}:/work" \
            -e CONTAINER=1 \
            -w /work \
            -u "${USER_ID}:${GROUP_ID}" \
            "${DOCKER_IMAGE}:latest" \
            "/work/scripts/$(basename "$0")" "$@"
    else
        echo "⚠ Docker not found, running on host (requires build dependencies installed)"
    fi
fi

# Configuration
KERNEL_VERSION="6.12"
KERNEL_BRANCH="v6.12"
KERNEL_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
KERNEL_DIR="${PROJECT_ROOT}/kernel-${KERNEL_VERSION}"

BOARD="${1:-rk3568_sz3568}"
DEFCONFIG="defconfig"  # Mainline uses generic defconfig, then we customize
CORES=$(nproc)

# Board-specific DTB
case "${BOARD}" in
    rk3568_sz3568)
        DTB_NAME="rk3568-sz3568"
        ;;
    rk3568_custom)
        DTB_NAME="rk3568-dc-a568"
        ;;
    *)
        echo "Unknown board: ${BOARD}"
        exit 1
        ;;
esac

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

# Redirect output in quiet mode
quiet_run() {
    if [ "$QUIET_MODE" = "true" ]; then
        "$@" 2>&1 | grep -v "^find:" | grep -v "^scripts/config:" || true
    else
        "$@"
    fi
}

check_deps() {
    # Skip dependency check if running in Docker (dependencies are in Dockerfile)
    if [ -f /.dockerenv ] || [ -n "$CONTAINER" ]; then
        log "Running in Docker container (dependencies pre-installed)"
        return 0
    fi

    log "Checking dependencies..."

    local deps=(git make gcc g++ bison flex libssl-dev libelf-dev bc kmod debhelper)
    local missing=()

    for dep in "${deps[@]}"; do
        if ! dpkg -l 2>/dev/null | grep -q "^ii  $dep "; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        warn "Missing dependencies: ${missing[*]}"
        log "Install with: sudo apt install ${missing[*]}"
        error "Please install missing dependencies first"
    fi

    # Check for cross-compiler
    if ! command -v aarch64-linux-gnu-gcc &>/dev/null; then
        error "Missing aarch64 cross-compiler\nInstall with: sudo apt install gcc-aarch64-linux-gnu"
    fi
}

clone_kernel() {
    log "Cloning Rockchip kernel ${KERNEL_VERSION}..."

    if [ ! -d "${KERNEL_DIR}" ]; then
        git clone --depth=1 --single-branch --branch="${KERNEL_BRANCH}" \
            "${KERNEL_REPO}" "${KERNEL_DIR}"
    else
        log "Kernel already cloned"

        # Skip update prompt if running non-interactively (in Docker or background)
        if [ -t 0 ]; then
            read -p "Update kernel source? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                cd "${KERNEL_DIR}"
                log "Cleaning kernel repo state..."
                git clean -fdx 2>/dev/null || true
                git reset --hard 2>/dev/null || true
                log "Fetching latest kernel..."
                git fetch origin "${KERNEL_BRANCH}"
                git checkout "${KERNEL_BRANCH}" 2>/dev/null || git checkout -b "${KERNEL_BRANCH}" "origin/${KERNEL_BRANCH}"
                git reset --hard "origin/${KERNEL_BRANCH}"
                cd "${PROJECT_ROOT}"
            fi
        else
            log "Non-interactive mode: skipping update (using existing kernel source)"
        fi
    fi
}

copy_custom_files() {
    log "Copying custom DTBs and drivers..."

    # Apply patches FIRST (before our custom additions)
    if [ -d "${PROJECT_ROOT}/external/custom/patches/linux" ]; then
        log "Applying kernel patches..."
        cd "${KERNEL_DIR}"

        # Reset any previously applied patches
        git checkout -- . 2>/dev/null || true

        for patch in "${PROJECT_ROOT}"/external/custom/patches/linux/*.patch; do
            if [ -f "$patch" ]; then
                log "Applying: $(basename "$patch")"
                if patch -p1 --dry-run < "$patch" &>/dev/null; then
                    patch -p1 < "$patch"
                else
                    warn "Patch $(basename "$patch") already applied or failed"
                fi
            fi
        done
        cd "${PROJECT_ROOT}"
    else
        warn "No patches found in external/custom/patches/linux"
    fi

    # Copy custom DTBs
    if [ -d "${PROJECT_ROOT}/external/custom/board/rk3568/dts/rockchip" ]; then
        log "Copying device trees..."
        cp -v "${PROJECT_ROOT}"/external/custom/board/rk3568/dts/rockchip/*.dts \
            "${KERNEL_DIR}/arch/arm64/boot/dts/rockchip/"
        # Also copy dtsi files if they exist
        if ls "${PROJECT_ROOT}"/external/custom/board/rk3568/dts/rockchip/*.dtsi >/dev/null 2>&1; then
            cp -v "${PROJECT_ROOT}"/external/custom/board/rk3568/dts/rockchip/*.dtsi \
                "${KERNEL_DIR}/arch/arm64/boot/dts/rockchip/"
        fi
    else
        warn "No custom DTBs found in external/custom/board/rk3568/dts/rockchip"
    fi

    # Copy vendor dt-bindings headers (for mainline kernel compatibility)
    if [ -d "${PROJECT_ROOT}/external/custom/board/rk3568/dt-bindings" ]; then
        log "Copying vendor dt-bindings headers..."
        cp -rv "${PROJECT_ROOT}"/external/custom/board/rk3568/dt-bindings/* \
            "${KERNEL_DIR}/include/dt-bindings/"
    fi

    # Continue with DTB Makefile additions
    if [ -d "${PROJECT_ROOT}/external/custom/board/rk3568/dts/rockchip" ]; then
        # Add custom DTBs to Makefile so they get compiled
        log "Adding custom DTBs to Makefile..."
        local makefile_path="${KERNEL_DIR}/arch/arm64/boot/dts/rockchip/Makefile"

        if [ ! -f "$makefile_path" ]; then
            error "Makefile not found at $makefile_path - kernel may not be cloned correctly"
        fi

        for dts in "${PROJECT_ROOT}"/external/custom/board/rk3568/dts/rockchip/*.dts; do
            if [ -f "$dts" ]; then
                local dtb_name=$(basename "$dts" .dts)
                # Check if already in Makefile
                if ! grep -q "${dtb_name}.dtb" "$makefile_path" 2>/dev/null; then
                    echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += ${dtb_name}.dtb" >> "$makefile_path"
                    if [ $? -eq 0 ]; then
                        log "✓ Added ${dtb_name}.dtb to Makefile"
                    else
                        error "Failed to add ${dtb_name}.dtb to Makefile"
                    fi
                else
                    log "✓ ${dtb_name}.dtb already in Makefile"
                fi
            fi
        done
    fi

    # Copy custom PHY drivers
    if [ -f "${PROJECT_ROOT}/external/custom/board/rk3568/drivers/maxio.c" ]; then
        log "Copying MAXIO PHY driver..."
        cp -v "${PROJECT_ROOT}/external/custom/board/rk3568/drivers/maxio.c" \
            "${KERNEL_DIR}/drivers/net/phy/"

        # Add to PHY Kconfig
        local kconfig="${KERNEL_DIR}/drivers/net/phy/Kconfig"
        if ! grep -q "config MAXIO_PHY" "$kconfig" 2>/dev/null; then
            log "Adding MAXIO_PHY to Kconfig..."
            # Find MOTORCOMM_PHY and add MAXIO_PHY after it
            sed -i '/config MOTORCOMM_PHY/,/Currently supports/{
                /Currently supports/a\
\
config MAXIO_PHY\
\ttristate "Maxio PHYs"\
\thelp\
\t  Enables support for Maxio network PHYs.\
\t  Currently supports the MAE0621A Gigabit PHY.
            }' "$kconfig"
            log "✓ Added MAXIO_PHY to Kconfig"
        else
            log "✓ MAXIO_PHY already in Kconfig"
        fi

        # Add to PHY Makefile
        local makefile="${KERNEL_DIR}/drivers/net/phy/Makefile"
        if ! grep -q "maxio.o" "$makefile" 2>/dev/null; then
            log "Adding maxio.o to Makefile..."
            sed -i '/motorcomm.o/a\obj-$(CONFIG_MAXIO_PHY)\t\t+= maxio.o' "$makefile"
            log "✓ Added maxio.o to Makefile"
        else
            log "✓ maxio.o already in Makefile"
        fi
    fi
}

configure_kernel() {
    log "Configuring kernel..."

    cd "${KERNEL_DIR}"

    # Clean previous config
    [ "$QUIET_MODE" = "true" ] && echo -e "${YELLOW}▸${NC} Cleaning previous kernel config"
    quiet_run make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- mrproper || true

    # Start with rockchip defconfig
    [ "$QUIET_MODE" = "true" ] && echo -e "${YELLOW}▸${NC} Applying ${DEFCONFIG}"
    quiet_run make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- "${DEFCONFIG}"

    # Apply config fragment if exists
    if [ -f "${PROJECT_ROOT}/external/custom/board/rk3568/kernel.config" ]; then
        log "Merging kernel config fragment..."

        # Append fragment to .config
        cat "${PROJECT_ROOT}/external/custom/board/rk3568/kernel.config" >> .config

        # Resolve dependencies
        [ "$QUIET_MODE" = "true" ] && echo -e "${YELLOW}▸${NC} Resolving config dependencies"
        quiet_run make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
    fi

    # GPU config is managed via kernel.config fragment
    # (Don't force Mali or Panfrost here - let the fragment decide)

    # Update config with new settings
    [ "$QUIET_MODE" = "true" ] && echo -e "${YELLOW}▸${NC} Finalizing kernel configuration"
    quiet_run make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

    log "Kernel configuration complete"
    cd "${PROJECT_ROOT}"
}

build_kernel() {
    log "Building kernel with ${CORES} cores..."

    cd "${KERNEL_DIR}"

    # Build kernel image, DTBs, and modules
    [ "$QUIET_MODE" = "true" ] && echo -e "${YELLOW}▸${NC} Compiling kernel (Image + DTBs + modules)"
    quiet_run make -j"${CORES}" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        Image dtbs modules || error "Kernel build failed"

    log "✓ Kernel build complete"

    # Show built DTB
    if [ -f "arch/arm64/boot/dts/rockchip/${DTB_NAME}.dtb" ]; then
        log "✓ DTB built: ${DTB_NAME}.dtb"
    else
        warn "DTB ${DTB_NAME}.dtb not found!"
    fi

    cd "${PROJECT_ROOT}"
}

build_deb_packages() {
    log "Creating .deb packages..."

    cd "${KERNEL_DIR}"

    # Remove any existing build artifacts from parent directory
    # (might be root-owned from previous builds)
    rm -f ../linux-*.deb ../linux-*.changes ../linux-*.buildinfo 2>/dev/null || true

    # Set version for packages
    local version=$(make -s kernelrelease)
    # Replace underscores with hyphens (Debian package versions can't have underscores)
    local pkg_version="1.0.0-rockchip-${BOARD//_/-}"

    log "Kernel version: ${version}"
    log "Package version: ${pkg_version}"

    # Build deb packages (creates in parent directory)
    [ "$QUIET_MODE" = "true" ] && echo -e "${YELLOW}▸${NC} Building .deb packages"
    KDEB_PKGVERSION="${pkg_version}" \
    quiet_run make -j"${CORES}" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        bindeb-pkg || error "Package build failed"

    cd "${PROJECT_ROOT}"

    # Move packages to a known location
    mkdir -p "${PROJECT_ROOT}/output/kernel-debs"
    mv -v linux-*.deb "${PROJECT_ROOT}/output/kernel-debs/" 2>/dev/null || true

    log "✓ Kernel .deb packages created in output/kernel-debs/"
    ls -lh "${PROJECT_ROOT}/output/kernel-debs/"
}

install_to_rootfs() {
    local rootfs_dir="${PROJECT_ROOT}/rootfs/work"

    if [ ! -d "${rootfs_dir}" ]; then
        warn "Rootfs not found at ${rootfs_dir}"
        warn "Build rootfs first with: ./scripts/build-debian-rootfs.sh"
        return
    fi

    log "Installing kernel .debs to rootfs..."

    # Copy .deb packages to rootfs
    sudo mkdir -p "${rootfs_dir}/tmp/kernel-debs"
    sudo cp "${PROJECT_ROOT}"/output/kernel-debs/linux-image-*.deb "${rootfs_dir}/tmp/kernel-debs/"
    sudo cp "${PROJECT_ROOT}"/output/kernel-debs/linux-headers-*.deb "${rootfs_dir}/tmp/kernel-debs/" 2>/dev/null || true

    # Install via chroot
    sudo cp /usr/bin/qemu-aarch64-static "${rootfs_dir}/usr/bin/" 2>/dev/null || true

    sudo chroot "${rootfs_dir}" /bin/bash << 'CHROOT_EOF'
set -e
cd /tmp/kernel-debs
echo "Installing kernel packages..."
dpkg -i linux-image-*.deb
dpkg -i linux-headers-*.deb 2>/dev/null || true
rm -rf /tmp/kernel-debs
echo "Kernel installed successfully"
CHROOT_EOF

    log "✓ Kernel installed to rootfs"
}

show_summary() {
    log ""
    log "=========================================="
    log "Kernel Build Summary"
    log "=========================================="
    log "Board:          ${BOARD}"
    log "DTB:            ${DTB_NAME}.dtb"
    log "Kernel dir:     ${KERNEL_DIR}"
    log "Packages:       output/kernel-debs/"
    log ""

    if [ -d "${PROJECT_ROOT}/output/kernel-debs" ]; then
        log "Built packages:"
        ls -1 "${PROJECT_ROOT}/output/kernel-debs/"
    fi

    log ""
    log "Next steps:"
    log "1. Build rootfs:     ./scripts/build-debian-rootfs.sh"
    log "2. Or install now:   Re-run this script to install to existing rootfs"
    log "3. Assemble image:   ./scripts/assemble-image.sh ${BOARD}"
    log "=========================================="
}

main() {
    log "Building Rockchip kernel ${KERNEL_VERSION} for ${BOARD}"
    log ""

    check_deps
    clone_kernel
    copy_custom_files
    configure_kernel
    build_kernel
    build_deb_packages

    # Optional: install to rootfs if it exists
    if [ -d "${PROJECT_ROOT}/rootfs/work" ]; then
        read -p "Install kernel to existing rootfs? (Y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            install_to_rootfs
        fi
    fi

    show_summary
}

main "$@"
