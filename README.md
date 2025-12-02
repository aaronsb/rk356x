# RK356X Embedded Linux Build System

**Complete build system for RK356X (RK3566/RK3568) boards with Debian/Ubuntu, mainline U-Boot, and open-source GPU drivers.**

This project provides a production-ready Debian-based Linux system for RK356x ARM64 boards, featuring modern components and full desktop support with hardware acceleration.

---

## 🎯 Quick Start

```bash
# Clone with submodules (vendor blobs required)
git clone --recursive https://github.com/aaronsb/rk356x.git
cd rk356x

# Build complete system (kernel + rootfs + image)
./build.sh

# Or build components individually
./scripts/build-kernel.sh          # Kernel 6.6 with custom DTBs
./scripts/build-debian-rootfs.sh   # Ubuntu 24.04 rootfs
./scripts/assemble-debian-image.sh # Create bootable SD card image
```

**Find your image:** `output/rk3568-debian-*.img.xz`

**Flash to SD card:**
```bash
xzcat output/rk3568-debian-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress
```

---

## 📦 What You Get

| Component | Version | Description |
|-----------|---------|-------------|
| **U-Boot** | Mainline (2024.10+) | From denx.de, supports SD card and eMMC boot |
| **Linux Kernel** | 6.6 (Rockchip BSP) | Custom DTBs, MAXIO PHY driver, display support |
| **GPU Driver** | Panfrost (Mesa) | Open-source Mali-G52 driver with desktop OpenGL 3.1 |
| **Root Filesystem** | Ubuntu 24.04 LTS | Debian-based with XFCE desktop and hardware acceleration |
| **Init System** | systemd | Modern init with networking and services |

**Desktop Environment:**
- ✅ XFCE4 with hardware-accelerated rendering
- ✅ LightDM display manager
- ✅ Full GTK3 application support
- ✅ Chromium browser (hardware accelerated)
- ✅ 1920x1080 HDMI output

---

## 🔧 Supported Boards

| Board | Status | Notes |
|-------|--------|-------|
| **SZ3568-V1.2** | ✅ Fully working | RGMII ethernet (MAXIO PHY), Mali-G52 GPU, HDMI 1080p |
| **DC-A568-V06** | ⚠️ Legacy | See `boards/dc-a568-v06/` - Buildroot-based (deprecated) |

**The build system supports multiple boards and profiles:**
```bash
# Build for specific board
./scripts/build-kernel.sh rk3568_sz3568
./scripts/build-kernel.sh rk3568_custom  # DC-A568 board

# Choose rootfs profile
PROFILE=minimal ./scripts/build-debian-rootfs.sh  # Lightweight (default)
PROFILE=full ./scripts/build-debian-rootfs.sh     # Full desktop packages
```

**Adding new boards:**
1. Add device tree to `external/custom/board/rk3568/dts/rockchip/`
2. Add board case to `scripts/build-kernel.sh`
3. Create board-specific config in `boards/your-board/`

See [README-DEBIAN-BUILD.md](README-DEBIAN-BUILD.md) for details on customization.

---

## 📚 Documentation

- **[Debian Build System Guide](README-DEBIAN-BUILD.md)** - Complete build documentation
- **[Project Context](CLAUDE.md)** - Technical details and configuration
- **[Legacy Buildroot System](scripts/legacy/)** - Original build system (deprecated)

---

## 🏗️ Build System Features

- **Docker-based builds** - Reproducible, no host dependencies
- **Incremental builds** - Only rebuild what changed
- **Kernel config fragments** - Easy customization without editing defconfig
- **Custom device trees** - Full hardware support for each board
- **Package profiles** - Minimal or full rootfs configurations
- **APT caching** - Fast rebuilds with package cache

---

## 🚀 Key Technical Highlights

### Mainline U-Boot
Using mainline U-Boot (not Rockchip fork) for better SD card boot support and community maintenance.

### Panfrost GPU Driver
Switched from proprietary Mali blob to open-source Panfrost for desktop OpenGL support. This enables:
- GTK3 desktop applications
- Hardware-accelerated graphics
- Standard Mesa/DRI stack compatibility

### Rockchip Kernel 6.6
Based on Rockchip's BSP kernel with mainline features and custom board support:
- Custom device trees for each board
- MAXIO MAE0621A Gigabit PHY driver
- Display subsystem with HDMI support
- Mali-G52 GPU via Panfrost

### Ubuntu 24.04 Base
Debian/Ubuntu-based rootfs provides:
- Standard package management (apt)
- Long-term support (LTS)
- Large software repository
- Easy desktop environment setup

---

## 🛠️ System Requirements

**Host system:**
- Linux (Ubuntu/Debian recommended)
- Docker (for containerized builds)
- ~40GB free disk space
- 4GB+ RAM

**Build time:** ~30-60 minutes (depending on CPU)

---

## 📝 Quick Build Example

```bash
# Full automated build
./build.sh

# Or step-by-step
./scripts/build-kernel.sh rk3568_sz3568          # ~15 min
./scripts/build-debian-rootfs.sh                 # ~20 min
./scripts/assemble-debian-image.sh rk3568_sz3568 # ~5 min

# Flash to SD card
xzcat output/rk3568-debian-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress
sync
```

**Default credentials:** `rock` / `rock`

---

## 🤝 Contributing

This is a working project for RK356x embedded development. Contributions, bug reports, and improvements are welcome!

**Before contributing:**
- Ensure builds work in Docker (reproducibility)
- Test on actual hardware when possible
- Update documentation for any changes
- Keep commit messages descriptive

---

## 📄 License

MIT License - See LICENSE file for details

Hardware-specific blobs and firmware may have different licenses (see rkbin/ submodule).

---

## 🔗 Useful Links

- [Rockchip Linux Kernel](https://github.com/rockchip-linux/kernel)
- [Mainline U-Boot](https://source.denx.de/u-boot/u-boot)
- [Panfrost Driver](https://docs.mesa3d.org/drivers/panfrost.html)
- [RK3568 Datasheet](https://www.rock-chips.com/uploads/pdf/2022.8.26/192/RK3568%20Brief%20Datasheet.pdf)
