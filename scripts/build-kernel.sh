#!/bin/bash
set -e

# RK356X Kernel Build Script
# Builds Linux kernel for specified board

BOARD="${1:-rock-3a}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${ROOT_DIR}/build"
OUTPUT_DIR="${ROOT_DIR}/output/kernel"
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
KERNEL_REPO="${KERNEL_REPO:-https://github.com/torvalds/linux.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-v6.6}"
KERNEL_DEFCONFIG="${KERNEL_DEFCONFIG:-defconfig}"
KERNEL_CONFIG="${KERNEL_CONFIG:-rockchip_linux_defconfig}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
ARCH="${ARCH:-arm64}"
DTB_FILE="${DTB_FILE:-rk3568-rock-3a.dtb}"

mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

# Clone or update kernel
if [ ! -d "${BUILD_DIR}/linux" ]; then
    log_info "Cloning kernel from ${KERNEL_REPO}"
    git clone --depth 1 -b "${KERNEL_BRANCH}" "${KERNEL_REPO}" "${BUILD_DIR}/linux"
else
    log_info "Kernel already cloned, updating..."
    cd "${BUILD_DIR}/linux"
    git fetch origin "${KERNEL_BRANCH}"
    git checkout "${KERNEL_BRANCH}"
    git pull
fi

cd "${BUILD_DIR}/linux"

