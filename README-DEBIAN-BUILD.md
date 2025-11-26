# Debian/Ubuntu Build System for RK3568

This build system creates bootable Debian/Ubuntu images for Rockchip RK3568 boards using kernel 6.6 LTS.

## Why Debian Instead of Buildroot?

**Problem with Buildroot:**
- Package version conflicts (e.g., WebKitGTK requires newer GBM APIs than rockchip-mali blob provides)
- Complex dependency resolution
- Time-consuming full rebuilds
- Difficult to update individual packages

**Benefits of Debian approach:**
- ✅ Standard `apt` package manager (no version conflicts)
- ✅ Mali GPU as `.deb` packages (same as OEM firmware)
- ✅ Kernel 6.6 LTS with modern APIs
- ✅ Easy updates: `apt upgrade`
- ✅ Desktop environment installs in minutes, not hours
- ✅ Team alignment: developers prefer `.deb` packages

## Build System Overview

```
┌─────────────────────────────────────────────────────────┐
│ 1. Build Kernel (build-kernel.sh)                      │
│    ├─ Clone Rockchip 6.6 kernel                        │
│    ├─ Copy custom DTBs (rk3568-sz3568.dts, etc.)       │
│    ├─ Apply patches (Maxio PHY, DMA timeout fix)       │
│    ├─ Configure (Mali Bifrost enabled)                 │
│    ├─ Build: Image + DTBs + modules                    │
│    └─ Create: linux-image-*.deb, linux-headers-*.deb   │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│ 2. Build Rootfs (build-debian-rootfs.sh)               │
│    ├─ Download Ubuntu 24.04.3 base                     │
│    ├─ Install XFCE desktop via apt                     │
│    ├─ Install kernel .debs                             │
│    ├─ Install Mali GPU .deb                            │
│    ├─ Install network firmware                         │
│    └─ Create: debian-rootfs.img                        │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│ 3. Assemble Image (assemble-image.sh)                  │
│    ├─ Build U-Boot                                     │
│    ├─ Create partitioned image                         │
│    ├─ Install bootloader                               │
│    ├─ Copy kernel + DTB                                │
│    ├─ Copy rootfs                                      │
│    └─ Create: rk3568-*.img (flashable SD/eMMC image)   │
└─────────────────────────────────────────────────────────┘
```

## Supported Boards

| Board | Config | Ethernet | DTB |
|-------|--------|----------|-----|
| SZ3568-V1.2 | rk3568_sz3568 | RGMII (MAXIO MAE0621A PHY) | rk3568-sz3568.dts |
| DC-A568-V06 | rk3568_custom | RMII | rk3568-dc-a568.dts |

## Quick Start

### Prerequisites

**Option 1: Docker (Recommended - no dependencies needed!)**

```bash
# Just install Docker
sudo apt install docker.io
sudo usermod -aG docker $USER  # Add yourself to docker group
# Log out and back in for group to take effect
```

**Option 2: Native build (if you prefer not to use Docker)**

```bash
# Install build dependencies on host
sudo apt install \
    qemu-user-static debootstrap wget \
    git make gcc g++ bison flex libssl-dev libelf-dev bc kmod debhelper \
    gcc-aarch64-linux-gnu
```

### Build Workflow

#### Option 1: Orchestrator Script (Recommended)

The `build.sh` orchestrator guides you through the build process interactively:

```bash
# Interactive mode (recommended for first-time builds)
./build.sh rk3568_sz3568

# Auto mode: build what's missing, flash to SD card
sudo ./build.sh --auto --device /dev/sdX rk3568_sz3568

# See all options
./build.sh --help
```

**Features:**
- 🔍 Detects existing artifacts (kernel, rootfs, image)
- 📊 Shows artifact properties (size, date, version)
- 🤔 Asks whether to skip or rebuild each stage
- ⚡ Auto mode: builds only what's missing
- 💾 Auto mode: flashes to SD card automatically

#### Option 2: Manual Build Process

Run individual scripts if you need fine-grained control:

