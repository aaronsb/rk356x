#!/bin/bash
set -e

# RK356X Image Assembly Script
# Assembles bootloader, kernel, and rootfs into a complete flashable image

BOARD="${1:-rock-3a}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${ROOT_DIR}/build"
OUTPUT_DIR="${ROOT_DIR}/output"
CONFIG_DIR="${ROOT_DIR}/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Load board configuration
if [ -f "${CONFIG_DIR}/boards/${BOARD}.conf" ]; then
    log_info "Loading configuration for ${BOARD}"
    source "${CONFIG_DIR}/boards/${BOARD}.conf"
else
    log_warn "No configuration found for board: ${BOARD}, using defaults"
fi

# Set defaults
IMAGE_SIZE="${IMAGE_SIZE:-4096}"  # Total image size in MB
BOOT_SIZE="${BOOT_SIZE:-256}"     # Boot partition size in MB
DTB_FILE="${DTB_FILE:-rk3568-rock-3a.dtb}"
IMAGE_NAME="${IMAGE_NAME:-${BOARD}-debian-$(date +%Y%m%d)}"

UBOOT_DIR="${OUTPUT_DIR}/u-boot"
KERNEL_DIR="${OUTPUT_DIR}/kernel"
ROOTFS_DIR="${OUTPUT_DIR}/rootfs"
FINAL_DIR="${OUTPUT_DIR}"

# Check if all components exist
log_info "Checking for required components..."

if [ ! -f "${UBOOT_DIR}/idbloader.img" ] || [ ! -f "${UBOOT_DIR}/u-boot.itb" ]; then
    log_error "U-Boot files not found. Run build-uboot.sh first"
    exit 1
fi

if [ ! -f "${KERNEL_DIR}/Image" ]; then
    log_error "Kernel Image not found. Run build-kernel.sh first"
    exit 1
fi

if [ ! -f "${KERNEL_DIR}/dtbs/rockchip/${DTB_FILE}" ]; then
    log_error "Device tree ${DTB_FILE} not found. Run build-kernel.sh first"
    exit 1
fi

ROOTFS_TARBALL=$(ls -t "${ROOTFS_DIR}"/rootfs-${BOARD}-*.tar.gz 2>/dev/null | head -1)
if [ -z "${ROOTFS_TARBALL}" ]; then
    log_error "Rootfs tarball not found. Run build-rootfs.sh first"
    exit 1
fi

log_info "All components found!"

# Create image file
IMAGE_FILE="${FINAL_DIR}/${IMAGE_NAME}.img"
log_step "Creating image file: ${IMAGE_FILE}"
log_info "Image size: ${IMAGE_SIZE} MB"

dd if=/dev/zero of="${IMAGE_FILE}" bs=1M count="${IMAGE_SIZE}" status=progress

# Create partition table
log_step "Creating partition table"

# Calculate partition boundaries
BOOT_START=32768      # Start boot partition at 16MB (sector 32768)
BOOT_END=$((BOOT_START + BOOT_SIZE * 2048))  # BOOT_SIZE in MB -> sectors
ROOTFS_START=${BOOT_END}

log_info "Partition layout:"
log_info "  Reserved:    0 - 32KB"
log_info "  idbloader:   32KB - 8MB"
log_info "  u-boot:      8MB - 16MB"
log_info "  Boot:        16MB - $((16 + BOOT_SIZE))MB"
log_info "  Rootfs:      $((16 + BOOT_SIZE))MB - ${IMAGE_SIZE}MB"

# Create GPT partition table
parted -s "${IMAGE_FILE}" mklabel gpt
parted -s "${IMAGE_FILE}" mkpart primary ext4 ${BOOT_START}s ${BOOT_END}s
parted -s "${IMAGE_FILE}" mkpart primary ext4 ${ROOTFS_START}s 100%
parted -s "${IMAGE_FILE}" set 1 boot on

# Flash U-Boot to image
log_step "Writing U-Boot to image"
dd if="${UBOOT_DIR}/idbloader.img" of="${IMAGE_FILE}" seek=64 conv=notrunc,fsync status=progress
dd if="${UBOOT_DIR}/u-boot.itb" of="${IMAGE_FILE}" seek=16384 conv=notrunc,fsync status=progress

