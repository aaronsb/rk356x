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
        DEFCONFIG="rk3568_defconfig"
        BOARD_DESC="SZ3568-V1.2 (RGMII + MAXIO PHY)"
        ;;
    rk3568_custom)
        DEFCONFIG="rk3568_defconfig"
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
UBOOT_DIR="${PROJECT_ROOT}/u-boot"
RKBIN_DIR="${PROJECT_ROOT}/rkbin"
OUTPUT_DIR="${PROJECT_ROOT}/output"
UBOOT_REPO="https://github.com/rockchip-linux/u-boot.git"
UBOOT_BRANCH="next-dev"  # Rockchip's development branch with RK3568 support

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
    step "Building U-Boot for RK3568..."

    cd "${UBOOT_DIR}"

    # Clean previous build
    make distclean || true

    # Configure for RK3568
    make ${DEFCONFIG}

    # Apply defconfig patch to disable SPL hardware crypto
    # (Required because EVB device tree lacks clock configuration for crypto engine)
    if [ -f "${PROJECT_ROOT}/config/uboot-rk3568-disable-spl-hw-crypto.patch" ]; then
        log "Applying SPL hardware crypto disable patch..."
        patch -p1 < "${PROJECT_ROOT}/config/uboot-rk3568-disable-spl-hw-crypto.patch" || warn "Patch may already be applied"
        make oldconfig </dev/null
    fi

    # Get ATF/TEE blob paths for FIT image creation
    # Try newer ultra version which may have critical fixes
    local bl31_blob="${RKBIN_DIR}/bin/rk35/rk3568_bl31_ultra_v2.17.elf"
    local bl32_blob="${RKBIN_DIR}/bin/rk35/rk3568_bl32_v2.15.bin"

    if [ ! -f "${bl31_blob}" ]; then
        error "BL31 blob not found: ${bl31_blob}"
    fi

    # Copy BL31 as bl31.elf for FIT generator (REQUIRED!)
    cp "${bl31_blob}" "${UBOOT_DIR}/bl31.elf"
    log "✓ BL31/ATF blob prepared"

    # Copy BL32 as tee.bin for FIT generator (optional, but recommended)
    if [ -f "${bl32_blob}" ]; then
        cp "${bl32_blob}" "${UBOOT_DIR}/tee.bin"
        log "✓ BL32/TEE blob prepared"
    else
        warn "BL32 not found, building without OP-TEE"
    fi

    # Build with relaxed warnings for GCC compatibility
    # Newer GCC (Ubuntu 24.04) is strict about enum/int mismatches and uninitialized vars
    # in older Rockchip U-Boot code
    # BL31 path tells make to create u-boot.itb (FIT image with ATF bundled)
    log "Compiling U-Boot (this may take a few minutes)..."
    make -j$(nproc) \
        CROSS_COMPILE=aarch64-linux-gnu- \
        BL31="${bl31_blob}" \
        KCFLAGS="-Wno-error=enum-int-mismatch -Wno-error=enum-conversion -Wno-error=maybe-uninitialized"

    if [ ! -f "u-boot.bin" ]; then
        error "U-Boot build failed - u-boot.bin not found"
    fi

    log "✓ U-Boot compiled successfully"

    # Explicitly build u-boot.itb (FIT image with ATF/TEE)
    log "Building u-boot.itb (FIT image)..."
    make -j$(nproc) \
        CROSS_COMPILE=aarch64-linux-gnu- \
        BL31="${bl31_blob}" \
        KCFLAGS="-Wno-error=enum-int-mismatch -Wno-error=enum-conversion -Wno-error=maybe-uninitialized" \
        u-boot.itb

    if [ ! -f "u-boot.itb" ]; then
        error "u-boot.itb creation failed - check build log for FIT generation errors"
    fi

    log "✓ u-boot.itb created successfully ($(du -h u-boot.itb | cut -f1))"
}

package_uboot() {
    step "Packaging U-Boot with Rockchip blobs..."

    cd "${UBOOT_DIR}"

    # Rockchip binary blob files (use latest versions available in rkbin)
    local ddr_blob="${RKBIN_DIR}/bin/rk35/rk3568_ddr_1560MHz_v1.23.bin"
    local bl31_blob="${RKBIN_DIR}/bin/rk35/rk3568_bl31_ultra_v2.17.elf"
    local bl32_blob="${RKBIN_DIR}/bin/rk35/rk3568_bl32_v2.15.bin"

    # Verify blobs exist
    if [ ! -f "${ddr_blob}" ]; then
        error "DDR blob not found: ${ddr_blob}"
    fi
    if [ ! -f "${bl31_blob}" ]; then
        error "BL31 blob not found: ${bl31_blob}"
    fi

    log "Using blobs:"
    log "  DDR:  $(basename ${ddr_blob})"
    log "  BL31: $(basename ${bl31_blob})"
    log "  BL32: $(basename ${bl32_blob})"

    # Create idbloader (DDR init + SPL)
    log "Creating idbloader..."
    "${RKBIN_DIR}/tools/mkimage" -n rk3568 -T rksd -d \
        "${ddr_blob}:spl/u-boot-spl.bin" \
        idbloader.img

    # Check if u-boot.itb was created (FIT image with U-Boot + DTB + ATF)
    if [ -f "u-boot.itb" ]; then
        log "Using u-boot.itb (FIT image with ATF bundled)..."
        /bin/cp -f u-boot.itb uboot.img
        log "✓ u-boot.itb found ($(du -h u-boot.itb | cut -f1))"

        # Create trust.img for compatibility with other boot methods
        log "Creating trust.img (for compatibility)..."
        cat > trust.ini << EOF
[VERSION]
MAJOR=1
MINOR=0

[BL30_OPTION]
SEC=0

[BL31_OPTION]
SEC=1
PATH=${bl31_blob}
ADDR=0x00040000

[BL32_OPTION]
SEC=1
PATH=${bl32_blob}
ADDR=0x08400000

[BL33_OPTION]
SEC=0

[OUTPUT]
PATH=trust.img
EOF
        "${RKBIN_DIR}/tools/trust_merger" trust.ini
    else
        error "u-boot.itb not found! Make sure BL31 was specified during build."
    fi

    log "✓ U-Boot packaged"
}

install_output() {
    log "Installing U-Boot to output directory..."

    mkdir -p "${OUTPUT_DIR}/uboot"

    cp "${UBOOT_DIR}/idbloader.img" "${OUTPUT_DIR}/uboot/"
    cp "${UBOOT_DIR}/uboot.img" "${OUTPUT_DIR}/uboot/"
    cp "${UBOOT_DIR}/trust.img" "${OUTPUT_DIR}/uboot/"

    # Create flash script
    cat > "${OUTPUT_DIR}/uboot/flash-uboot.sh" << 'EOF'
#!/bin/bash
# Flash U-Boot to SD card or eMMC
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

echo "WARNING: This will flash U-Boot to $DEVICE"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

set -e

echo "Flashing idbloader to sector 64..."
dd if=idbloader.img of=$DEVICE seek=64 conv=fsync

echo "Flashing u-boot.img to sector 16384..."
dd if=uboot.img of=$DEVICE seek=16384 conv=fsync

echo "Flashing trust.img to sector 24576..."
dd if=trust.img of=$DEVICE seek=24576 conv=fsync

sync

echo "✓ U-Boot flashed successfully!"
echo "Remove SD card and reboot the board"
EOF

    chmod +x "${OUTPUT_DIR}/uboot/flash-uboot.sh"

    log "✓ U-Boot installed to ${OUTPUT_DIR}/uboot/"
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
