# RK356X Debian Boot & Build System

Automated build system for creating production-ready Debian images for RK356X (RK3566/RK3568) ARM development boards with GitHub Actions CI/CD integration.

## 🚀 Features

- ✅ **Automated Builds** - GitHub Actions for continuous integration
- ✅ **Multi-Board Support** - Rock 3A, Quartz64, NanoPi R5S, and more
- ✅ **Modular Architecture** - Build components independently
- ✅ **Production Ready** - Proper partition layout, bootloader, and rootfs
- ✅ **Customizable** - Easy board configurations and overlays
- ✅ **Well Documented** - Comprehensive guides and inline documentation

## 📋 Supported Boards

| Board | SoC | Manufacturer | Status |
|-------|-----|--------------|--------|
| Rock 3A | RK3568 | Radxa | ✅ Tested |
| Quartz64 Model A | RK3566 | Pine64 | ✅ Tested |
| NanoPi R5S | RK3568 | FriendlyELEC | ✅ Tested |
| Station M2 | RK3566 | Firefly | ⚠️ Untested |
| RK3568 EVB | RK3568 | Generic | ⚠️ Untested |

*More boards can be easily added - see [Adding Boards](#adding-new-boards)*

## 🎯 Quick Start

### Option 1: Use Pre-built Images (Recommended)

Download from [Releases](https://github.com/yourusername/rk356x/releases) and flash:

```bash
# Flash to SD card (Linux/macOS)
xz -d rock-3a-debian-*.img.xz
sudo dd if=rock-3a-debian-*.img of=/dev/sdX bs=4M status=progress
```

Or use [balenaEtcher](https://www.balena.io/etcher/) for all platforms.

### Option 2: Build Yourself

```bash
# Install dependencies (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y gcc-aarch64-linux-gnu build-essential \
    libssl-dev flex bison bc debootstrap qemu-user-static \
    device-tree-compiler u-boot-tools parted git pixz

# Clone and build
git clone https://github.com/yourusername/rk356x.git
cd rk356x
chmod +x scripts/*.sh

# Build complete image for Rock 3A
./scripts/build-uboot.sh rock-3a
sudo ./scripts/build-kernel.sh rock-3a
sudo ./scripts/build-rootfs.sh rock-3a
sudo ./scripts/assemble-image.sh rock-3a
```

Output: `output/rock-3a-debian-YYYYMMDD.img.xz`

## 📖 Documentation

- **[BUILD.md](BUILD.md)** - Complete build system documentation
- **[config/README.md](config/README.md)** - Configuration and customization guide
- **[RK356X-GUIDE.md](RK356X-GUIDE.md)** - Hardware overview and technical details

## 🏗️ Architecture

### Build Components

The build system consists of four independent, modular scripts:

1. **build-uboot.sh** - Compiles U-Boot bootloader with Rockchip binaries
2. **build-kernel.sh** - Builds Linux kernel and device trees
3. **build-rootfs.sh** - Creates Debian base filesystem with debootstrap
4. **assemble-image.sh** - Combines everything into a flashable image

### Image Layout

```
┌─────────────────┬───────────────────────────────┐
│ Offset          │ Content                       │
├─────────────────┼───────────────────────────────┤
│ 0 - 32KB        │ Reserved                      │
│ 32KB - 8MB      │ idbloader (TPL + SPL)         │
│ 8MB - 16MB      │ U-Boot + ATF                  │
│ 16MB - 272MB    │ Boot Partition (ext4)         │
│                 │  ├─ /Image (kernel)           │
│                 │  ├─ /dtbs/ (device trees)     │
│                 │  └─ /extlinux/extlinux.conf   │
│ 272MB - END     │ Root Partition (ext4)         │
│                 │  └─ Debian bookworm           │
└─────────────────┴───────────────────────────────┘
```

## 🔧 GitHub Actions Integration

### Automated Builds

Builds trigger automatically on:
- Push to `main` or `develop`
- Pull requests
- Manual workflow dispatch
- Tagged releases

### Manual Build

1. Go to **Actions** → **Build RK356X Image**
2. Click **Run workflow**
3. Select board and build type
4. Download artifacts when complete

### Creating Releases

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

Automatically creates a GitHub release with built images.

## 🎨 Customization

### Adding New Boards

1. Create board config: `config/boards/myboard.conf`
```bash
BOARD_NAME="My Board"
SOC="RK3568"
UBOOT_DEFCONFIG="myboard-rk3568_defconfig"
DTB_FILE="rk3568-myboard.dtb"
# ... more settings
```

2. Build:
```bash
./scripts/assemble-image.sh myboard
```

See [config/README.md](config/README.md) for details.

### Custom Kernel Configuration

Add kernel options in `config/kernel/myboard.config`:
```
CONFIG_MY_DRIVER=y
CONFIG_ANOTHER_OPTION=m
```

### Custom Rootfs Files

Place files in:
- `config/rootfs-overlay/common/` - All boards
- `config/rootfs-overlay/myboard/` - Board-specific

### Patches

Add patches in:
- `config/patches/kernel/myboard/*.patch`
- `config/patches/u-boot/myboard/*.patch`

## 🔐 Default Credentials

Credentials vary by board:

| Board | Username | Password |
|-------|----------|----------|
| Rock 3A | `rock` | `rock` |
| Quartz64 | `pine64` | `pine64` |
| NanoPi R5S | `pi` | `pi` |
| Others | `debian` | `debian` |

**Root password is the same as user password.**

⚠️ **Change passwords immediately after first boot:**
```bash
passwd
sudo passwd root
```

## 🌐 Network Setup

NetworkManager is pre-configured for easy networking:

### Wired
Automatically configured with DHCP - just plug in.

### Wireless
```bash
nmtui  # Text UI
# Or
nmcli device wifi connect "SSID" password "PASSWORD"
```

### Serial Console
Connect to UART2 (ttyS2) at **1500000 baud**:
```bash
sudo screen /dev/ttyUSB0 1500000
```

## 🐛 Troubleshooting

### Board Won't Boot

1. **Check serial console** - Connect UART to see boot messages
2. **Verify image** - Ensure you downloaded the correct board image
3. **Re-flash** - Try flashing again with different tool
4. **Check SD card** - Test with different SD card

### No Display Output

1. Boot messages appear on serial (ttyS2) first
2. Try connecting HDMI before powering on
3. Some boards need specific DTB - try alternatives in `/boot/dtbs/rockchip/`

### No Network

```bash
# Check interface status
ip addr

# Restart NetworkManager
sudo systemctl restart NetworkManager

# Check DHCP
sudo dhclient eth0
```

See [BUILD.md](BUILD.md) for comprehensive troubleshooting.

## 📊 Build Requirements

### Host System
- Ubuntu 20.04+ or Debian 11+ (recommended)
- Other Linux distros should work with proper dependencies

### Disk Space
- **Build directory**: ~15-20 GB
- **Output image**: 2-8 GB (depending on configuration)

### Build Time
- **U-Boot**: ~5-10 minutes
- **Kernel**: ~20-40 minutes (depending on CPU)
- **Rootfs**: ~10-20 minutes
- **Assembly**: ~5-10 minutes
- **Total**: ~40-80 minutes for full build

GitHub Actions runners typically complete in 60-90 minutes.

## 🤝 Contributing

Contributions welcome! Areas for improvement:

- [ ] Test and verify more board configurations
- [ ] Add support for RK3588 boards
- [ ] Improve mainline kernel support
- [ ] Add more pre-configured images (minimal, desktop, server)
- [ ] Optimize build times
- [ ] Better documentation and examples

Please:
1. Test on real hardware
2. Document changes
3. Follow existing code style
4. Update relevant docs

## 📚 Resources

### Official Documentation
- [Rockchip Linux Wiki](http://opensource.rock-chips.com/wiki_Main_Page)
- [U-Boot Documentation](https://u-boot.readthedocs.io/)
- [Linux Kernel Documentation](https://www.kernel.org/doc/html/latest/)

### Community Resources
- [Armbian](https://www.armbian.com/) - Reference Linux distribution
- [Radxa Wiki](https://wiki.radxa.com/)
- [Pine64 Wiki](https://wiki.pine64.org/)
- [FriendlyELEC Wiki](https://wiki.friendlyelec.com/)

### Development
- [Linux Rockchip Mailing List](http://lists.infradead.org/mailman/listinfo/linux-rockchip)
- [Rockchip GitHub](https://github.com/rockchip-linux)

## 📜 License

This build system is released under MIT License. Individual components have their own licenses:
- **U-Boot**: GPL-2.0+
- **Linux Kernel**: GPL-2.0
- **Debian**: Various (DFSG-compliant)

## 🙏 Acknowledgments

- Rockchip for hardware and SDK support
- Armbian project for reference implementations
- Collabora for mainline kernel enablement
- Board manufacturers (Radxa, Pine64, FriendlyELEC, Firefly)
- Debian project for solid base system

## 💬 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/rk356x/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/rk356x/discussions)
- **IRC**: #rockchip on OFTC
- **Forum**: [Armbian Forum](https://forum.armbian.com/)

---

**Built with ❤️ for the ARM embedded Linux community**