# Setup loop device
log_step "Setting up loop device"
LOOP_DEV=$(losetup -f)
losetup -P "${LOOP_DEV}" "${IMAGE_FILE}"

# Wait for partition devices
sleep 2

BOOT_DEV="${LOOP_DEV}p1"
ROOTFS_DEV="${LOOP_DEV}p2"

log_info "Loop device: ${LOOP_DEV}"
log_info "Boot partition: ${BOOT_DEV}"
log_info "Rootfs partition: ${ROOTFS_DEV}"

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    sync

    # Unmount if mounted
    umount "${BUILD_DIR}/mnt/boot" 2>/dev/null || true
    umount "${BUILD_DIR}/mnt/rootfs" 2>/dev/null || true

    # Detach loop device
    losetup -d "${LOOP_DEV}" 2>/dev/null || true

    # Remove mount points
    rm -rf "${BUILD_DIR}/mnt"
}
trap cleanup EXIT

# Format partitions
log_step "Formatting partitions"
log_info "Formatting boot partition..."
mkfs.ext4 -F -L "BOOT" "${BOOT_DEV}"

log_info "Formatting rootfs partition..."
mkfs.ext4 -F -L "ROOTFS" "${ROOTFS_DEV}"

# Mount partitions
log_step "Mounting partitions"
mkdir -p "${BUILD_DIR}/mnt/boot"
mkdir -p "${BUILD_DIR}/mnt/rootfs"

mount "${BOOT_DEV}" "${BUILD_DIR}/mnt/boot"
mount "${ROOTFS_DEV}" "${BUILD_DIR}/mnt/rootfs"

# Install boot files
log_step "Installing boot files"
log_info "Copying kernel..."
cp "${KERNEL_DIR}/Image" "${BUILD_DIR}/mnt/boot/"

log_info "Copying device tree..."
mkdir -p "${BUILD_DIR}/mnt/boot/dtbs/rockchip"
cp "${KERNEL_DIR}/dtbs/rockchip/${DTB_FILE}" "${BUILD_DIR}/mnt/boot/dtbs/rockchip/"

# Create boot script if it exists
if [ -f "${KERNEL_DIR}/boot.scr" ]; then
    log_info "Copying boot script..."
    cp "${KERNEL_DIR}/boot.scr" "${BUILD_DIR}/mnt/boot/"
fi

# Create extlinux config (alternative to boot.scr)
log_info "Creating extlinux configuration..."
mkdir -p "${BUILD_DIR}/mnt/boot/extlinux"
cat > "${BUILD_DIR}/mnt/boot/extlinux/extlinux.conf" << EOF
label Debian
    kernel /Image
    fdt /dtbs/rockchip/${DTB_FILE}
    append root=/dev/mmcblk0p2 rootwait rw console=ttyS2,1500000 earlycon=uart8250,mmio32,0xfe660000
EOF

# Extract rootfs
log_step "Extracting rootfs (this may take a while...)"
tar -xzf "${ROOTFS_TARBALL}" -C "${BUILD_DIR}/mnt/rootfs"

# Install kernel modules
log_step "Installing kernel modules"
if [ -f "${KERNEL_DIR}/modules.tar.gz" ]; then
    log_info "Extracting kernel modules..."
    tar -xzf "${KERNEL_DIR}/modules.tar.gz" -C "${BUILD_DIR}/mnt/rootfs"
else
    log_warn "No kernel modules found"
fi

# Create boot directory in rootfs
mkdir -p "${BUILD_DIR}/mnt/rootfs/boot"

# Update fstab with correct partition labels
log_info "Updating fstab..."
cat > "${BUILD_DIR}/mnt/rootfs/etc/fstab" << 'EOF'
# <file system> <mount point> <type> <options> <dump> <pass>
LABEL=ROOTFS    /               ext4    defaults,noatime    0   1
LABEL=BOOT      /boot           ext4    defaults,noatime    0   2
tmpfs           /tmp            tmpfs   defaults,nosuid     0   0
EOF

