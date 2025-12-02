#!/bin/bash
set -e

# U-Boot Build Script for RK3568
# Builds custom U-Boot with modified bootcmd to prefer SD card boot
# Uses Docker for reproducible builds

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }
step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Parse arguments
BOARD=""
CUSTOM_BOOTCMD=""
SKIP_DOCKER=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --bootcmd)
            CUSTOM_BOOTCMD="$2"
            shift 2
            ;;
        --skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            BOARD="$1"
            shift
            ;;
    esac
done

# Default board
BOARD="${BOARD:-rk3568_sz3568}"

# Board-specific configuration
case "${BOARD}" in
    rk3568_sz3568)
        DEFCONFIG="evb-rk3568_defconfig"
        BOARD_DESC="SZ3568-V1.2 (RGMII + MAXIO PHY)"
        ;;
    rk3568_custom)
        DEFCONFIG="evb-rk3568_defconfig"
        BOARD_DESC="DC-A568-V06 (RMII)"
        ;;
    *)
        error "Unknown board: ${BOARD}"
        ;;
esac

# Default bootcmd: skip boot_android, go straight to distro_bootcmd
DEFAULT_BOOTCMD="run distro_bootcmd"
BOOTCMD="${CUSTOM_BOOTCMD:-$DEFAULT_BOOTCMD}"

# Paths
UBOOT_DIR="${PROJECT_ROOT}/u-boot-mainline"
RKBIN_DIR="${PROJECT_ROOT}/rkbin"
OUTPUT_DIR="${PROJECT_ROOT}/output"
UBOOT_REPO="https://source.denx.de/u-boot/u-boot.git"
UBOOT_BRANCH="master"  # Mainline U-Boot with better SD card support

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [BOARD]

Build custom U-Boot for RK3568 boards with modified boot sequence.

Arguments:
  BOARD                  Board name (default: rk3568_sz3568)
                         Options: rk3568_sz3568, rk3568_custom

Options:
  --bootcmd CMD          Custom bootcmd (default: "run distro_bootcmd")
  --skip-docker          Build on host instead of Docker
  --help, -h             Show this help

Examples:
  # Build with default settings
  $0 rk3568_sz3568

  # Build with custom bootcmd
  $0 --bootcmd "run custom_boot" rk3568_sz3568

Output:
  output/uboot/idbloader.img  SPL + DDR init
  output/uboot/uboot.img      U-Boot proper
  output/uboot/trust.img      ARM Trusted Firmware
  output/uboot/flash-uboot.sh Flash script

Flashing:
  cd output/uboot
  sudo ./flash-uboot.sh /dev/sdX

EOF
    exit 0
}

# Check if rkbin exists
if [ ! -d "${RKBIN_DIR}" ]; then
    error "rkbin directory not found. Initialize submodule: git submodule update --init"
fi

# Docker build wrapper
build_in_docker() {
    step "Building U-Boot in Docker..."

    DOCKER_IMAGE="rk3568-debian-builder"

    # Build Docker image if it doesn't exist
    if ! docker image inspect "${DOCKER_IMAGE}:latest" &>/dev/null; then
        log "Building Docker image..."
        DOCKER_BUILDKIT=1 docker build -t "${DOCKER_IMAGE}:latest" -f "${PROJECT_ROOT}/Dockerfile" "${PROJECT_ROOT}"
    fi

    # Use SUDO_UID/SUDO_GID if running via sudo, otherwise use current user
    USER_ID="${SUDO_UID:-$(id -u)}"
    GROUP_ID="${SUDO_GID:-$(id -g)}"

    # Run build inside Docker
    docker run --rm \
        -v "${PROJECT_ROOT}:${PROJECT_ROOT}" \
        -w "${PROJECT_ROOT}" \
        -u "${USER_ID}:${GROUP_ID}" \
        -e "BOARD=${BOARD}" \
        -e "BOOTCMD=${BOOTCMD}" \
        -e "DEFCONFIG=${DEFCONFIG}" \
        "${DOCKER_IMAGE}:latest" \
        bash -c "
            set -e
            cd ${PROJECT_ROOT}
            ${SCRIPT_DIR}/build-uboot.sh --skip-docker ${BOARD}
        "
}

clone_uboot() {
    step "Cloning Rockchip U-Boot..."

    if [ -d "${UBOOT_DIR}" ]; then
        log "U-Boot directory exists, updating..."
        cd "${UBOOT_DIR}"
        git fetch origin "${UBOOT_BRANCH}" || true
        git checkout "${UBOOT_BRANCH}" || true
    else
        log "Cloning from ${UBOOT_REPO}..."
        git clone --depth 1 -b "${UBOOT_BRANCH}" "${UBOOT_REPO}" "${UBOOT_DIR}"
        cd "${UBOOT_DIR}"
    fi

    log "✓ U-Boot source ready: $(git describe --tags 2>/dev/null || git rev-parse --short HEAD)"
}