```bash
# 1. Build kernel (automatically uses Docker if available)
./scripts/build-kernel.sh rk3568_sz3568

# 2. Build rootfs (automatically uses Docker if available)
./scripts/build-debian-rootfs.sh

# 3. Assemble bootable image (needs sudo for loop devices)
sudo ./scripts/assemble-debian-image.sh rk3568_sz3568

# 4. Flash to SD card
sudo dd if=output/rk3568-debian-*.img of=/dev/sdX bs=4M status=progress conv=fsync
# Or use the compressed .xz file with balenaEtcher
```

**How Docker works:**
- Scripts auto-detect if Docker is available
- First run builds Docker image (one-time, ~2 min)
- Subsequent runs reuse the image (fast!)
- If no Docker, scripts run on host (needs dependencies)
- All build artifacts saved to host filesystem

**Total build time:**
- Kernel build: ~10-15 minutes (first time)
- Rootfs build: ~15-20 minutes (first time)
- Image assembly: ~5-10 minutes
- **Total: ~30-45 minutes** (vs 4-6 hours with Buildroot!)

#### Option 2: Iterative Development

```bash
# Build kernel once
./scripts/build-kernel.sh rk3568_sz3568

# Modify kernel config, DTB, or patches
# Rebuild only kernel
./scripts/build-kernel.sh rk3568_sz3568

# Kernel .debs will be updated in output/kernel-debs/
# Re-run rootfs build to install updated kernel
./scripts/build-debian-rootfs.sh
```

## What Gets Built

### Kernel (6.6 LTS)
- **Source:** https://github.com/rockchip-linux/kernel (develop-6.6 branch)
- **Config:** `rockchip_linux_defconfig` + `external/custom/board/rk3568/kernel.config`
- **DTBs:** Custom device trees from `external/custom/board/rk3568/dts/`
- **Patches:** Applied from `external/custom/patches/linux/`
- **Drivers:**
  - Mali Bifrost GPU (CONFIG_MALI_BIFROST=y)
  - MAXIO MAE0621A PHY (via patch)
  - STMMAC Ethernet
  - RK809 Audio Codec
  - USB, HDMI, WiFi (RTL8723DS)

**Output:** `output/kernel-debs/linux-image-*.deb`, `linux-headers-*.deb`

### Rootfs (Ubuntu 24.04 LTS)
- **Base:** Ubuntu 24.04.3 Noble Numbat
- **Desktop:** XFCE4 + LightDM (auto-login)
- **Browser:** Epiphany (WebKitGTK-based, hardware-accelerated)
- **GPU:** libmali-bifrost-g52-g13p0 (proprietary Mali driver)
- **Network:** NetworkManager + firmware-realtek (for WiFi)
- **Multimedia:** GStreamer with full codec support

**Installed Packages:**
- System: systemd, NetworkManager, openssh-server
- Desktop: xfce4, lightdm, epiphany-browser
- Graphics: libmali-bifrost-g52-g13p0, mesa-utils
- Network: linux-firmware, firmware-realtek, wpasupplicant, iw
- Multimedia: gstreamer1.0-plugins-{base,good,bad,ugly,libav}
- Tools: vim, git, wget, curl, htop, i2c-tools, usbutils

**Users:**
- `root` / `root` (for development)
- `rock` / `rock` (default user, auto-login)

**Output:** `rootfs/debian-rootfs.img`

## Directory Structure

```
rk356x/
├── kernel-6.6/                    # Rockchip 6.6 kernel (cloned during build)
├── external/custom/               # Your customizations
│   ├── board/rk3568/
│   │   ├── dts/rockchip/          # Custom device trees
│   │   ├── kernel.config          # Kernel config fragment
│   │   └── rootfs-overlay/        # Files copied to rootfs (future)
│   └── patches/linux/             # Kernel patches
│       ├── 0001-add-maxio-phy-driver.patch
│       └── 0002-increase-dma-reset-timeout.patch
├── rootfs/                        # Rootfs build artifacts
│   ├── work/                      # Extracted Ubuntu base (build time only)
│   ├── debian-rootfs.img          # Final rootfs image
│   └── mali-pkg/                  # Downloaded Mali .deb
├── output/
│   ├── kernel-debs/               # Built kernel packages
│   │   ├── linux-image-*.deb
│   │   └── linux-headers-*.deb
│   └── rk3568-*.img               # Final flashable images
└── scripts/
    ├── build-kernel.sh            # Kernel build script
    ├── build-debian-rootfs.sh     # Rootfs build script
    └── assemble-image.sh          # Image assembly script
```

