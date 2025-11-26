#!/bin/bash
set -e

# Build SD Card Image for Board Provisioning
# Usage: ./scripts/build-sd-image.sh <board-name> <sd-device>
# Example: ./scripts/build-sd-image.sh dc-a568-v06 /dev/sdb

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <board-name> <sd-device>"
    echo "Example: $0 dc-a568-v06 /dev/sdb"
    echo ""
    echo "Available boards:"
    ls -1 "${PROJECT_ROOT}/boards/" 2>/dev/null || echo "  (none found)"
    exit 1
fi

BOARD_NAME="$1"
SD_DEVICE="$2"
BOARD_DIR="${PROJECT_ROOT}/boards/${BOARD_NAME}"
BOARD_CONF="${BOARD_DIR}/board.conf"

# Validate board exists
if [ ! -f "$BOARD_CONF" ]; then
    log_error "Board configuration not found: $BOARD_CONF"
    exit 1
fi

# Validate SD device
if [ ! -b "$SD_DEVICE" ]; then
    log_error "Not a block device: $SD_DEVICE"
    exit 1
fi

# Source board configuration
source "$BOARD_CONF"

# Paths to build outputs
IMAGES_DIR="${PROJECT_ROOT}/buildroot/output/images"
UBOOT_BUILD_DIR="${PROJECT_ROOT}/buildroot/output/build/uboot-2024.07"

echo "========================================"
echo "Build SD Card Image"
echo "========================================"
echo ""
echo "Board: ${BOARD_NAME}"
echo "Device: ${SD_DEVICE}"
echo "Description: ${BOARD_DESCRIPTION}"
echo ""

# Check for required files
log_info "Checking for required files..."
REQUIRED_FILES=(
    "${UBOOT_BUILD_DIR}/idbloader.img"
    "${UBOOT_BUILD_DIR}/u-boot.itb"
    "${IMAGES_DIR}/Image"
    "${IMAGES_DIR}/${BOARD_DTB}"
    "${IMAGES_DIR}/rootfs.tar.gz"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        log_error "Required file not found: $f"
        log_error "Run ./scripts/buildroot-build.sh first to build the images"
        exit 1
    fi
done
log_info "All required files present"

# Confirmation
echo ""
log_warn "WARNING: This will ERASE all data on ${SD_DEVICE}"
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_error "Cancelled"
    exit 1
fi

# Create partition table
log_info "Creating partition table..."
sudo parted "$SD_DEVICE" --script mklabel gpt
sudo parted "$SD_DEVICE" --script mkpart boot ext4 ${BOOT_START}MiB ${ROOTFS_START}MiB
sudo parted "$SD_DEVICE" --script mkpart rootfs ext4 ${ROOTFS_START}MiB 100%

# Wait for partitions to appear
sleep 2
sudo partprobe "$SD_DEVICE" 2>/dev/null || true
sleep 1

# Format partitions
log_info "Formatting partitions..."
sudo mkfs.ext4 -F -L BOOT "${SD_DEVICE}1"
sudo mkfs.ext4 -F -L rootfs "${SD_DEVICE}2"

# Mount partitions
log_info "Mounting partitions..."
MOUNT_BOOT=$(mktemp -d)
MOUNT_ROOTFS=$(mktemp -d)
sudo mount "${SD_DEVICE}1" "$MOUNT_BOOT"
sudo mount "${SD_DEVICE}2" "$MOUNT_ROOTFS"

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    sudo umount "$MOUNT_BOOT" 2>/dev/null || true
    sudo umount "$MOUNT_ROOTFS" 2>/dev/null || true
    rmdir "$MOUNT_BOOT" 2>/dev/null || true
    rmdir "$MOUNT_ROOTFS" 2>/dev/null || true
}
trap cleanup EXIT

# Copy kernel and DTB to boot partition
log_info "Copying kernel and DTB..."
sudo cp "${IMAGES_DIR}/Image" "$MOUNT_BOOT/"
sudo cp "${IMAGES_DIR}/${BOARD_DTB}" "$MOUNT_BOOT/"

# Create extlinux.conf for SD card boot
log_info "Creating boot configuration..."
sudo mkdir -p "${MOUNT_BOOT}/extlinux"
sudo tee "${MOUNT_BOOT}/extlinux/extlinux.conf" > /dev/null << EOF
default ${BOARD_NAME}
timeout 3

label ${BOARD_NAME}
    kernel /Image
    fdt /${BOARD_DTB}
    append console=${CONSOLE} root=${SD_DEV}p2 rootwait rw
EOF

# Extract rootfs
log_info "Extracting root filesystem (this may take a while)..."
sudo tar -xzf "${IMAGES_DIR}/rootfs.tar.gz" -C "$MOUNT_ROOTFS"

# Create setup-emmc script on the rootfs
log_info "Installing setup-emmc script..."
sudo mkdir -p "${MOUNT_ROOTFS}/usr/local/bin"
sudo tee "${MOUNT_ROOTFS}/usr/local/bin/setup-emmc" > /dev/null << 'SETUP_SCRIPT'
#!/bin/sh
set -e

# Setup eMMC - Provisions the internal storage
# Run this after booting from SD card

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================"
echo "eMMC Setup Script"
echo "========================================"
echo ""