# Apply patches if they exist
if [ -d "${CONFIG_DIR}/patches/kernel/${BOARD}" ]; then
    log_info "Applying board-specific patches"
    for patch in "${CONFIG_DIR}/patches/kernel/${BOARD}"/*.patch; do
        if [ -f "$patch" ]; then
            log_info "Applying $(basename $patch)"
            git apply "$patch" || log_warn "Failed to apply $patch"
        fi
    done
fi

# Clean previous build
log_info "Cleaning previous build"
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" mrproper

# Configure kernel
log_info "Configuring kernel with ${KERNEL_CONFIG}"
if [ -f "arch/${ARCH}/configs/${KERNEL_CONFIG}" ]; then
    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" "${KERNEL_CONFIG}"
else
    log_warn "${KERNEL_CONFIG} not found, using defconfig"
    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" defconfig
fi

# Apply custom config fragments
if [ -f "${CONFIG_DIR}/kernel/${BOARD}.config" ]; then
    log_info "Applying custom configuration fragment"
    ./scripts/kconfig/merge_config.sh .config "${CONFIG_DIR}/kernel/${BOARD}.config"
fi

# Enable common options for RK356X
log_info "Enabling RK356X specific options"
./scripts/config --enable CONFIG_ARCH_ROCKCHIP
./scripts/config --enable CONFIG_ARM64
./scripts/config --enable CONFIG_ROCKCHIP_RK3568
./scripts/config --enable CONFIG_ROCKCHIP_IOMMU
./scripts/config --enable CONFIG_PHY_ROCKCHIP_NANENG_COMBO_PHY
./scripts/config --enable CONFIG_PHY_ROCKCHIP_SNPS_PCIE3
./scripts/config --enable CONFIG_DRM_ROCKCHIP
./scripts/config --enable CONFIG_ROCKCHIP_VOP2
./scripts/config --enable CONFIG_DRM_PANEL_SIMPLE
./scripts/config --enable CONFIG_ROCKCHIP_SARADC
./scripts/config --enable CONFIG_ROCKCHIP_THERMAL
./scripts/config --enable CONFIG_COMMON_CLK_ROCKCHIP
./scripts/config --enable CONFIG_PINCTRL_ROCKCHIP
./scripts/config --enable CONFIG_PWM_ROCKCHIP
./scripts/config --enable CONFIG_SND_SOC_ROCKCHIP
./scripts/config --enable CONFIG_CRYPTO_DEV_ROCKCHIP
./scripts/config --enable CONFIG_VIDEO_ROCKCHIP_RGA

# Enable Panfrost (Mali GPU)
./scripts/config --enable CONFIG_DRM_PANFROST

# Enable common storage and networking
./scripts/config --enable CONFIG_MMC
./scripts/config --enable CONFIG_MMC_SDHCI
./scripts/config --enable CONFIG_MMC_SDHCI_OF_DWCMSHC
./scripts/config --enable CONFIG_STMMAC_ETH
./scripts/config --enable CONFIG_DWMAC_ROCKCHIP

# Enable USB
./scripts/config --enable CONFIG_USB_DWC3
./scripts/config --enable CONFIG_USB_DWC3_DUAL_ROLE

# Update config with new settings
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig

# Save final config
cp .config "${OUTPUT_DIR}/${BOARD}.config"

# Build kernel
log_info "Building kernel (this may take a while...)"
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" -j$(nproc) Image modules dtbs

# Install modules to temporary directory
MODULES_DIR="${BUILD_DIR}/modules"
rm -rf "${MODULES_DIR}"
mkdir -p "${MODULES_DIR}"

log_info "Installing kernel modules"
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" INSTALL_MOD_PATH="${MODULES_DIR}" modules_install

# Copy outputs
log_info "Copying output files"
cp -v arch/${ARCH}/boot/Image "${OUTPUT_DIR}/"

# Copy device tree blobs
log_info "Copying device tree files"
mkdir -p "${OUTPUT_DIR}/dtbs/rockchip"

if [ -n "${DTB_FILE}" ]; then
    cp -v arch/${ARCH}/boot/dts/rockchip/${DTB_FILE} "${OUTPUT_DIR}/dtbs/rockchip/"
else
    # Copy all RK356X DTBs
    cp -v arch/${ARCH}/boot/dts/rockchip/rk356*.dtb "${OUTPUT_DIR}/dtbs/rockchip/" || true
fi

# Create compressed tarball of modules
log_info "Creating modules tarball"
tar -czf "${OUTPUT_DIR}/modules.tar.gz" -C "${MODULES_DIR}" .

# Get kernel version
KERNEL_VERSION=$(make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" kernelrelease)
log_info "Kernel version: ${KERNEL_VERSION}"

# Create boot files
log_info "Creating boot.scr for U-Boot"
cat > "${BUILD_DIR}/boot.cmd" << 'EOF'
# U-Boot boot script for RK356X

setenv bootargs "root=/dev/mmcblk0p2 rootwait rw console=ttyS2,1500000 earlycon=uart8250,mmio32,0xfe660000"

load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /boot/Image
load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} /boot/dtbs/${fdtfile}

booti ${kernel_addr_r} - ${fdt_addr_r}
EOF

# Compile boot script if mkimage is available
if command -v mkimage &> /dev/null; then
    mkimage -C none -A arm64 -T script -d "${BUILD_DIR}/boot.cmd" "${OUTPUT_DIR}/boot.scr"
    log_info "Created boot.scr"
fi

# Create README
cat > "${OUTPUT_DIR}/README.md" << EOF
# Kernel for ${BOARD}

Built: $(date)
Version: ${KERNEL_VERSION}
Branch: ${KERNEL_BRANCH}

## Files

- \`Image\` - Kernel image
- \`dtbs/rockchip/${DTB_FILE}\` - Device tree blob
- \`modules.tar.gz\` - Kernel modules tarball
- \`boot.scr\` - U-Boot boot script (optional)
- \`${BOARD}.config\` - Kernel configuration used

## Installation

### To boot partition:
\`\`\`bash
# Mount boot partition
sudo mount /dev/mmcblk0p1 /mnt/boot

# Copy kernel and dtb
sudo cp Image /mnt/boot/
sudo cp dtbs/rockchip/${DTB_FILE} /mnt/boot/dtbs/
sudo cp boot.scr /mnt/boot/  # if using U-Boot script

# Unmount
sudo umount /mnt/boot
\`\`\`

### To rootfs:
\`\`\`bash
# Mount rootfs
sudo mount /dev/mmcblk0p2 /mnt/rootfs

# Extract modules
sudo tar -xzf modules.tar.gz -C /mnt/rootfs/

# Unmount
sudo umount /mnt/rootfs
\`\`\`

## Device Tree

DTB used: ${DTB_FILE}

If you need a different DTB, check \`dtbs/rockchip/\` for other options.
EOF

log_info "Kernel build complete!"
log_info "Kernel version: ${KERNEL_VERSION}"
log_info "Output files in: ${OUTPUT_DIR}"
ls -lh "${OUTPUT_DIR}"
