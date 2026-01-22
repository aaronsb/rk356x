# RK356X Embedded Linux Build System

Complete build system for RK356X (RK3566/RK3568) boards with Debian 12, mainline kernel and U-Boot, and open-source Panfrost GPU drivers.

This project provides a production-ready Debian-based Linux system for RK356x ARM64 boards, featuring a modern Wayland desktop with hardware-accelerated graphics.

![WebGL Aquarium running at 38 FPS with Cog browser](docs/media/cog-webgl-aquarium-38fps.jpg)

*WebGL Aquarium demo running smoothly at 38 FPS using [Cog browser](docs/cog-browser.md) with Panfrost GPU acceleration.*

---

## Quick Start

```bash
# Clone with submodules (vendor blobs required)
git clone --recursive https://github.com/aaronsb/rk356x.git
cd rk356x

# Build complete system (interactive, recommended)
./scripts/build.sh sz3568-v1.2

# Auto mode: build what's missing
./scripts/build.sh --auto sz3568-v1.2

# Or build components individually
./scripts/build/kernel.sh sz3568-v1.2 build      # Kernel 6.12 with custom DTBs
./scripts/build/rootfs.sh sz3568-v1.2 build      # Debian 12 rootfs
sudo ./scripts/device/assemble.sh sz3568-v1.2 build  # Create bootable image
```

Output image location: `output/rk3568-debian-*.img.xz`

Flash to SD card:
```bash
sudo ./scripts/device/flash-sd.sh sz3568-v1.2 flash
# Or manually:
xzcat output/rk3568-debian-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress
```

Default credentials: `rock` / `rock`

---

## System Components

| Component | Version | Description |
|-----------|---------|-------------|
| U-Boot | Mainline 2024.10+ | Community-maintained, SD/eMMC boot support |
| Linux Kernel | 6.12 Mainline | Custom DTBs, Panfrost GPU, display subsystem |
| GPU Driver | Panfrost (Mesa) | Open-source Mali-G52, desktop OpenGL 3.1 |
| Root Filesystem | Debian 12 (bookworm) | LTS until June 2028 |
| Desktop | Wayland + sway | Tiling compositor, hardware accelerated |
| Browsers | Firefox ESR, Chromium, [Cog](docs/cog-browser.md) | WebGL support, Cog recommended for best performance |
| Init System | systemd | Networking and service management |

---

## Supported Boards

| Board | Status | Ethernet | Display | Notes |
|-------|--------|----------|---------|-------|
| SZ3568-V1.2 | Fully working | RGMII (MAXIO PHY) | HDMI + LVDS | Primary development board |
| DC-A568-V06 | Legacy | RMII | HDMI | Buildroot-based, deprecated |

### Building for Specific Boards

```bash
# SZ3568 board (default)
./scripts/build.sh sz3568-v1.2

# DC-A568 board
./scripts/build.sh dc-a568-v06
```

### Rootfs Profiles

```bash
./scripts/build/rootfs.sh sz3568-v1.2 build                    # Minimal (default)
./scripts/build/rootfs.sh --profile full sz3568-v1.2 build     # Full desktop + dev tools
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [HOW-TO-BUILD.md](HOW-TO-BUILD.md) | Build instructions and commands |
| [docs/adr/](docs/adr/) | Architecture Decision Records |
| [CLAUDE.md](CLAUDE.md) | Technical context and debugging |
| [boards/](boards/) | Board configurations |

### Architecture Decisions

This project uses ADR (Architecture Decision Records) to document significant technical choices. See [docs/adr/README.md](docs/adr/README.md) for the full index.

Current architectural state:

| Decision | Choice | ADR |
|----------|--------|-----|
| Build System | Debian 12 + Docker | ADR-0002 |
| Bootloader | Mainline U-Boot | ADR-0003 |
| GPU Driver | Panfrost (open-source) | ADR-0004 |
| Kernel | Mainline 6.12 | ADR-0005 |
| Desktop | Wayland + sway | ADR-0006 |

---

## Build System Features

The build system provides:

- **Docker-based builds** for reproducibility across host environments
- **Incremental builds** that only rebuild changed components
- **Kernel config fragments** for easy customization
- **Custom device trees** with full hardware support per board
- **Package profiles** for minimal or full rootfs configurations
- **APT caching** for faster rebuilds

### Build Times

| Component | Approximate Time |
|-----------|------------------|
| Kernel | 15 minutes |
| Rootfs | 20 minutes |
| Image assembly | 5 minutes |
| **Total** | **30-45 minutes** |

---

## Technical Details

### Mainline U-Boot

Using mainline U-Boot from denx.de rather than the Rockchip fork provides:

- Better community support and documentation
- Clean integration with mainline kernel
- Standard boot flow that works with both SD card and eMMC

### Panfrost GPU Driver

The open-source Panfrost driver (via Mesa) replaced the proprietary Mali blob to enable:

- Desktop OpenGL 3.1 (not just OpenGL ES)
- Hardware-accelerated Wayland compositing
- WebGL in Firefox and Chromium
- Standard Mesa/DRI stack compatibility

### Mainline Kernel 6.12

After experimenting with Rockchip BSP kernels, mainline 6.12 was selected for:

- Best Panfrost GPU support
- Clean device tree integration
- Active community development
- Long-term maintainability

Custom patches include:
- DMA reset timeout fix for MAXIO PHY
- Native LVDS controller driver for RK3568
- Inno video PHY driver for LVDS
- PLL mode switching fix for HDMI clock initialization
- HDMI mode validation fix for RK3568

### Wayland Desktop

The switch from X11/XFCE to Wayland/sway provides:

- Lower latency display
- Better Panfrost integration
- Reduced resource usage
- Modern display protocol support

---

## Using the Desktop

After booting, login at the console and start the graphical environment:

```bash
sway
```

### Sway Keybindings

| Key | Action |
|-----|--------|
| `Super+Enter` | Open terminal |
| `Super+D` | Application menu (dmenu) |
| `Super+Shift+Q` | Close window |
| `Super+Shift+C` | Reload config |
| `Super+Shift+E` | Exit sway |
| `Super+F` | Toggle fullscreen |
| `Super+1-4` | Switch workspace |

These keybindings are also shown in the status bar.

---

## Flashing Methods

There are two ways to install to eMMC:

### Method 1: USB OTG Maskrom Mode (flash-emmc.sh)

Use this when you have physical access and can put the board in maskrom mode. This method can recover boards with corrupted bootloaders or unknown firmware (like OEM images).

**Requirements:**
- USB OTG cable connected to the board
- `rkdeveloptool` installed (`apt install rkdeveloptool`)
- Board in maskrom mode

**Entering Maskrom Mode:**
1. Power off the board
2. Hold the RECOVERY button
3. Connect USB OTG cable (or press RESET if already connected)
4. Release RECOVERY button after 2 seconds
5. Verify with `rkdeveloptool ld` (should show "Maskrom" device)

**Flashing Commands:**
```bash
# Show usage help
./scripts/device/flash-emmc.sh