# Detect devices
# SD card is what we booted from (root device)
ROOT_DEV=$(findmnt -n -o SOURCE /)
case "$ROOT_DEV" in
    *mmcblk0*)
        SD_DEV="/dev/mmcblk0"
        EMMC_DEV="/dev/mmcblk1"
        ;;
    *mmcblk1*)
        SD_DEV="/dev/mmcblk1"
        EMMC_DEV="/dev/mmcblk0"
        ;;
    *)
        log_error "Cannot determine SD/eMMC devices"
        exit 1
        ;;
esac

log_info "SD card: ${SD_DEV}"
log_info "eMMC: ${EMMC_DEV}"
echo ""

# Confirm
log_warn "This will ERASE all data on ${EMMC_DEV}"
printf "Continue? (y/N) "
read REPLY
case "$REPLY" in
    y|Y) ;;
    *)
        log_error "Cancelled"
        exit 1
        ;;
esac

# Mount boot partition
mkdir -p /boot
if ! mountpoint -q /boot; then
    mount "${SD_DEV}p1" /boot
fi
BOOT_MOUNT="/boot"

# Find DTB name from extlinux.conf
DTB_NAME=$(grep "fdt /" "${BOOT_MOUNT}/extlinux/extlinux.conf" | sed 's/.*fdt \///' | tr -d ' ')
CONSOLE=$(grep "console=" "${BOOT_MOUNT}/extlinux/extlinux.conf" | sed 's/.*console=\([^ ]*\).*/\1/')
LABEL=$(grep "^label" "${BOOT_MOUNT}/extlinux/extlinux.conf" | awk '{print $2}')

log_info "DTB: ${DTB_NAME}"
log_info "Console: ${CONSOLE}"
log_info "Label: ${LABEL}"
echo ""

# Partition eMMC
log_info "Partitioning eMMC..."
# Use fdisk since parted may not be available
{
    echo g      # Create GPT
    echo n      # New partition
    echo 1      # Partition 1
    echo 32768  # Start sector (16MiB)
    echo 557055 # End sector (~272MiB)
    echo n      # New partition
    echo 2      # Partition 2
    echo 557056 # Start sector
    echo        # Default end (rest of disk)
    echo w      # Write
} | fdisk "${EMMC_DEV}" > /dev/null 2>&1

sleep 1

# Format
log_info "Formatting partitions..."
mkfs.ext4 -F -L BOOT "${EMMC_DEV}p1" > /dev/null
mkfs.ext4 -F -L rootfs "${EMMC_DEV}p2" > /dev/null

# Mount
log_info "Mounting eMMC partitions..."
mkdir -p /mnt/emmc_boot /mnt/emmc_rootfs
mount "${EMMC_DEV}p1" /mnt/emmc_boot
mount "${EMMC_DEV}p2" /mnt/emmc_rootfs

# Copy boot files
log_info "Copying kernel and DTB..."
cp "${BOOT_MOUNT}/Image" /mnt/emmc_boot/
cp "${BOOT_MOUNT}/${DTB_NAME}" /mnt/emmc_boot/

# Create extlinux.conf for eMMC
log_info "Creating boot configuration..."
mkdir -p /mnt/emmc_boot/extlinux
cat > /mnt/emmc_boot/extlinux/extlinux.conf << EOF
default ${LABEL}
timeout 3

label ${LABEL}
    kernel /Image
    fdt /${DTB_NAME}
    append console=${CONSOLE} root=${EMMC_DEV}p2 rootwait rw
EOF

# Copy rootfs
log_info "Copying root filesystem (this may take a while)..."
cd /
tar --exclude='./dev' --exclude='./proc' --exclude='./sys' --exclude='./tmp' --exclude='./run' --exclude='./mnt' --exclude='./boot' -cf - . | tar -xf - -C /mnt/emmc_rootfs/

# Create essential directories
mkdir -p /mnt/emmc_rootfs/{dev,proc,sys,tmp,run,mnt,boot}

# Unmount
log_info "Unmounting..."
umount /mnt/emmc_boot
umount /mnt/emmc_rootfs
sync

echo ""
log_info "========================================"
log_info "eMMC setup complete!"
log_info "========================================"
echo ""
log_info "Remove SD card and reboot to boot from eMMC"
echo ""
SETUP_SCRIPT

sudo chmod +x "${MOUNT_ROOTFS}/usr/local/bin/setup-emmc"

# Write bootloader to SD card
log_info "Writing bootloader..."
sudo dd if="${UBOOT_BUILD_DIR}/idbloader.img" of="$SD_DEVICE" seek=64 conv=notrunc bs=512 status=none
sudo dd if="${UBOOT_BUILD_DIR}/u-boot.itb" of="$SD_DEVICE" seek=16384 conv=notrunc bs=512 status=none

# Sync
log_info "Syncing..."
sync

echo ""
log_info "========================================"
log_info "SD card image created successfully!"
log_info "========================================"
echo ""
log_info "Next steps:"
log_info "1. Insert SD card into ${BOARD_NAME} board"
log_info "2. Boot from SD card"
log_info "3. Login as root (password: root)"
log_info "4. Run: setup-emmc"
log_info "5. Remove SD card and reboot"
echo ""
log_info "If U-Boot doesn't auto-boot from SD, use these commands:"
echo "   ext4load mmc 1:1 0x40000000 Image"
echo "   ext4load mmc 1:1 0x48000000 ${BOARD_DTB}"
echo "   setenv bootargs console=${CONSOLE} root=${SD_DEV}p2 rootwait rw"
echo "   booti 0x40000000 - 0x48000000"
echo ""
log_info "SD card is safe to remove"
