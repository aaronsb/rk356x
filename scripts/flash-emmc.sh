#!/bin/bash
#
# Flash mainline build to eMMC via USB OTG (maskrom mode)
#
# Usage: ./scripts/flash-emmc.sh [image.img]
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
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RKBIN_DIR="${PROJECT_ROOT}/rkbin"
OUTPUT_DIR="${PROJECT_ROOT}/output"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[FLASH]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

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

# Find image to flash
find_image() {
    if [ -n "$1" ] && [ -f "$1" ]; then
        IMAGE="$1"
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
    echo "=========================================="
    echo "  RK3568 eMMC Flash Tool"
    echo "=========================================="
    echo ""

    check_permissions "$@"
    find_rkdeveloptool
    check_device
    prepare_loader
    find_image "$1"

    echo ""
    echo "Ready to flash:"
    echo "  Image:  $(basename "$IMAGE")"
    echo "  Loader: $(basename "$LOADER")"
    echo ""
    read -p "Continue? [y/N] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cancelled"
        exit 0
    fi

    download_loader
    write_image
    reboot_device

    echo ""
    log "Flash complete! Device is rebooting."
    echo ""
    echo "Default credentials: rock/rock"
    echo ""
}

main "$@"
