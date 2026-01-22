# RK356X Project - Claude Context

## Build System

Debian-based build system with modular scripts. Each script can run standalone or through the orchestrator.

- **Documentation:** See [HOW-TO-BUILD.md](HOW-TO-BUILD.md)
- **Quick Start:** `./scripts/build.sh sz3568-v1.2` (interactive) or `./scripts/build.sh --auto sz3568-v1.2`

## Supported Boards

Boards are defined in `boards/*/board.conf`:

| Board | Canonical Name | Aliases | Description |
|-------|----------------|---------|-------------|
| DC-A568-V06 | `dc-a568-v06` | `rk3568_custom` | RMII ethernet |
| SZ3568-V1.2 | `sz3568-v1.2` | `rk3568_sz3568` | RGMII ethernet with MAXIO MAE0621A PHY |

## Build Commands

### Orchestrator (interactive workflow)

```bash
# Interactive build (recommended)
./scripts/build.sh sz3568-v1.2

# Auto mode: build missing, flash to SD
./scripts/build.sh --auto --device /dev/sdX sz3568-v1.2

# Clean all artifacts
./scripts/build.sh --clean sz3568-v1.2

# Build specific stage only
./scripts/build.sh --kernel-only sz3568-v1.2
./scripts/build.sh --rootfs-only sz3568-v1.2
./scripts/build.sh --image-only sz3568-v1.2
```

### Standalone Scripts (for direct control)

Each script follows the pattern: `<script> <board> <command>`

```bash
# Kernel
./scripts/build/kernel.sh sz3568-v1.2 build
./scripts/build/kernel.sh sz3568-v1.2 info

# U-Boot
./scripts/build/uboot.sh sz3568-v1.2 build

# Rootfs
./scripts/build/rootfs.sh sz3568-v1.2 build

# Image assembly
sudo ./scripts/device/assemble.sh sz3568-v1.2 build

# Flash to SD card
sudo ./scripts/device/flash-sd.sh sz3568-v1.2 flash

# Flash to eMMC (maskrom mode)
sudo ./scripts/device/flash-emmc.sh --latest
```

Build happens in Docker container (ubuntu:22.04) for reproducibility.

## Directory Structure

```
rk356x/
├── boards/                       # Board configurations (source of truth)
│   ├── sz3568-v1.2/board.conf
│   └── dc-a568-v06/board.conf
├── scripts/
│   ├── build.sh                  # Thin orchestrator
│   ├── lib/                      # Shared libraries
│   │   ├── common.sh             # Loads all libs
│   │   ├── ui.sh                 # Colors, logging
│   │   ├── board.sh              # Board lookup
│   │   └── artifacts.sh          # Artifact detection
│   ├── build/                    # Build scripts
│   │   ├── kernel.sh
│   │   ├── uboot.sh
│   │   └── rootfs.sh
│   └── device/                   # Device scripts
│       ├── assemble.sh
│       ├── flash-sd.sh
│       └── flash-emmc.sh
├── rkbin/                        # Vendor blobs (git submodule)
├── external/custom/              # Board customizations
│   └── board/rk3568/
│       ├── dts/rockchip/         # Custom device trees
│       ├── kernel.config         # Kernel config fragment
│       ├── rootfs-overlay/       # Files copied to rootfs
│       └── drivers/              # Reference driver sources
└── output/                       # Build artifacts
    ├── kernel-debs/              # Kernel .deb packages
    ├── uboot/                    # U-Boot binaries
    └── rk3568-debian-*.img       # Final images
```

## Key Technical Details

### SZ3568 Ethernet (MAXIO MAE0621A PHY)

The SZ3568 uses a MAXIO MAE0621A Gigabit PHY requiring:
1. **Full vendor driver** (`maxio.c`) - NOT generic PHY functions
2. **1000ms clock init delay** in `maxio_mae0621a_clk_init()`
3. **DMA reset patch** using blocking `mdelay()` instead of `readl_poll_timeout()`

PHY ID: `0x7b744411`

If ethernet fails with "Failed to reset the dma", the PHY clock isn't stabilized before GMAC tries to use it.

### Kernel Patches

Patches in `external/custom/patches/linux/` are applied automatically via `BR2_LINUX_KERNEL_PATCH` in defconfig.

**IMPORTANT:** When modifying patches, you must clean the linux build dirs:
```bash
rm -rf buildroot/output/build/linux-develop-6.1 buildroot/output/build/linux-headers-develop-6.1
```
Then run `build` (not `linux-rebuild`) to re-extract and re-patch.

### Persistent MAC Address

MAC address is generated from CPU serial number at boot via:
- `/usr/local/bin/set-mac-from-serial`
- `set-mac.service` (systemd)

This ensures consistent MAC across reboots without hardcoding.

### System Banner

`/etc/issue` is updated periodically by `update-issue.timer` to show:
- Network status (IP, ethernet speed, WiFi)
- Hardware status (HDMI, USB devices, storage)

## Workflow

1. **Modify config** - Edit files in `external/custom/` or `boards/`
2. **Build** - `./scripts/build.sh sz3568-v1.2` (or standalone scripts)
3. **Test** - Flash to SD card or eMMC
4. **Commit** - All changes tracked in git
5. **Repeat**

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Failed to reset the dma" | PHY clock not stable | Ensure maxio driver patch applied |
| Patches not applying | Stale build artifacts | `./scripts/build/kernel.sh <board> clean` |
| Docker path errors | Mixed Docker/native builds | `./scripts/build.sh --clean <board>` |
| Missing rkbin blobs | Submodule not initialized | `git submodule update --init --recursive` |

## Kernel Config

The kernel uses Rockchip's 6.1 BSP kernel (`rockchip_linux_defconfig`) plus a config fragment at `external/custom/board/rk3568/kernel.config` that enables:
- MAXIO_PHY driver
- STMMAC ethernet
- USB HID (keyboard/mouse)
- HDMI/DRM display
- RK809 audio codec
- WiFi (cfg80211/mac80211 as modules)

## Testing on Hardware

Default credentials: `root` / `root`

### Connecting to the Board

**SSH (for Claude Code to run commands):**
```bash
sshpass -p 'root' ssh -o StrictHostKeyChecking=no root@192.168.1.x "<command>"
```

**Serial console (for user interaction):**
```bash
picocom -b 1500000 /dev/ttyUSB0
```
Baud rate is 1500000, serial port is ttyS2 on the board.

### Hardware Status Checks

```bash
ip address                    # Ethernet
cat /sys/class/drm/*/status   # HDMI
iw dev wlan0 scan             # WiFi
aplay -l                      # Audio
lsusb                         # USB
dmesg | grep -i eth           # Ethernet driver messages
dmesg | grep -i maxio         # PHY driver messages
```

### Typical Test Workflow

1. User connects via picocom to see boot messages and interact
2. Board boots and gets DHCP address
3. Claude Code uses sshpass to run diagnostic commands
4. Results inform next iteration of config changes

## Finding Driver Sources

Use `gh search code` to find upstream sources for vendor drivers:

```bash
# Search for driver by unique string
gh search code "MAXIO_PHY_VER" --limit 5

# Get exact file URL
gh api search/code -X GET -f q="MAXIO_PHY_VER v1.8.1.4" --jq '.items[0].html_url'
```

**Always document sources** in `external/custom/board/rk3568/drivers/README.md` so code doesn't appear from "thin air".

Current driver sources:
- **maxio.c**: https://github.com/CoreELEC/common_drivers/blob/c758f3df5449105018701c8ce04869c7ab8811c4/drivers/net/phy/maxio.c
