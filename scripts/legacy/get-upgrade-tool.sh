#!/bin/bash
set -e

# Download Rockchip upgrade_tool for Linux
# This tool is used to flash images to RK3568 boards via USB OTG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TOOLS_DIR="${ROOT_DIR}/tools"

# upgrade_tool download URL (from Rockchip Linux tools)
UPGRADE_TOOL_URL="https://raw.githubusercontent.com/rockchip-linux/rkbin/master/tools/upgrade_tool"

echo "========================================"
echo "Rockchip upgrade_tool Installer"
echo "========================================"
echo ""

# Create tools directory
mkdir -p "${TOOLS_DIR}"

# Download upgrade_tool
echo "==> Downloading upgrade_tool..."
if curl -L -o "${TOOLS_DIR}/upgrade_tool" "${UPGRADE_TOOL_URL}"; then
    chmod +x "${TOOLS_DIR}/upgrade_tool"
    echo "✓ upgrade_tool downloaded to ${TOOLS_DIR}/upgrade_tool"
else
    echo "ERROR: Failed to download upgrade_tool"
    echo "Try downloading manually from:"
    echo "  https://github.com/rockchip-linux/rkbin/tree/master/tools"
    exit 1
fi

echo ""

# Check if udev rules exist for Rockchip devices
UDEV_RULE="/etc/udev/rules.d/99-rockchip.rules"
if [ ! -f "${UDEV_RULE}" ]; then
    echo "==> Setting up udev rules for Rockchip devices..."
    echo ""
    echo "The following udev rule will be created:"
    echo '  SUBSYSTEM=="usb", ATTR{idVendor}=="2207", MODE="0666"'
    echo ""
    echo "This allows flashing without sudo. Creating rule..."

    sudo tee "${UDEV_RULE}" > /dev/null << 'EOF'
# Rockchip USB devices
SUBSYSTEM=="usb", ATTR{idVendor}=="2207", MODE="0666"
EOF

    sudo udevadm control --reload-rules
    sudo udevadm trigger
    echo "✓ udev rules installed"
else
    echo "✓ udev rules already exist"
fi

echo ""
echo "========================================"
echo "✓ Installation Complete!"
echo "========================================"
echo ""
echo "Usage:"
echo "  ${TOOLS_DIR}/upgrade_tool ld              # List devices"
echo "  ${TOOLS_DIR}/upgrade_tool uf update.img   # Flash unified image"
echo ""
echo "To flash individual partitions:"
echo "  ${TOOLS_DIR}/upgrade_tool db MiniLoaderAll.bin"
echo "  ${TOOLS_DIR}/upgrade_tool wl 0x40 idbloader.img"
echo "  ${TOOLS_DIR}/upgrade_tool wl 0x4000 u-boot.itb"
echo ""
echo "See scripts/flash-emmc.sh for complete flashing instructions."
echo ""
