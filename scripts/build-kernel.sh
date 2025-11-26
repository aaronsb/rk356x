#!/bin/bash
set -e

# Rockchip Kernel Build Script
# Builds kernel 6.6 with custom DTBs and creates .deb packages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
KERNEL_VERSION="6.6"
KERNEL_BRANCH="develop-6.6"
KERNEL_REPO="https://github.com/rockchip-linux/kernel.git"
KERNEL_DIR="${PROJECT_ROOT}/kernel-${KERNEL_VERSION}"

BOARD="${1:-rk3568_sz3568}"
DEFCONFIG="rockchip_linux_defconfig"
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

check_deps() {
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
        read -p "Update kernel source? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cd "${KERNEL_DIR}"
            git fetch origin "${KERNEL_BRANCH}"
            git reset --hard "origin/${KERNEL_BRANCH}"
            cd "${PROJECT_ROOT}"
        fi
    fi
}

copy_custom_files() {
    log "Copying custom DTBs and patches..."

    # Copy custom DTBs
    if [ -d "${PROJECT_ROOT}/external/custom/board/rk3568/dts/rockchip" ]; then
        log "Copying device trees..."
        cp -v "${PROJECT_ROOT}"/external/custom/board/rk3568/dts/rockchip/*.dts \
            "${KERNEL_DIR}/arch/arm64/boot/dts/rockchip/"
    else
        warn "No custom DTBs found in external/custom/board/rk3568/dts/rockchip"
    fi

    # Apply patches
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
}

configure_kernel() {
    log "Configuring kernel..."

    cd "${KERNEL_DIR}"

    # Clean previous config
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- mrproper || true

    # Start with rockchip defconfig
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- "${DEFCONFIG}"

    # Apply config fragment if exists
    if [ -f "${PROJECT_ROOT}/external/custom/board/rk3568/kernel.config" ]; then
        log "Merging kernel config fragment..."

        # Append fragment to .config
        cat "${PROJECT_ROOT}/external/custom/board/rk3568/kernel.config" >> .config

        # Resolve dependencies
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
    fi

    # Ensure Mali Bifrost is enabled (critical for GPU)
    ./scripts/config --enable CONFIG_MALI_BIFROST
    ./scripts/config --set-str CONFIG_MALI_PLATFORM_NAME "rk"
    ./scripts/config --enable CONFIG_MALI_BIFROST_DEVFREQ

    # Ensure Panfrost is disabled (conflicts with Mali)
    ./scripts/config --disable CONFIG_DRM_PANFROST

    # Update config with new settings
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

    log "Kernel configuration complete"
    cd "${PROJECT_ROOT}"
}

build_kernel() {
    log "Building kernel with ${CORES} cores..."

    cd "${KERNEL_DIR}"

    # Build kernel image, DTBs, and modules
    make -j"${CORES}" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
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

    # Set version for packages
    local version=$(make -s kernelrelease)
    local pkg_version="1.0.0-rockchip-${BOARD}"

    log "Kernel version: ${version}"
    log "Package version: ${pkg_version}"

    # Build deb packages (creates in parent directory)
    KDEB_PKGVERSION="${pkg_version}" \
    make -j"${CORES}" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
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
