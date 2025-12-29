# RK356X Embedded Linux Build System

Complete build system for RK356X (RK3566/RK3568) boards with Debian 12, mainline kernel and U-Boot, and open-source Panfrost GPU drivers.

This project provides a production-ready Debian-based Linux system for RK356x ARM64 boards, featuring a modern Wayland desktop with hardware-accelerated graphics.

---

## Quick Start

```bash
# Clone with submodules (vendor blobs required)
git clone --recursive https://github.com/aaronsb/rk356x.git
cd rk356x

# Build complete system (kernel + rootfs + image)
./build.sh

# Or build components individually
./scripts/build-kernel.sh          # Kernel 6.12 with custom DTBs
./scripts/build-debian-rootfs.sh   # Debian 12 rootfs
./scripts/assemble-debian-image.sh # Create bootable SD card image
```

Output image location: `output/rk3568-debian-*.img.xz`

Flash to SD card:
```bash
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
| Browsers | Firefox ESR, Chromium | Both with WebGL support |
| Init System | systemd | Networking and service management |

---

## Supported Boards

| Board | Status | Ethernet | Display | Notes |
|-------|--------|----------|---------|-------|
| SZ3568-V1.2 | Fully working | RGMII (MAXIO PHY) | HDMI 1080p | Primary development board |
| DC-A568-V06 | Legacy | RMII | HDMI | Buildroot-based, deprecated |

### Building for Specific Boards

```bash
# SZ3568 board (default)
./scripts/build-kernel.sh rk3568_sz3568

# DC-A568 board
./scripts/build-kernel.sh rk3568_custom
```

### Rootfs Profiles

```bash
PROFILE=minimal ./scripts/build-debian-rootfs.sh  # Lightweight (default)
PROFILE=full ./scripts/build-debian-rootfs.sh     # Full desktop + dev tools
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [README-DEBIAN-BUILD.md](README-DEBIAN-BUILD.md) | Complete build system guide |
| [docs/adr/](docs/adr/) | Architecture Decision Records |
| [CLAUDE.md](CLAUDE.md) | Technical context and configuration |
| [boards/](boards/) | Board-specific documentation |

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

Custom patches are minimal (DMA reset timeout for MAXIO PHY only).

### Wayland Desktop

The switch from X11/XFCE to Wayland/sway provides:

- Lower latency display
- Better Panfrost integration
- Reduced resource usage
- Modern display protocol support

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
├── build.sh                 # Main build orchestrator
├── scripts/                 # Build scripts
│   ├── build-kernel.sh
│   ├── build-debian-rootfs.sh
│   ├── build-uboot.sh
│   └── assemble-debian-image.sh
├── external/custom/         # Board customizations
│   └── board/rk3568/
│       ├── dts/rockchip/    # Active device trees
│       └── dts/reference/   # Vendor reference files
├── boards/                  # Board documentation
├── docs/                    # Project documentation
│   └── adr/                 # Architecture decisions
├── rkbin/                   # Vendor blobs (submodule)
└── output/                  # Build artifacts
```

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