# Create release info
log_info "Creating release information..."
cat > "${BUILD_DIR}/mnt/rootfs/etc/rk356x-release" << EOF
BOARD=${BOARD}
BUILD_DATE=$(date)
KERNEL_VERSION=$(cat ${KERNEL_DIR}/../build/linux/include/config/kernel.release 2>/dev/null || echo "unknown")
IMAGE_VERSION=${IMAGE_NAME}
DTB=${DTB_FILE}
EOF

# Sync and unmount
log_step "Finalizing image"
sync
umount "${BUILD_DIR}/mnt/boot"
umount "${BUILD_DIR}/mnt/rootfs"

# Detach loop device
losetup -d "${LOOP_DEV}"
trap - EXIT

# Compress image
log_step "Compressing image"
log_info "Creating compressed image (this may take a while...)"
pixz -9 "${IMAGE_FILE}" "${IMAGE_FILE}.xz"

# Calculate checksums
log_info "Calculating checksums..."
cd "${FINAL_DIR}"
sha256sum "$(basename ${IMAGE_FILE})" > "${IMAGE_NAME}.img.sha256"
sha256sum "$(basename ${IMAGE_FILE}).xz" > "${IMAGE_NAME}.img.xz.sha256"

# Create flashing instructions
cat > "${FINAL_DIR}/${IMAGE_NAME}-FLASH.txt" << EOF
# Flashing Instructions for ${IMAGE_NAME}

## Requirements
- microSD card or eMMC (minimum ${IMAGE_SIZE}MB)
- Card reader
- Linux, macOS, or Windows PC

## Method 1: Using dd (Linux/macOS)

1. Decompress the image:
   xz -d ${IMAGE_NAME}.img.xz

2. Insert SD card and identify the device (e.g., /dev/sdX)
   lsblk  # or 'diskutil list' on macOS

3. Flash the image:
   sudo dd if=${IMAGE_NAME}.img of=/dev/sdX bs=4M status=progress conv=fsync

   ⚠️  WARNING: Double-check the device name! This will erase all data!

4. Eject the card:
   sudo eject /dev/sdX

## Method 2: Using balenaEtcher (All platforms)

1. Download balenaEtcher: https://www.balena.io/etcher/
2. Select the ${IMAGE_NAME}.img.xz file (no need to decompress)
3. Select your SD card
4. Click "Flash!"

## Method 3: Using Rockchip tools (USB OTG)

For flashing directly to eMMC via USB:
1. Install rkdeveloptool or RKDevTool
2. Put device in maskrom mode
3. Flash with upgrade_tool

## After Flashing

1. Insert SD card into ${BOARD}
2. Connect power
3. Default login:
   - User: debian
   - Password: debian
   - Root password: debian

4. ⚠️  Change default passwords immediately:
   passwd          # Change user password
   sudo passwd root # Change root password

## Serial Console

Connect to serial console (optional):
- Port: ttyS2
- Baud: 1500000
- 8N1

## Network

System uses NetworkManager:
- Wired (DHCP): Auto-configured
- Wireless: nmtui or nmcli

## Troubleshooting

- No boot: Check U-Boot on serial console
- No display: May need different DTB for your board
- No network: Check cable and DHCP server

For support, check: https://github.com/yourrepo

Build info: See /etc/rk356x-release on the device
EOF

# Create summary
log_info ""
log_info "═══════════════════════════════════════════════════════"
log_info "  Image assembly complete!"
log_info "═══════════════════════════════════════════════════════"
log_info ""
log_info "Image file:      ${IMAGE_FILE}"
log_info "Compressed:      ${IMAGE_FILE}.xz"
log_info "Image size:      $(du -h ${IMAGE_FILE} | cut -f1)"
log_info "Compressed size: $(du -h ${IMAGE_FILE}.xz | cut -f1)"
log_info ""
log_info "Files created:"
log_info "  - ${IMAGE_NAME}.img       (raw image)"
log_info "  - ${IMAGE_NAME}.img.xz    (compressed)"
log_info "  - ${IMAGE_NAME}-FLASH.txt (instructions)"
log_info "  - ${IMAGE_NAME}.img*.sha256 (checksums)"
log_info ""
log_info "To flash:"
log_info "  sudo dd if=${IMAGE_NAME}.img of=/dev/sdX bs=4M status=progress"
log_info ""
log_info "Or use balenaEtcher with the .xz file"
log_info "═══════════════════════════════════════════════════════"
