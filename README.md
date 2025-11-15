# RK356X Buildroot Template

**A template repository for building embedded Linux images for RK356X (RK3566/RK3568) boards using Buildroot.**

This project provides a minimal, production-ready starting point for RK356x embedded development. It uses **Buildroot** to create complete bootable images with U-Boot, Linux kernel, and root filesystem.

---

## 🎯 Quick Start

```bash
# Clone with submodules (vendor blobs required)
git clone --recursive https://github.com/aaronsb/rk356x.git
cd rk356x

# Build everything (takes ~15-60 minutes)
./build.sh

# Find your images
ls -lh buildroot/output/images/
```

**That's it!** The build script handles everything: downloading Buildroot, installing dependencies in a Docker container, and compiling the complete image.

---

## 📦 What Gets Built

| Component | Version | Description |
|-----------|---------|-------------|
| **Buildroot** | 2024.08.1 | Build system |
| **U-Boot** | 2024.07 | Bootloader with Rockchip vendor blobs |
| **Linux Kernel** | 6.6.62 LTS | Mainline kernel with ARM64 default config |
| **Init System** | systemd | Modern init with networking |
| **Root Filesystem** | 512MB ext4 | Minimal embedded Linux with essential tools |

**Included Packages:**
- **Networking:** dhcpcd, dropbear (SSH), ethtool, iproute2
- **Hardware:** i2c-tools, pciutils, usbutils
- **Filesystem:** e2fsprogs, dosfstools
- **Utilities:** util-linux, systemd

---

## 🏗️ Build Approach

This template uses **Docker containers** to ensure consistent, reproducible builds that match the GitHub Actions environment exactly.

### Why Docker?

✅ **Consistent** - Same environment locally and in CI
✅ **Fast** - Leverage all your CPU cores (32-core builds in ~15 minutes!)
✅ **Isolated** - No system pollution, no dependency conflicts
✅ **Reproducible** - Builds work identically everywhere

**Important:** The Docker approach matches the GitHub Actions runner environment (Ubuntu 22.04), so successful local builds will work in CI.

---

## 🎨 Board Configuration

### Current Target: RK3568 EVB (Generic)

This template is configured for a **generic RK3568 EVB (Evaluation Board)** using mainline device trees and U-Boot configurations. This provides broad compatibility with RK3568-based boards.

**Configuration:**
- **SoC:** RK3568 (Cortex-A55 quad-core, ARM64)
- **U-Boot defconfig:** `evb-rk3568_defconfig`
- **Kernel defconfig:** ARM64 default (`defconfig`)
- **Device Tree:** `rk3568-evb1-v10.dtb`

### Adapting for Your Board

The RK356x family includes many variants. To customize for your specific board:

1. **Choose a device tree:**
   ```bash
   ls buildroot/output/build/linux-6.6.62/arch/arm64/boot/dts/rockchip/ | grep rk3568
   ```
   Available boards: Rock 3A, NanoPi R5S, Radxa E25, ODROID-M1, BPI-R2 Pro, etc.

2. **Update defconfig:**
   Edit `external/jvl/configs/rk3568_jvl_defconfig`:
   ```
   BR2_LINUX_KERNEL_INTREE_DTS_NAME="rockchip/rk3568-rock-3a"
   ```

3. **Rebuild:**
   ```bash
   ./build.sh
   ```

**Need a different SoC?** RK3566 boards work similarly - just select the appropriate DTB and U-Boot config.

---

## 📋 Requirements

- **Docker** (recommended) or native build dependencies
- **Git** with submodule support
- **~20GB disk space** for build artifacts
- **Internet connection** for downloading Buildroot and source packages

### System Compatibility

- ✅ **Linux** (Ubuntu, Debian, Arch, Fedora, etc.)
- ✅ **macOS** (with Docker Desktop)
- ✅ **Windows** (WSL2 with Docker)

---

## 🔧 Build Options

### Option 1: One-Command Build (Recommended)

```bash
./build.sh
```

This script:
1. Downloads Buildroot if needed
2. Initializes git submodules (vendor blobs)
3. Runs the build in a Docker container
4. Outputs images to `buildroot/output/images/`

### Option 2: Native Build (Advanced)

If you prefer building without Docker:

```bash
# Install dependencies (Ubuntu/Debian)
sudo apt-get install -y build-essential libssl-dev libncurses-dev \
  bc rsync file wget cpio unzip python3 python3-pyelftools git

# Initialize submodules
git submodule update --init --recursive

# Download Buildroot
wget https://buildroot.org/downloads/buildroot-2024.08.1.tar.gz
tar xzf buildroot-2024.08.1.tar.gz
mv buildroot-2024.08.1 buildroot

# Build
cd buildroot
BR2_EXTERNAL=../external/jvl make rk3568_jvl_defconfig
BR2_EXTERNAL=../external/jvl make -j$(nproc)
```

