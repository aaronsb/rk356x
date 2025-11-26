#!/bin/bash
set -e

# Flash images to RK3568 eMMC via USB OTG
# Requires board in Loader/Maskrom mode

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TOOLS_DIR="${ROOT_DIR}/tools"
IMAGES_DIR="${ROOT_DIR}/buildroot/output/images"

UPGRADE_TOOL="${TOOLS_DIR}/upgrade_tool"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "RK3568 eMMC Flash Tool"
echo "========================================"
echo ""

# Check for upgrade_tool
if [ ! -x "${UPGRADE_TOOL}" ]; then
    echo -e "${RED}ERROR:${NC} upgrade_tool not found"
    echo "Run: ./scripts/get-upgrade-tool.sh"
    exit 1
fi

# Check for required images
echo "Checking for images in: ${IMAGES_DIR}"
echo ""

MISSING=0
for img in idbloader.img u-boot.bin Image rootfs.ext4; do
    if [ -f "${IMAGES_DIR}/${img}" ]; then
        SIZE=$(ls -lh "${IMAGES_DIR}/${img}" | awk '{print $5}')
        echo -e "  ${GREEN}✓${NC} ${img} (${SIZE})"
    else
        echo -e "  ${RED}✗${NC} ${img} missing"
        MISSING=1
    fi
done

# Check for DTB
DTB=$(ls "${IMAGES_DIR}"/*.dtb 2>/dev/null | head -1)
if [ -n "${DTB}" ]; then
    SIZE=$(ls -lh "${DTB}" | awk '{print $5}')
    echo -e "  ${GREEN}✓${NC} $(basename ${DTB}) (${SIZE})"
else
    echo -e "  ${RED}✗${NC} No .dtb file found"
    MISSING=1
fi

echo ""

if [ "${MISSING}" -eq 1 ]; then
    echo -e "${RED}ERROR:${NC} Missing required images. Run build first."
    exit 1
fi

# Check device connection
echo "Checking for device in Loader/Maskrom mode..."
if ! "${UPGRADE_TOOL}" ld 2>/dev/null | grep -q "DevNo"; then
    echo ""
    echo -e "${YELLOW}No device found in Loader/Maskrom mode${NC}"
    echo ""
    echo "To enter Loader mode:"
    echo "  1. Connect USB OTG cable from board to PC"
    echo "  2. Press and HOLD the Recovery button"
    echo "  3. While holding, connect power"
    echo "  4. Wait 3 seconds, then release"
    echo ""
    echo "Then run this script again."
    exit 1
fi

echo -e "${GREEN}Device found!${NC}"
"${UPGRADE_TOOL}" ld
echo ""

# Confirm before flashing
echo -e "${YELLOW}WARNING: This will erase the eMMC!${NC}"
read -p "Continue? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "==> Flashing images..."
echo ""

# Flash idbloader (contains TPL + SPL)
echo "Flashing idbloader.img to sector 0x40..."
"${UPGRADE_TOOL}" wl 0x40 "${IMAGES_DIR}/idbloader.img"

# Flash u-boot.bin to sector 0x4000 (8MB offset)
echo "Flashing u-boot.bin to sector 0x4000..."
"${UPGRADE_TOOL}" wl 0x4000 "${IMAGES_DIR}/u-boot.bin"

echo ""
echo -e "${GREEN}========================================"
echo "✓ Bootloader flashed successfully!"
echo "========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. The board should now boot to U-Boot"
echo "  2. You can boot from SD card with kernel + rootfs"
echo "  3. Or flash kernel/rootfs to eMMC partitions"
echo ""
echo "To create a bootable SD card with kernel + rootfs:"
echo "  See docs for dd or balenaEtcher instructions"
echo ""
