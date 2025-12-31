#!/bin/bash
set -e

# Debian Image Assembly Script for RK3568
# Assembles U-Boot, kernel, and Debian rootfs into a bootable image

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Parse arguments
BOARD=""
WITH_UBOOT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --with-uboot)
            WITH_UBOOT=true
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

BOARD="${BOARD:-rk3568_sz3568}"

# Board-specific configuration
case "${BOARD}" in
    rk3568_sz3568)
        DTB_NAME="rk3568-sz3568"
        BOARD_DESC="SZ3568-V1.2 (RGMII + MAXIO PHY)"
        ;;
    rk3568_custom)
        DTB_NAME="rk3568-dc-a568"
        BOARD_DESC="DC-A568-V06 (RMII)"
        ;;
    *)
        echo "Unknown board: ${BOARD}"
        echo "Supported: rk3568_sz3568, rk3568_custom"
        exit 1
        ;;
esac

# Image configuration
IMAGE_SIZE="6144"          # Total image size in MB (6GB to fit rootfs + desktop)
BOOT_SIZE="256"            # Boot partition size in MB
IMAGE_NAME="rk3568-debian-$(date +%Y%m%d%H%M)"

# Root device will be determined by PARTUUID during image assembly
# This ensures boot.scr always matches the actual partition UUID

# Kernel version (from environment or default to 6.1)
KERNEL_VERSION="${KERNEL_VERSION:-6.1}"