See [docs/dev/BUILD.md](docs/dev/BUILD.md) for detailed native build instructions.

---

## 🚀 GitHub Actions Integration

### Automatic Validation

**Every push to `main` or `develop` triggers config validation** (~2 minutes):
- ✅ Verifies defconfig loads correctly
- ✅ Validates Buildroot configuration
- ❌ Does NOT build full image (saves CI minutes)

### Full Builds

Full builds (~60 minutes) are triggered by:

**Option 1: Create a release**
```bash
./scripts/release.sh patch  # v0.1.0 → v0.1.1
```

**Option 2: Manual workflow dispatch**
```bash
gh workflow run "Build RK356X Image" \
  --field board=rk3568_jvl \
  --field build_type=full-build
```

See [docs/dev/QUICK-REFERENCE.md](docs/dev/QUICK-REFERENCE.md) for workflow details.

---

## 📁 Project Structure

```
rk356x/
├── .github/workflows/       # GitHub Actions CI/CD
│   └── build-image.yml
├── buildroot/               # Buildroot source (gitignored)
├── docs/                    # Documentation
│   ├── dev/                 # Developer guides
│   └── features/            # Feature specifications
├── external/jvl/            # Buildroot external tree
│   └── configs/
│       └── rk3568_jvl_defconfig
├── rkbin/                   # Vendor blobs (submodule)
├── scripts/                 # Build automation
│   └── release.sh
├── build.sh                 # One-command build script
└── README.md                # This file
```

---

## 🛠️ Customization

### Modify Packages

Edit `external/jvl/configs/rk3568_jvl_defconfig` to add/remove packages:

```bash
# Interactive menu
cd buildroot
BR2_EXTERNAL=../external/jvl make menuconfig

# Save changes
BR2_EXTERNAL=../external/jvl make savedefconfig
cp defconfig ../external/jvl/configs/rk3568_jvl_defconfig
```

### Change Kernel Version

Update in `rk3568_jvl_defconfig`:
```
BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="6.6.62"
```

### Adjust Filesystem Size

Current: 512MB. To change:
```
BR2_TARGET_ROOTFS_EXT2_SIZE="1024M"
```

---

## 🔍 Output Artifacts

After a successful build, find these in `buildroot/output/images/`:

| File | Size | Description |
|------|------|-------------|
| `Image` | ~40MB | Linux kernel binary |
| `rk3568-evb1-v10.dtb` | ~58KB | Device tree blob |
| `rootfs.ext4` | 512MB | Root filesystem image |
| `rootfs.tar.gz` | ~31MB | Compressed rootfs archive |
| `u-boot.bin` | ~820KB | U-Boot bootloader |
| `u-boot-spl.bin` | ~121KB | U-Boot SPL |

**These files are ready for flashing to SD card or eMMC.**

---

## 🐛 Troubleshooting

### Missing `rkbin` submodule

**Error:** `Image 'simple-bin' is missing external blobs`

**Fix:**
```bash
git submodule update --init --recursive
```

### Build fails in Docker

**Error:** `you should not run configure as root`

**Fix:** Already handled by `FORCE_UNSAFE_CONFIGURE=1` in build script

### Out of disk space

Buildroot needs ~20GB. Clean old builds:
```bash
rm -rf buildroot/output
```

See [docs/dev/BUILD.md](docs/dev/BUILD.md) for comprehensive troubleshooting.

---

## 📖 Documentation

- **[Quick Reference](docs/dev/QUICK-REFERENCE.md)** - Build cheat sheet
- **[Build Guide](docs/dev/BUILD.md)** - Complete build instructions
- **[GitHub Actions](docs/dev/GITHUB-ACTIONS.md)** - CI/CD workflow details
- **[Feature Docs](docs/README.md)** - Project feature specifications

---

## 🤝 Contributing

This is a template repository - feel free to fork and customize for your needs!

**Contributions welcome:**
- ✨ Board-specific configurations
- 🐛 Bug fixes and improvements
- 📚 Documentation enhancements
- 🧪 Testing on real hardware

---

## 📜 License

MIT License - See [LICENSE](LICENSE)

Individual components have their own licenses:
- **U-Boot:** GPL-2.0+
- **Linux Kernel:** GPL-2.0
- **Buildroot:** GPL-2.0+
- **Vendor blobs (rkbin):** Proprietary (Rockchip)

---

## 🙏 Acknowledgments

- **Buildroot project** for the excellent embedded build system
- **Rockchip** for hardware and binary blobs
- **Mainline kernel developers** for RK356x support
- **U-Boot community** for bootloader support

---

**Ready to build? Just run `./build.sh` and grab a coffee!** ☕
