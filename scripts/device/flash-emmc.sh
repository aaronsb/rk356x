#!/bin/bash
#
# Flash mainline build to eMMC via USB OTG (maskrom mode)
#
# Usage: ./scripts/flash-emmc.sh [OPTIONS] [image.img]
#
# Options:
#   --uboot-only    Only flash U-Boot (clears eMMC boot area, boots from SD)
#   --wipe          Wipe entire eMMC before flashing
#
# If no image specified, uses the most recent image in output/
#
# Prerequisites:
#   - Board in maskrom mode (hold recovery button while powering on)
#   - USB OTG cable connected
#   - rkdeveloptool installed (apt install rkdeveloptool)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common libraries for consistent UI
source "${SCRIPT_DIR}/../lib/ui.sh"

# Override PROJECT_ROOT since we're in device/ not scripts/
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
RKBIN_DIR="${PROJECT_ROOT}/rkbin"
OUTPUT_DIR="${PROJECT_ROOT}/output"
UBOOT_DIR="${OUTPUT_DIR}/uboot"

# Options
UBOOT_ONLY=false
WIPE_EMMC=false
FLASH_LATEST=false

# Show usage
usage() {
    echo "RK3568 eMMC Flash Tool"
    echo ""
    echo "Usage: sudo $0 [OPTIONS] [image.img]"
    echo ""
    echo "Options:"
    echo "  --latest        Flash the latest image from output/"
    echo "  --uboot-only    Flash U-Boot only (board will boot from SD card)"
    echo "  --wipe          Wipe entire eMMC before flashing"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo $0 --latest             # Flash latest image to eMMC"
    echo "  sudo $0 --uboot-only         # Flash U-Boot only, boot from SD"
    echo "  sudo $0 --wipe my-image.img  # Wipe eMMC and flash specific image"
    echo ""
    exit 0
}

# Parse arguments
parse_args() {
    # Show help if no arguments
    if [[ $# -eq 0 ]]; then
        usage
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            --latest)
                FLASH_LATEST=true
                shift
                ;;
            --uboot-only)
                UBOOT_ONLY=true
                shift
                ;;
            --wipe)
                WIPE_EMMC=true
                shift
                ;;
            -*)
                error "Unknown option: $1"
                ;;
            *)
                IMAGE_ARG="$1"
                shift
                ;;
        esac
    done
}

# Check for root/sudo
check_permissions() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run with sudo: sudo $0 $*"
    fi
}

# Find rkdeveloptool
find_rkdeveloptool() {
    if command -v rkdeveloptool &>/dev/null; then
        RKDEV="rkdeveloptool"
    elif [ -x "/usr/local/bin/rkdeveloptool" ]; then
        RKDEV="/usr/local/bin/rkdeveloptool"
    else
        error "rkdeveloptool not found. Install with: apt install rkdeveloptool"
    fi
    log "Using: $RKDEV"
}

# Check device is in maskrom mode
check_device() {
    log "Checking for device in maskrom mode..."

    local device_info
    device_info=$($RKDEV ld 2>&1) || true

    if echo "$device_info" | grep -q "Maskrom"; then
        log "Device found in maskrom mode"
        return 0
    else
        echo ""
        echo "No device found in maskrom mode."
        echo ""
        echo "To enter maskrom mode:"
        echo "  1. Power off the board"
        echo "  2. Hold the RECOVERY button"
        echo "  3. Connect USB OTG cable (or press RESET if already connected)"
        echo "  4. Release RECOVERY button after 2 seconds"
        echo ""
        error "Device not in maskrom mode"
    fi
}

# Create or find loader
prepare_loader() {
    LOADER="${RKBIN_DIR}/rk356x_spl_loader_v1.23.114.bin"

    if [ ! -f "$LOADER" ]; then
        log "Creating loader from RKBOOT config..."

        if [ ! -f "${RKBIN_DIR}/RKBOOT/RK3568MINIALL.ini" ]; then
            error "RKBOOT config not found. Ensure rkbin submodule is initialized."
        fi

        cd "$RKBIN_DIR"
        ./tools/boot_merger RKBOOT/RK3568MINIALL.ini || error "Failed to create loader"
        cd "$PROJECT_ROOT"

        if [ ! -f "$LOADER" ]; then
            # Check for alternate naming
            LOADER=$(ls -t "${RKBIN_DIR}"/rk356x_spl_loader*.bin 2>/dev/null | head -1)
            [ -z "$LOADER" ] && error "Loader creation failed"
        fi
    fi

    log "Using loader: $(basename "$LOADER")"
}