# Paths
KERNEL_DIR="${PROJECT_ROOT}/kernel-${KERNEL_VERSION}"
ROOTFS_DIR="${PROJECT_ROOT}/rootfs"
OUTPUT_DIR="${PROJECT_ROOT}/output"
WORK_DIR="${PROJECT_ROOT}/output/image-work"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}==>${NC} $*"; }
step() { echo -e "${BLUE}[STEP]${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

usage() {
    cat << EOF
Usage: sudo $0 [OPTIONS] [BOARD]

Assembles bootable Debian image for RK3568 boards.

Arguments:
  BOARD              Board name (default: rk3568_sz3568)
                     Options: rk3568_sz3568, rk3568_custom

Options:
  --with-uboot       Include U-Boot flashing (⚠️  DANGEROUS - can brick board!)
  --help, -h         Show this help message

Examples:
  # Build image using existing U-Boot on board (safe, recommended)
  sudo $0 rk3568_sz3568

  # Build image with U-Boot flashing (only with spare board!)
  sudo $0 --with-uboot rk3568_sz3568

What this script does:
  1. ✓ Creates a 6GB disk image file
  2. ✓ Creates GPT partitions (boot + rootfs)
  3. ⚠ Flashes U-Boot (only if --with-uboot specified)
  4. ✓ Installs kernel Image + DTB to boot partition
  5. ✓ Installs Debian rootfs to root partition
  6. ✓ Configures fstab and boot config
  7. ✓ Compresses image with xz
  8. ✓ Creates checksums and flash instructions

Requirements (run first):
  ./scripts/build-kernel.sh [BOARD]
  ./scripts/build-debian-rootfs.sh

Output:
  output/rk3568-debian-YYYYMMDDHHMM.img     (raw image)
  output/rk3568-debian-YYYYMMDDHHMM.img.xz  (compressed)

Flash to SD card:
  sudo dd if=output/rk3568-debian-*.img of=/dev/sdX bs=4M status=progress

EOF
    exit 0
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root (use sudo)"
    fi
}

check_deps() {
    local deps=(parted losetup mkfs.ext4 e2fsck resize2fs xz mkimage)
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing dependencies: ${missing[*]}\n\nInstall with:\n  Ubuntu/Debian: sudo apt install parted e2fsprogs xz-utils u-boot-tools\n  Arch Linux:    yay -S uboot-tools (from AUR)"
    fi
}

check_components() {
    log "Checking for required components..."

    # Check kernel
    if [ ! -f "${KERNEL_DIR}/arch/arm64/boot/Image" ]; then
        error "Kernel Image not found. Run: ./scripts/build-kernel.sh ${BOARD}"
    fi

    # Check DTB
    if [ ! -f "${KERNEL_DIR}/arch/arm64/boot/dts/rockchip/${DTB_NAME}.dtb" ]; then
        error "DTB ${DTB_NAME}.dtb not found. Run: ./scripts/build-kernel.sh ${BOARD}"
    fi

    # Check rootfs
    if [ ! -f "${ROOTFS_DIR}/debian-rootfs.img" ]; then
        error "Rootfs image not found. Run: ./scripts/build-debian-rootfs.sh"
    fi

    # Check U-Boot (from rkbin)
    if [ ! -d "${PROJECT_ROOT}/rkbin" ]; then
        warn "rkbin not found. Cloning..."
        git clone https://github.com/rockchip-linux/rkbin.git "${PROJECT_ROOT}/rkbin"
    fi

    log "✓ All components found"
}

use_existing_uboot() {
    step "Using existing U-Boot binaries"

    # For now, use pre-built U-Boot to avoid bricking boards during development
    # When we have a spare board for testing, we can enable custom U-Boot builds

    mkdir -p "${OUTPUT_DIR}/u-boot"

    # Board already has U-Boot flashed to eMMC/SPI
    # We only create boot + rootfs partitions
    # Existing U-Boot will boot from SD card

    log "✓ Using existing U-Boot on board (not flashing new U-Boot)"
    log "  This avoids risk of bricking the board during development"
}

# build_uboot() {
#     # TODO: Enable this when we have a spare board for U-Boot development
#     # Building/flashing U-Boot can brick the board if something goes wrong
#
#     step "Building U-Boot for RK3568"
#
#     local uboot_dir="${PROJECT_ROOT}/u-boot"
#
#     if [ ! -d "${uboot_dir}" ]; then
#         log "Cloning U-Boot..."
#         git clone --depth=1 -b v2024.10 https://github.com/u-boot/u-boot.git "${uboot_dir}"
#     fi
#
#     cd "${uboot_dir}"
#
#     log "Configuring U-Boot..."
#     make CROSS_COMPILE=aarch64-linux-gnu- distclean || true
#     make CROSS_COMPILE=aarch64-linux-gnu- evb-rk3568_defconfig
#
#     log "Building U-Boot..."
#     export BL31="${PROJECT_ROOT}/rkbin/bin/rk35/rk3568_bl31_v1.45.elf"
#     make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
#
#     log "Creating boot images..."
#     ./tools/mkimage -n rk3568 -T rksd \
#         -d "${PROJECT_ROOT}/rkbin/bin/rk35/rk3568_ddr_1560MHz_v1.23.bin:spl/u-boot-spl.bin" \
#         idbloader.img
#
#     mkdir -p "${OUTPUT_DIR}/u-boot"
#     cp -v idbloader.img u-boot.itb "${OUTPUT_DIR}/u-boot/"
#
#     cd "${PROJECT_ROOT}"
#     log "✓ U-Boot build complete"
# }

create_image_file() {
    step "Creating disk image file"

    IMAGE_FILE="${OUTPUT_DIR}/${IMAGE_NAME}.img"

    log "Image size: ${IMAGE_SIZE} MB"
    log "Creating: ${IMAGE_FILE}"

    # Create sparse file (faster)
    dd if=/dev/zero of="${IMAGE_FILE}" bs=1M count=0 seek="${IMAGE_SIZE}" status=none

    log "✓ Image file created"
}

partition_image() {
    step "Creating partition table"

    local boot_start
    local boot_end
    local rootfs_start

    if [ "${WITH_UBOOT}" = true ]; then
        # With U-Boot: Reserve space for bootloader
        # 0-63:        Reserved (32KB)
        # 64-16383:    idbloader.img (8MB)
        # 16384-32767: u-boot.itb (8MB)
        # 32768+:      Boot partition (256MB)
        boot_start=32768  # 16MB
        log "Partition layout (with U-Boot):"
        log "  Reserved:    0 - 32KB"
        log "  idbloader:   32KB - 8MB (sector 64)"
        log "  u-boot:      8MB - 16MB (sector 16384)"
        log "  Boot:        16MB - $((16 + BOOT_SIZE))MB"
    else
        # Without U-Boot: Start partitions earlier (board has U-Boot already)
        boot_start=2048   # 1MB (standard GPT start)
        log "Partition layout (using existing U-Boot on board):"
        log "  Boot:        1MB - $((1 + BOOT_SIZE))MB"
    fi

    boot_end=$((boot_start + BOOT_SIZE * 2048))
    rootfs_start=$((boot_end + 1))  # Start one sector after boot partition ends

    log "  Rootfs:      $((boot_start / 2048 + BOOT_SIZE))MB - ${IMAGE_SIZE}MB"

    # Create GPT partition table
    parted -s "${IMAGE_FILE}" mklabel gpt
    parted -s "${IMAGE_FILE}" mkpart primary ext4 ${boot_start}s ${boot_end}s
    parted -s "${IMAGE_FILE}" mkpart primary ext4 ${rootfs_start}s 100%
    # Set legacy BIOS bootable flag for U-Boot to detect it
    parted -s "${IMAGE_FILE}" set 1 legacy_boot on
    parted -s "${IMAGE_FILE}" set 1 boot on

    log "✓ Partitions created"
}

flash_bootloader() {
    if [ "${WITH_UBOOT}" != true ]; then
        log "Skipping U-Boot flash (using existing U-Boot on board)"
        return
    fi

    step "Flashing bootloader to image"

    local uboot_dir="${OUTPUT_DIR}/uboot"

    # Mainline U-Boot creates a unified u-boot-rockchip.bin image
    if [ ! -f "${uboot_dir}/u-boot-rockchip.bin" ]; then
        error "U-Boot binary not found: ${uboot_dir}/u-boot-rockchip.bin
Run: ./scripts/build-uboot.sh ${BOARD}"
    fi

    warn "⚠️  Flashing mainline U-Boot - this can brick your board if interrupted!"
    warn "   Make sure you have maskrom recovery available"
    sleep 2

    log "Writing u-boot-rockchip.bin at sector 64..."
    log "  (Unified image contains: TPL, SPL, ATF, U-Boot proper)"
    dd if="${uboot_dir}/u-boot-rockchip.bin" of="${IMAGE_FILE}" \
        seek=64 conv=notrunc,fsync status=none

    log "✓ Mainline U-Boot flashed (unified image at sector 64)"
}

setup_loop_device() {
    step "Setting up loop device"

    # Find free loop device
    LOOP_DEV=$(losetup -f)
    losetup -P "${LOOP_DEV}" "${IMAGE_FILE}"

    # Wait for partition devices to appear
    sleep 2

    BOOT_PART="${LOOP_DEV}p1"
    ROOT_PART="${LOOP_DEV}p2"

    log "Loop device: ${LOOP_DEV}"
    log "Boot partition: ${BOOT_PART}"
    log "Root partition: ${ROOT_PART}"

    # Verify partition devices exist
    if [ ! -b "${BOOT_PART}" ] || [ ! -b "${ROOT_PART}" ]; then
        error "Partition devices not created. Try: sudo partprobe ${LOOP_DEV}"
    fi
}

format_partitions() {
    step "Formatting partitions"

    log "Formatting boot partition (ext4)..."
    mkfs.ext4 -F -L "BOOT" "${BOOT_PART}" >/dev/null

    log "Formatting root partition (ext4)..."
    mkfs.ext4 -F -L "ROOTFS" "${ROOT_PART}" >/dev/null

    log "✓ Partitions formatted"
}

install_boot_files() {
    step "Installing boot files"

    # Mount boot partition
    mkdir -p "${WORK_DIR}/boot"
    mount "${BOOT_PART}" "${WORK_DIR}/boot"

    # Copy kernel
    log "Copying kernel Image..."
    cp "${KERNEL_DIR}/arch/arm64/boot/Image" "${WORK_DIR}/boot/"

    # Copy DTB
    log "Copying device tree: ${DTB_NAME}.dtb..."
    mkdir -p "${WORK_DIR}/boot/dtbs/rockchip"
    cp "${KERNEL_DIR}/arch/arm64/boot/dts/rockchip/${DTB_NAME}.dtb" \
        "${WORK_DIR}/boot/dtbs/rockchip/"
    # Also copy to root of boot partition for easier manual loading
    cp "${KERNEL_DIR}/arch/arm64/boot/dts/rockchip/${DTB_NAME}.dtb" \
        "${WORK_DIR}/boot/"

    # Copy U-Boot images if available (for on-board flashing with manage-uboot)
    if [ -d "${OUTPUT_DIR}/uboot" ] && [ -f "${OUTPUT_DIR}/uboot/idbloader.img" ]; then
        log "Copying U-Boot images to boot partition..."
        mkdir -p "${WORK_DIR}/boot/uboot"
        cp "${OUTPUT_DIR}/uboot/idbloader.img" "${WORK_DIR}/boot/uboot/"
        cp "${OUTPUT_DIR}/uboot/uboot.img" "${WORK_DIR}/boot/uboot/"
        cp "${OUTPUT_DIR}/uboot/trust.img" "${WORK_DIR}/boot/uboot/"
        log "✓ U-Boot images copied (available for on-board flashing)"
    fi

    # Get PARTUUID of root partition for boot.scr
    # This is read from the actual partition we just created, so it will always match
    log "Getting root partition PARTUUID..."
    ROOT_PARTUUID=$(blkid -s PARTUUID -o value "${ROOT_PART}")
    log "Root PARTUUID: ${ROOT_PARTUUID}"

    # NOTE: We skip extlinux.conf because this U-Boot checks extlinux BEFORE boot scripts,
    # and extlinux cannot clear the existing bootargs that interfere with root device selection.
    # Boot.scr gives us full control to clear bootargs before setting new ones.

    # Create boot.scr for U-Boot
    # This ensures bootargs is set correctly without interference from saved env vars
    log "Creating boot script (boot.scr)..."
    cat > "${WORK_DIR}/boot/boot.cmd" << EOF
# U-Boot boot script for Debian RK3568
# This script ensures clean bootargs without interference from saved environment

echo "=== Debian RK3568 Boot Script ==="

# Clear any existing bootargs by setting to empty (compatible with all U-Boot versions)
setenv bootargs

# Set bootargs explicitly
# video=HDMI-A-1:1920x1080@60e forces mode when DDC/EDID fails
# clk_ignore_unused prevents UART clock disable
setenv bootargs "root=PARTUUID=${ROOT_PARTUUID} rootwait rw console=ttyS2,1500000 earlycon=uart8250,mmio32,0xfe660000 clk_ignore_unused video=HDMI-A-1:1920x1080@60e"

# Load kernel and DTB from current boot device
load \${devtype} \${devnum}:\${distro_bootpart} \${kernel_addr_r} /Image
load \${devtype} \${devnum}:\${distro_bootpart} \${fdt_addr_r} /dtbs/rockchip/${DTB_NAME}.dtb

# Boot the kernel
booti \${kernel_addr_r} - \${fdt_addr_r}
EOF

    # Compile boot.cmd to boot.scr.uimg
    # Use -A arm (32-bit) not arm64 because U-Boot runs in 32-bit mode even on 64-bit SoC
    mkimage -C none -A arm -T script -d "${WORK_DIR}/boot/boot.cmd" "${WORK_DIR}/boot/boot.scr.uimg"

    sync
    umount "${WORK_DIR}/boot"

    log "✓ Boot files installed"
}

install_rootfs() {
    step "Installing rootfs (this may take a few minutes)"

    # Mount root partition
    mkdir -p "${WORK_DIR}/root"
    mount "${ROOT_PART}" "${WORK_DIR}/root"

    # Mount rootfs image
    mkdir -p "${WORK_DIR}/rootfs-src"
    local rootfs_loop=$(losetup -f)
    losetup "${rootfs_loop}" "${ROOTFS_DIR}/debian-rootfs.img"
    mount "${rootfs_loop}" "${WORK_DIR}/rootfs-src"

    # Copy rootfs contents
    log "Copying rootfs contents..."
    cp -a "${WORK_DIR}/rootfs-src"/* "${WORK_DIR}/root/"

    # Create boot mount point
    mkdir -p "${WORK_DIR}/root/boot"

    # Update fstab
    log "Creating fstab..."
    cat > "${WORK_DIR}/root/etc/fstab" << 'EOF'
# <file system> <mount point> <type> <options> <dump> <pass>
LABEL=ROOTFS    /               ext4    defaults,noatime    0   1
LABEL=BOOT      /boot           ext4    defaults,noatime    0   2
tmpfs           /tmp            tmpfs   defaults,nosuid     0   0
EOF

    # Create release info
    log "Creating release info..."
    cat > "${WORK_DIR}/root/etc/rk3568-release" << EOF
BOARD=${BOARD}
BOARD_DESC=${BOARD_DESC}
DTB=${DTB_NAME}.dtb
BUILD_DATE=$(date)
KERNEL_VERSION=$(cat ${KERNEL_DIR}/include/config/kernel.release 2>/dev/null || echo "6.6-rockchip")
IMAGE_VERSION=${IMAGE_NAME}
BUILD_SYSTEM=debian-build-system
EOF

    # Install kernel modules from .deb package
    local kernel_deb=$(ls -1t "${OUTPUT_DIR}/kernel-debs"/linux-image-*.deb 2>/dev/null | grep -v '\-dbg' | head -1)
    if [ -n "$kernel_deb" ] && [ -f "$kernel_deb" ]; then
        log "Installing kernel modules from $(basename "$kernel_deb")..."
        # Extract modules from deb to temp dir, then copy to rootfs
        local tmp_extract=$(mktemp -d)
        ar -x "$kernel_deb" --output="$tmp_extract"
        if [ -f "$tmp_extract/data.tar.zst" ]; then
            zstd -d "$tmp_extract/data.tar.zst" -c | tar -xf - -C "$tmp_extract" ./lib/modules 2>/dev/null || true
        elif [ -f "$tmp_extract/data.tar.xz" ]; then
            tar -xJf "$tmp_extract/data.tar.xz" -C "$tmp_extract" ./lib/modules 2>/dev/null || true
        elif [ -f "$tmp_extract/data.tar.gz" ]; then
            tar -xzf "$tmp_extract/data.tar.gz" -C "$tmp_extract" ./lib/modules 2>/dev/null || true
        fi
        if [ -d "$tmp_extract/lib/modules" ]; then
            # Ensure target directory exists (cp behaves differently if it doesn't)
            mkdir -p "${WORK_DIR}/root/lib/modules"
            # Copy each versioned modules directory (e.g., 6.12.0-dirty/) preserving structure
            for moddir in "$tmp_extract/lib/modules"/*; do
                if [ -d "$moddir" ]; then
                    cp -a "$moddir" "${WORK_DIR}/root/lib/modules/"
                fi
            done
            log "✓ Kernel modules installed"
        else
            warn "Could not extract modules from deb package"
        fi
        rm -rf "$tmp_extract"
    elif [ -d "${KERNEL_DIR}/modules_install" ]; then
        # Fallback to legacy modules_install directory
        log "Installing kernel modules from modules_install..."
        cp -a "${KERNEL_DIR}/modules_install/lib/modules" "${WORK_DIR}/root/lib/" || true
    else
        warn "No kernel modules found - WiFi and other module-based drivers will not work"
    fi

    # Cleanup and unmount
    sync
    umount "${WORK_DIR}/rootfs-src"
    losetup -d "${rootfs_loop}"
    umount "${WORK_DIR}/root"

    log "✓ Rootfs installed"
}

cleanup_loop_device() {
    step "Cleaning up"

    sync
    sleep 1

    # Unmount anything still mounted
    umount "${WORK_DIR}/boot" 2>/dev/null || true
    umount "${WORK_DIR}/root" 2>/dev/null || true
    umount "${WORK_DIR}/rootfs-src" 2>/dev/null || true

    # Detach loop devices
    losetup -d "${LOOP_DEV}" 2>/dev/null || true

    # Remove work directory
    rm -rf "${WORK_DIR}"

    log "✓ Cleanup complete"
}

compress_image() {
    step "Compressing image"

    log "Compressing to ${IMAGE_NAME}.img.xz (this takes ~5 minutes)..."
    xz -T0 -9 -k "${IMAGE_FILE}"

    log "✓ Image compressed"
}

calculate_checksums() {
    step "Calculating checksums"

    cd "${OUTPUT_DIR}"

    log "Creating SHA256 checksums..."
    sha256sum "$(basename ${IMAGE_FILE})" > "${IMAGE_NAME}.img.sha256"
    sha256sum "$(basename ${IMAGE_FILE}).xz" > "${IMAGE_NAME}.img.xz.sha256"

    log "✓ Checksums created"
    cd "${PROJECT_ROOT}"
}

create_flash_instructions() {
    step "Creating flash instructions"

    cat > "${OUTPUT_DIR}/${IMAGE_NAME}-FLASH.txt" << EOF
# Flashing Instructions for RK3568 Debian Image

Board: ${BOARD_DESC}
Image: ${IMAGE_NAME}
Date:  $(date)

## What's Included

- Ubuntu 24.04 LTS with XFCE desktop
- Rockchip kernel 6.6 LTS
- Mali G52 GPU drivers (hardware acceleration)
- Network support (Ethernet + WiFi)
- Full multimedia support

## Requirements

- microSD card (minimum 8GB, recommend 16GB+)
- Card reader
- Linux/macOS/Windows PC

## Method 1: Linux/macOS (dd)

1. Decompress the image:
   xz -d ${IMAGE_NAME}.img.xz

2. Identify SD card device:
   lsblk          # Linux
   diskutil list  # macOS

3. Flash the image (replace sdX with your device):
   sudo dd if=${IMAGE_NAME}.img of=/dev/sdX bs=4M status=progress conv=fsync

   ⚠️  WARNING: This will erase all data on the SD card!
   ⚠️  Double-check the device name!

4. Eject:
   sudo eject /dev/sdX

## Method 2: balenaEtcher (All platforms)

1. Download: https://www.balena.io/etcher/
2. Select ${IMAGE_NAME}.img.xz (no need to decompress)
3. Select your SD card
4. Click "Flash!"

## First Boot

1. Insert SD card into board
2. Connect HDMI display
3. Connect Ethernet cable (or configure WiFi later)
4. Connect power

## Default Credentials

Desktop auto-login: rock / rock
Root access:       root / root

⚠️  Change passwords immediately:
    passwd          # Change rock password
    sudo passwd root # Change root password

## Network Configuration

Ethernet: Auto-configured (DHCP)
WiFi:     Click network icon in system tray
          Or use: nmtui

## Serial Console (Optional)

Port: /dev/ttyUSB0 (UART2)
Baud: 1500000
Settings: 8N1

## Verification

After boot, check:
    cat /etc/rk3568-release    # Build info
    uname -a                   # Kernel version
    glxinfo | grep OpenGL      # GPU info (if installed)

## Troubleshooting

No boot:
  - Check power supply (5V/3A minimum)
  - Connect serial console to see boot messages
  - Verify SD card is fully inserted

No display:
  - Check HDMI cable
  - Try different HDMI port
  - May need different DTB for your board variant

No network:
  - Check Ethernet cable
  - Verify DHCP server on network
  - Check: ip address

GPU not working:
  - Check: ls -la /dev/mali0
  - Check: ls -la /usr/lib/aarch64-linux-gnu/libmali*

## Manual Boot (If U-Boot doesn't auto-boot)

If the board doesn't automatically boot from SD, use these U-Boot commands:

1. Interrupt U-Boot (press any key during countdown)

2. Load kernel and device tree:
   ext4load mmc 1:1 0x02080000 /Image
   ext4load mmc 1:1 0x0a100000 /${DTB_NAME}

3. Set boot arguments:
   setenv bootargs console=ttyS2,1500000 root=/dev/mmcblk1p2 rootwait rw

4. Boot:
   booti 0x02080000 - 0x0a100000

Note: If using SD in slot 0, change mmc 1:1 to mmc 0:1 and root=/dev/mmcblk0p2

## eMMC Provisioning Workflow

To install to internal eMMC storage:

1. Boot from SD card (as above)
2. Login: rock / rock
3. Run provisioning tool:
   sudo setup-emmc

4. The tool will:
   - Detect SD card and eMMC automatically
   - Partition and format eMMC
   - Copy entire system to eMMC (takes ~5 minutes)
   - Configure boot loader

5. Shutdown and remove SD card:
   sudo poweroff

6. Power on - board will boot from eMMC

This workflow is ideal for:
- Testing new builds on SD before committing to eMMC
- Provisioning multiple boards from single SD image
- Recovery (boot from SD, reflash eMMC)

## Support

Project: https://github.com/aaronsb/rk356x
EOF

    log "✓ Flash instructions created"
}

show_summary() {
    log ""
    log "════════════════════════════════════════════════════════════════"
    log "  ✓ Image Assembly Complete!"
    log "════════════════════════════════════════════════════════════════"
    log ""
    log "Board:           ${BOARD_DESC}"
    log "DTB:             ${DTB_NAME}.dtb"
    log "Image file:      ${IMAGE_FILE}"
    log "Compressed:      ${IMAGE_FILE}.xz"
    log "Image size:      $(du -h ${IMAGE_FILE} | cut -f1)"
    log "Compressed size: $(du -h ${IMAGE_FILE}.xz | cut -f1)"
    log ""
    log "Files created:"
    ls -lh "${OUTPUT_DIR}/${IMAGE_NAME}"* | awk '{print "  " $9 "  (" $5 ")"}'
    log ""
    log "To flash to SD card:"
    log "  sudo dd if=${IMAGE_FILE} of=/dev/sdX bs=4M status=progress"
    log ""
    log "Or use balenaEtcher with ${IMAGE_NAME}.img.xz"
    log ""
    log "Instructions: ${OUTPUT_DIR}/${IMAGE_NAME}-FLASH.txt"
    log "════════════════════════════════════════════════════════════════"
}

main() {
    log "Assembling Debian image for ${BOARD}"
    log ""

    check_root
    check_deps
    check_components

    # Use existing U-Boot (safer until we have a spare board)
    use_existing_uboot

    create_image_file
    partition_image
    flash_bootloader
    setup_loop_device

    # Set trap for cleanup
    trap cleanup_loop_device EXIT

    format_partitions
    install_boot_files
    install_rootfs

    cleanup_loop_device
    trap - EXIT

    compress_image
    calculate_checksums
    create_flash_instructions

    show_summary
}

main "$@"