patch_bootcmd() {
    log "Patching default bootcmd..."

    # Find the include file that defines bootcmd for RK3568
    local config_file="${UBOOT_DIR}/include/configs/rk3568_common.h"

    if [ ! -f "${config_file}" ]; then
        # Try alternate location
        config_file="${UBOOT_DIR}/include/configs/rockchip-common.h"
    fi

    if [ ! -f "${config_file}" ]; then
        warn "Could not find config file to patch, will use environment override"
        return
    fi

    # Backup original
    cp "${config_file}" "${config_file}.orig"

    # Replace bootcmd to skip boot_android
    # Old: bootcmd=boot_android ${devtype} ${devnum};boot_fit;bootrkp;run distro_bootcmd;
    # New: bootcmd=run distro_bootcmd;

    sed -i 's/bootcmd=boot_android.*distro_bootcmd;/bootcmd=run distro_bootcmd;/' "${config_file}" || true

    log "Bootcmd patched (if found in ${config_file})"
}

build_uboot() {
    step "Building mainline U-Boot for RK3568..."

    cd "${UBOOT_DIR}"

    # Clean previous build (handle permission issues from Docker builds)
    if ! make distclean 2>/dev/null; then
        warn "Standard clean failed, using git clean to remove root-owned files..."
        git clean -fdx || warn "Git clean failed, some files may remain"
    fi

    # Configure for RK3568 EVB (mainline defconfig)
    make ${DEFCONFIG}

    # Set ATF and DDR init blobs as environment variables (mainline method)
    export BL31="${RKBIN_DIR}/bin/rk35/rk3568_bl31_ultra_v2.17.elf"
    export ROCKCHIP_TPL="${RKBIN_DIR}/bin/rk35/rk3568_ddr_1560MHz_v1.23.bin"

    if [ ! -f "${BL31}" ]; then
        error "BL31 blob not found: ${BL31}"
    fi

    if [ ! -f "${ROCKCHIP_TPL}" ]; then
        error "DDR init blob not found: ${ROCKCHIP_TPL}"
    fi

    log "Using blobs:"
    log "  BL31: $(basename ${BL31})"
    log "  DDR:  $(basename ${ROCKCHIP_TPL})"

    # Build U-Boot (mainline uses binman to create unified image)
    log "Compiling U-Boot (this may take a few minutes)..."
    make -j$(nproc) CROSS_COMPILE=aarch64-linux-gnu-

    if [ ! -f "u-boot-rockchip.bin" ]; then
        error "U-Boot build failed - u-boot-rockchip.bin not found"
    fi

    log "✓ U-Boot compiled successfully"
    log "✓ u-boot-rockchip.bin created ($(du -h u-boot-rockchip.bin | cut -f1))"
}

package_uboot() {
    step "Preparing mainline U-Boot image..."

    cd "${UBOOT_DIR}"

    # Mainline U-Boot creates a unified u-boot-rockchip.bin image via binman
    # No manual packaging needed - binman handles everything

    if [ ! -f "u-boot-rockchip.bin" ]; then
        error "u-boot-rockchip.bin not found!"
    fi

    log "✓ Mainline U-Boot image ready: u-boot-rockchip.bin"
}

install_output() {
    log "Installing U-Boot to output directory..."

    mkdir -p "${OUTPUT_DIR}/uboot"

    # Copy the unified mainline U-Boot image
    cp "${UBOOT_DIR}/u-boot-rockchip.bin" "${OUTPUT_DIR}/uboot/"

    # Create flash script for unified image
    cat > "${OUTPUT_DIR}/uboot/flash-uboot.sh" << 'EOF'
#!/bin/bash
# Flash mainline U-Boot to SD card or eMMC
# WARNING: This will overwrite the bootloader!

if [ $# -ne 1 ]; then
    echo "Usage: sudo $0 /dev/sdX"
    echo "Example: sudo $0 /dev/sdb"
    exit 1
fi

DEVICE=$1

if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a block device"
    exit 1
fi

echo "WARNING: This will flash mainline U-Boot to $DEVICE"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

set -e

echo "Flashing u-boot-rockchip.bin to sector 64..."
dd if=u-boot-rockchip.bin of=$DEVICE seek=64 conv=fsync

sync

echo "✓ Mainline U-Boot flashed successfully!"
echo "Remove SD card and reboot the board"
EOF

    chmod +x "${OUTPUT_DIR}/uboot/flash-uboot.sh"

    log "✓ U-Boot installed to ${OUTPUT_DIR}/uboot/"
    log "✓ Image: u-boot-rockchip.bin ($(du -h ${UBOOT_DIR}/u-boot-rockchip.bin | cut -f1))"
    echo
    log "Flash to SD card with:"
    log "  cd ${OUTPUT_DIR}/uboot"
    log "  sudo ./flash-uboot.sh /dev/sdX"
    echo
    warn "⚠️  CAUTION: Flashing U-Boot can brick your board if done incorrectly!"
    warn "⚠️  Only proceed if you have a spare board or recovery method!"
}

main() {
    echo
    log "========================================"
    log "U-Boot Build for RK3568"
    log "Board: ${BOARD_DESC}"
    log "Bootcmd: ${BOOTCMD}"
    log "========================================"
    echo

    # Use Docker unless --skip-docker is specified
    if [ "$SKIP_DOCKER" = false ] && command -v docker &>/dev/null; then
        build_in_docker
        return 0
    fi

    if [ "$SKIP_DOCKER" = false ]; then
        warn "Docker not found, running native build"
        warn "Install Docker for reproducible builds"
    fi

    # Native build
    clone_uboot
    patch_bootcmd
    build_uboot
    package_uboot
    install_output

    log "✓ U-Boot build complete!"
}

main "$@"
