#!/bin/bash
set -e

# Backup U-Boot from RK3568 board via SSH
# Dumps bootloader partitions from eMMC for recovery

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

# Board connection
BOARD_IP="${1:-192.168.1.21}"
BOARD_USER="root"
BOARD_PASS="root"

OUTPUT_DIR="${PROJECT_ROOT}/output/uboot-backup"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${OUTPUT_DIR}/${TIMESTAMP}"

mkdir -p "${BACKUP_DIR}"

log "Backing up U-Boot from ${BOARD_IP}..."
echo

# U-Boot partition offsets (in 512-byte sectors)
# idbloader: sector 64 (32KB), size ~512KB
# uboot:     sector 16384 (8MB), size ~2MB
# trust:     sector 24576 (12MB), size ~2MB

log "Creating backup directory: ${BACKUP_DIR}"

# Backup idbloader (SPL + DDR init)
log "Backing up idbloader..."
sshpass -p "${BOARD_PASS}" ssh -o StrictHostKeyChecking=no "${BOARD_USER}@${BOARD_IP}" \
    "dd if=/dev/mmcblk0 skip=64 count=1024 bs=512 status=none" \
    > "${BACKUP_DIR}/idbloader.img.backup"

# Backup u-boot
log "Backing up u-boot..."
sshpass -p "${BOARD_PASS}" ssh -o StrictHostKeyChecking=no "${BOARD_USER}@${BOARD_IP}" \
    "dd if=/dev/mmcblk0 skip=16384 count=4096 bs=512 status=none" \
    > "${BACKUP_DIR}/uboot.img.backup"

# Backup trust (ATF)
log "Backing up trust..."
sshpass -p "${BOARD_PASS}" ssh -o StrictHostKeyChecking=no "${BOARD_USER}@${BOARD_IP}" \
    "dd if=/dev/mmcblk0 skip=24576 count=4096 bs=512 status=none" \
    > "${BACKUP_DIR}/trust.img.backup"

# Create restore script
cat > "${BACKUP_DIR}/restore-uboot.sh" << 'RESTORE_EOF'
#!/bin/bash
# Restore original U-Boot to device
# Usage: sudo ./restore-uboot.sh /dev/sdX

set -e

if [ $# -ne 1 ]; then
    echo "Usage: sudo $0 /dev/sdX"
    echo "Example: sudo $0 /dev/mmcblk0  (for eMMC)"
    echo "Example: sudo $0 /dev/sdb       (for SD card)"
    exit 1
fi

DEVICE=$1

if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a block device"
    exit 1
fi

echo "WARNING: This will restore the original U-Boot to $DEVICE"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

echo "Restoring idbloader..."
dd if=idbloader.img.backup of=$DEVICE seek=64 bs=512 conv=fsync

echo "Restoring u-boot..."
dd if=uboot.img.backup of=$DEVICE seek=16384 bs=512 conv=fsync

echo "Restoring trust..."
dd if=trust.img.backup of=$DEVICE seek=24576 bs=512 conv=fsync

sync

echo "✓ Original U-Boot restored!"
RESTORE_EOF

chmod +x "${BACKUP_DIR}/restore-uboot.sh"

# Create info file
cat > "${BACKUP_DIR}/README.txt" << INFO_EOF
U-Boot Backup - $(date)

Board: RK3568 SZ3568
Source: ${BOARD_IP} (eMMC /dev/mmcblk0)

Files:
- idbloader.img.backup  SPL + DDR init (from sector 64)
- uboot.img.backup      U-Boot proper (from sector 16384)
- trust.img.backup      ARM Trusted Firmware (from sector 24576)
- restore-uboot.sh      Script to restore this backup

To restore:
  sudo ./restore-uboot.sh /dev/sdX

To flash via maskrom mode:
  Use rkdeveloptool or upgrade_tool with these images
INFO_EOF

log "✓ Backup complete!"
echo
log "Backup saved to: ${BACKUP_DIR}"
log "Files:"
ls -lh "${BACKUP_DIR}"
echo
log "To restore this backup:"
log "  cd ${BACKUP_DIR}"
log "  sudo ./restore-uboot.sh /dev/sdX"