# Flash complete image to eMMC
sudo ./scripts/device/flash-emmc.sh --latest

# Flash just U-Boot (board will boot from SD card)
sudo ./scripts/device/flash-emmc.sh --uboot-only

# Wipe eMMC and flash specific image
sudo ./scripts/device/flash-emmc.sh --wipe /path/to/image.img
```

**Cold Flash Recovery (unknown/OEM firmware):**
```bash
# 1. Put board in maskrom mode (see above)
# 2. Wipe and flash fresh image
sudo ./scripts/device/flash-emmc.sh --wipe --latest

# Or just install U-Boot to boot from SD card
sudo ./scripts/device/flash-emmc.sh --uboot-only
```

### Method 2: On-Device Cloning (setup-emmc)

Use this to update eMMC from a running system booted from SD card. Useful for field updates without USB OTG access.

**Procedure:**
1. Insert SD card with new image (board auto-boots from SD when present)
2. Login and run:
```bash
sudo setup-emmc
```
3. Remove SD card and reboot

This partitions the eMMC, copies the kernel/DTB, and clones the rootfs from SD to eMMC.

---

## System Requirements

**Host system:**

| Requirement | Minimum |
|-------------|---------|
| OS | Linux (Ubuntu/Debian recommended) |
| Docker | Required for builds |
| Disk space | 40GB free |
| RAM | 4GB+ |

---

## Directory Structure

```
rk356x/
├── scripts/
│   ├── build.sh             # Thin orchestrator
│   ├── lib/                 # Shared libraries
│   │   ├── common.sh        # Loads all libs
│   │   ├── ui.sh            # Colors, logging
│   │   ├── board.sh         # Board lookup
│   │   └── artifacts.sh     # Artifact detection
│   ├── build/               # Build scripts
│   │   ├── kernel.sh        # Compile kernel + DTBs
│   │   ├── rootfs.sh        # Create Debian rootfs
│   │   └── uboot.sh         # Compile U-Boot
│   └── device/              # Device scripts
│       ├── assemble.sh      # Create bootable image
│       ├── flash-sd.sh      # Flash to SD card
│       └── flash-emmc.sh    # Flash to eMMC via USB OTG
├── boards/                  # Board configurations
│   ├── sz3568-v1.2/board.conf
│   └── dc-a568-v06/board.conf
├── external/custom/         # Board customizations
│   └── board/rk3568/
│       ├── dts/rockchip/    # Device trees
│       ├── patches/linux/   # Kernel patches
│       ├── rootfs-overlay/  # Files copied to rootfs
│       └── kernel.config    # Kernel config fragment
├── docs/                    # Project documentation
│   └── adr/                 # Architecture decisions
├── rkbin/                   # Vendor blobs (submodule)
└── output/                  # Build artifacts
```

### Build Scripts

| Script | Purpose |
|--------|---------|
| `scripts/build.sh` | Orchestrator: sequences all stages |
| `scripts/build/kernel.sh` | Compile kernel, modules, and DTBs |
| `scripts/build/rootfs.sh` | Create Debian rootfs with packages |
| `scripts/build/uboot.sh` | Compile mainline U-Boot |
| `scripts/device/assemble.sh` | Combine components into bootable image |
| `scripts/device/flash-sd.sh` | Flash image to SD card |
| `scripts/device/flash-emmc.sh` | Flash image to eMMC via maskrom mode |

---

## Contributing

Contributions, bug reports, and improvements are welcome.

Before contributing:

- Ensure builds work in Docker for reproducibility
- Test on actual hardware when possible
- Update documentation for any changes
- Follow conventional commit message format

---

## License

MIT License - See LICENSE file for details.

Hardware-specific blobs and firmware may have different licenses (see rkbin/ submodule).

---

## References

| Resource | Link |
|----------|------|
| Mainline U-Boot | https://source.denx.de/u-boot/u-boot |
| Panfrost Driver | https://docs.mesa3d.org/drivers/panfrost.html |
| Debian 12 | https://www.debian.org/releases/bookworm/ |
| RK3568 Datasheet | https://www.rock-chips.com/ |
