#!/bin/bash
set -e

# RK356X U-Boot Build Script
# Builds U-Boot for specified board

BOARD="${1:-rock-3a}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${ROOT_DIR}/build"
OUTPUT_DIR="${ROOT_DIR}/output/u-boot"
CONFIG_DIR="${ROOT_DIR}/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Load board configuration
if [ -f "${CONFIG_DIR}/boards/${BOARD}.conf" ]; then
    log_info "Loading configuration for ${BOARD}"
    source "${CONFIG_DIR}/boards/${BOARD}.conf"
else
    log_error "No configuration found for board: ${BOARD}"
    exit 1
fi

# Set defaults if not in config
UBOOT_REPO="${UBOOT_REPO:-https://github.com/u-boot/u-boot.git}"
UBOOT_BRANCH="${UBOOT_BRANCH:-v2024.01}"
UBOOT_DEFCONFIG="${UBOOT_DEFCONFIG:-${BOARD}-rk3568_defconfig}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
RKBIN_REPO="${RKBIN_REPO:-https://github.com/rockchip-linux/rkbin.git}"

mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

# Clone or update U-Boot
if [ ! -d "${BUILD_DIR}/u-boot" ]; then
    log_info "Cloning U-Boot from ${UBOOT_REPO}"
    git clone --depth 1 -b "${UBOOT_BRANCH}" "${UBOOT_REPO}" "${BUILD_DIR}/u-boot"
else
    log_info "U-Boot already cloned, updating..."
    cd "${BUILD_DIR}/u-boot"
    git fetch origin "${UBOOT_BRANCH}"
    git checkout "${UBOOT_BRANCH}"
    git pull
fi

# Clone or update rkbin (Rockchip binary tools)
if [ ! -d "${BUILD_DIR}/rkbin" ]; then
    log_info "Cloning rkbin from ${RKBIN_REPO}"
    git clone "${RKBIN_REPO}" "${BUILD_DIR}/rkbin"
else
    log_info "rkbin already cloned, updating..."
    cd "${BUILD_DIR}/rkbin"
    git pull
fi

cd "${BUILD_DIR}/u-boot"

# Apply patches if they exist
if [ -d "${CONFIG_DIR}/patches/u-boot/${BOARD}" ]; then
    log_info "Applying board-specific patches"
    for patch in "${CONFIG_DIR}/patches/u-boot/${BOARD}"/*.patch; do
        if [ -f "$patch" ]; then
            log_info "Applying $(basename $patch)"
            git apply "$patch" || log_warn "Failed to apply $patch"
        fi
    done
fi

# Clean previous build
log_info "Cleaning previous build"
make CROSS_COMPILE="${CROSS_COMPILE}" distclean

# Configure U-Boot
log_info "Configuring U-Boot with ${UBOOT_DEFCONFIG}"
make CROSS_COMPILE="${CROSS_COMPILE}" "${UBOOT_DEFCONFIG}"

# Apply custom config if exists
if [ -f "${CONFIG_DIR}/u-boot/${BOARD}.config" ]; then
    log_info "Applying custom configuration"
    ./scripts/kconfig/merge_config.sh .config "${CONFIG_DIR}/u-boot/${BOARD}.config"
fi

# Build U-Boot
log_info "Building U-Boot (this may take a while...)"
make CROSS_COMPILE="${CROSS_COMPILE}" -j$(nproc)

# Build Rockchip boot images
log_info "Building Rockchip boot images"

# Set TPL/SPL paths based on U-Boot version
if [ -f "tpl/u-boot-tpl.bin" ]; then
    TPL_BIN="tpl/u-boot-tpl.bin"
else
    TPL_BIN="${BUILD_DIR}/rkbin/bin/rk35/rk3568_ddr_1560MHz_v1.18.bin"
fi

# Create idbloader.img (TPL + SPL)
./tools/mkimage -n rk3568 -T rksd -d "${TPL_BIN}:spl/u-boot-spl.bin" idbloader.img

# Check if ATF is needed (for newer U-Boot)
if [ ! -f "u-boot.itb" ]; then
    log_info "Building FIT image with ATF"
    # Use prebuilt ATF from rkbin
    BL31="${BUILD_DIR}/rkbin/bin/rk35/rk3568_bl31_v1.44.elf"

    if [ ! -f "$BL31" ]; then
        log_error "BL31 not found at $BL31"
        exit 1
    fi

    export BL31
    make CROSS_COMPILE="${CROSS_COMPILE}" u-boot.itb
fi

# Copy outputs
log_info "Copying output files"
cp -v idbloader.img "${OUTPUT_DIR}/"
cp -v u-boot.itb "${OUTPUT_DIR}/" || cp -v u-boot.bin "${OUTPUT_DIR}/"

# Create flash script
cat > "${OUTPUT_DIR}/flash-uboot.sh" << 'EOF'
#!/bin/bash
# Flash U-Boot to SD card or eMMC
# Usage: ./flash-uboot.sh /dev/sdX

if [ $# -ne 1 ]; then
    echo "Usage: $0 <device>"
    echo "Example: $0 /dev/sdb"
    exit 1
fi

DEVICE=$1

if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a block device"
    exit 1
fi

echo "WARNING: This will write U-Boot to $DEVICE"
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Flash idbloader at sector 64 (32KB offset)
sudo dd if=idbloader.img of=$DEVICE seek=64 conv=notrunc,fsync
# Flash u-boot.itb at sector 16384 (8MB offset)
sudo dd if=u-boot.itb of=$DEVICE seek=16384 conv=notrunc,fsync

sync
echo "U-Boot flashed successfully!"
EOF

chmod +x "${OUTPUT_DIR}/flash-uboot.sh"

# Create README
cat > "${OUTPUT_DIR}/README.md" << EOF
# U-Boot for ${BOARD}

Built: $(date)
Branch: ${UBOOT_BRANCH}

## Files

- \`idbloader.img\` - Initial boot loader (TPL + SPL)
- \`u-boot.itb\` - U-Boot proper with ATF
- \`flash-uboot.sh\` - Helper script to flash U-Boot

## Manual Flashing

\`\`\`bash
# Flash to SD card (replace /dev/sdX with your device)
sudo dd if=idbloader.img of=/dev/sdX seek=64 conv=notrunc,fsync
sudo dd if=u-boot.itb of=/dev/sdX seek=16384 conv=notrunc,fsync
sync
\`\`\`

## Partition Layout

\`\`\`
Offset  | Size | Content
--------|------|------------------
0KB     | 32KB | Reserved
32KB    | ~8MB | idbloader.img (TPL + SPL)
8MB     | ~8MB | u-boot.itb (U-Boot + ATF)
16MB+   | ...  | Boot partition
\`\`\`
EOF

log_info "U-Boot build complete!"
log_info "Output files in: ${OUTPUT_DIR}"
ls -lh "${OUTPUT_DIR}"