# Find U-Boot binary
find_uboot() {
    UBOOT_BIN="${UBOOT_DIR}/u-boot-rockchip.bin"

    if [ ! -f "$UBOOT_BIN" ]; then
        error "U-Boot not found at $UBOOT_BIN. Build first with: ./scripts/build-kernel.sh"
    fi

    log "U-Boot: $(basename "$UBOOT_BIN")"
}

# Wipe eMMC
wipe_emmc() {
    log "Wiping eMMC (erasing all data)..."

    if ! $RKDEV ef; then
        error "Failed to erase flash"
    fi

    log "eMMC wiped successfully"
}

# Write U-Boot only (sector 64 = 0x40)
write_uboot() {
    log "Writing U-Boot to eMMC at sector 64..."

    if ! $RKDEV wl 64 "$UBOOT_BIN"; then
        error "Failed to write U-Boot"
    fi

    log "U-Boot written successfully"
}

# Find image to flash
find_image() {
    if [ -n "$IMAGE_ARG" ] && [ -f "$IMAGE_ARG" ]; then
        IMAGE="$IMAGE_ARG"
    else
        # Find most recent image
        IMAGE=$(ls -t "${OUTPUT_DIR}"/rk3568-debian-*.img 2>/dev/null | head -1)

        if [ -z "$IMAGE" ] || [ ! -f "$IMAGE" ]; then
            error "No image found. Build first with: ./scripts/build-kernel.sh && ./scripts/assemble-debian-image.sh"
        fi
    fi

    IMAGE_SIZE=$(stat -c%s "$IMAGE" 2>/dev/null || stat -f%z "$IMAGE")
    IMAGE_SIZE_GB=$(echo "scale=2; $IMAGE_SIZE / 1073741824" | bc)

    log "Image: $(basename "$IMAGE") (${IMAGE_SIZE_GB}GB)"
}

# Download loader to device
download_loader() {
    log "Downloading loader to initialize DRAM..."

    if ! $RKDEV db "$LOADER"; then
        error "Failed to download loader. Check USB connection."
    fi

    sleep 1
    log "Loader downloaded successfully"
}

# Write image to eMMC
write_image() {
    log "Writing image to eMMC (this will take several minutes)..."
    echo ""

    if ! $RKDEV wl 0 "$IMAGE"; then
        error "Failed to write image"
    fi

    echo ""
    log "Image written successfully"
}

# Reboot device
reboot_device() {
    log "Rebooting device..."
    $RKDEV rd || warn "Reboot command failed, manually power cycle the board"
}

# Main
main() {
    parse_args "$@"

    echo "=========================================="
    echo "  RK3568 eMMC Flash Tool"
    echo "=========================================="
    echo ""

    check_permissions "$@"
    find_rkdeveloptool
    check_device
    prepare_loader

    if $UBOOT_ONLY; then
        # U-Boot only mode
        find_uboot

        echo ""
        echo "Ready to flash U-Boot only:"
        echo "  U-Boot: $(basename "$UBOOT_BIN")"
        echo "  Loader: $(basename "$LOADER")"
        echo ""
        echo "This will clear the eMMC boot area so the board boots from SD card."
        echo ""
        read -p "Continue? [y/N] " -n 1 -r
        echo ""

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cancelled"
            exit 0
        fi

        download_loader
        if $WIPE_EMMC; then
            wipe_emmc
        fi
        write_uboot
        reboot_device

        echo ""
        log "U-Boot flashed! Board will now boot from SD card."
        echo ""
    else
        # Full image mode
        find_image

        echo ""
        echo "Ready to flash:"
        echo "  Image:  $(basename "$IMAGE")"
        echo "  Loader: $(basename "$LOADER")"
        if $WIPE_EMMC; then
            echo "  Wipe:   YES (will erase all data first)"
        fi
        echo ""
        read -p "Continue? [y/N] " -n 1 -r
        echo ""

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cancelled"
            exit 0
        fi

        download_loader
        if $WIPE_EMMC; then
            wipe_emmc
        fi
        write_image
        reboot_device

        echo ""
        log "Flash complete! Device is rebooting."
        echo ""
        echo "Default credentials: rock/rock"
        echo ""
    fi
}

main "$@"