## Customization

### Adding Kernel Drivers

1. Add patch to `external/custom/patches/linux/`
2. Update `external/custom/board/rk3568/kernel.config` if needed
3. Rebuild kernel: `./scripts/build-kernel.sh`

### Modifying Device Tree

1. Edit `external/custom/board/rk3568/dts/rockchip/rk3568-*.dts`
2. Rebuild kernel: `./scripts/build-kernel.sh`
3. New DTB will be in `kernel-6.6/arch/arm64/boot/dts/rockchip/`

### Adding Rootfs Packages

Edit `scripts/build-debian-rootfs.sh`, add packages to the `apt-get install` section:

```bash
# Install your packages
apt-get install -y \
    your-package-1 \
    your-package-2
```

Then rebuild rootfs: `./scripts/build-debian-rootfs.sh`

### Adding Rootfs Files

(TODO: Implement rootfs-overlay support)

## Troubleshooting

### Kernel build fails with "missing dependency"
```bash
sudo apt install build-essential gcc-aarch64-linux-gnu \
    libssl-dev libelf-dev bc bison flex debhelper
```

### Rootfs build fails with "qemu-aarch64-static not found"
```bash
sudo apt install qemu-user-static debootstrap
```

### Mali GPU package download fails
The Mali package is downloaded from Kylinos archive. If it fails:
1. Download manually: http://archive.kylinos.cn/kylin/KYLIN-ALL/pool/main/libm/libmali/
2. Place in `rootfs/mali-pkg/` directory
3. Re-run rootfs build

### Network not working on boot
Check:
- Kernel has network drivers enabled (STMMAC, RTL8723DS)
- Firmware packages installed: `dpkg -l | grep firmware`
- NetworkManager running: `systemctl status NetworkManager`

## Kernel 6.6 vs 6.1

**Why 6.6 instead of 6.1?**

| Feature | 6.1 LTS | 6.6 LTS |
|---------|---------|---------|
| Rockchip support | ✅ Stable | ✅ Newer |
| Mali Bifrost | ✅ | ✅ |
| GBM APIs | Older | **Modern** (gbm_bo_map) |
| WebKitGTK compatibility | ⚠️ Needs workaround | ✅ Should work |
| LTS support | Until Dec 2026 | Until Dec 2026 |
| Rockchip updates | Active | **Very Active** |

**Verdict:** 6.6 has newer APIs that should solve the WebKitGTK GBM compatibility issues we hit with Buildroot.

## Comparison to Buildroot

| Aspect | Buildroot | Debian Build System |
|--------|-----------|---------------------|
| Package management | Internal recipes | `apt` packages |
| Desktop install time | 4-6 hours | ~15 minutes |
| Update process | Full rebuild | `apt upgrade` |
| Version conflicts | Common | Rare |
| Mali GPU | rockchip-mali package | libmali .deb |
| Kernel customization | ✅ Full control | ✅ Full control |
| DTB support | ✅ Yes | ✅ Yes |
| Team preference | ⚠️ Complex | ✅ Familiar (.deb) |

## Future Improvements

- [ ] Add rootfs-overlay support for custom files
- [ ] Create SD card flashing script
- [ ] Add eMMC flashing via USB (upgrade_tool)
- [ ] Pre-built kernel .deb packages for faster iteration
- [ ] Docker-based build environment
- [ ] CI/CD pipeline for automated builds

## References

- [Rockchip 6.6 Kernel](https://github.com/rockchip-linux/kernel/tree/develop-6.6)
- [Ubuntu Base Images](https://cdimage.ubuntu.com/ubuntu-base/releases/noble/release/)
- [Radxa Mali GPU Guide](https://docs.radxa.com/en/rock5/rock5c/radxa-os/mali-gpu)
- [Firefly Ubuntu Rootfs Guide](https://wiki.t-firefly.com/en/ROC-RK3568-PC/linux_build_ubuntu_rootfs.html)
- [Kylinos Mali Package Archive](http://archive.kylinos.cn/kylin/KYLIN-ALL/pool/main/libm/libmali/)

## License

Same as the main project.
