# Build System Guide

This guide explains how to build RK356X images locally and via GitHub Actions.

## Overview

The build system uses **Buildroot** to create minimal embedded Linux images for RK356X (RK3566/RK3568) processors. Buildroot compiles everything from source: toolchain, kernel, bootloader, and root filesystem.

## Quick Start

### Local Build

```bash
# 1. Download Buildroot (if not already present)
wget https://buildroot.org/downloads/buildroot-2024.02.3.tar.gz
tar xzf buildroot-2024.02.3.tar.gz
mv buildroot-2024.02.3 buildroot

# 2. Load configuration
cd buildroot
BR2_EXTERNAL=../external/jvl make rk3568_jvl_defconfig

# 3. Build (takes ~60 minutes)
BR2_EXTERNAL=../external/jvl make -j$(nproc)

# 4. Find output
ls -lh output/images/
```

### GitHub Actions Build

**Option 1: Manual trigger (for testing)**
```bash
gh workflow run "Build RK356X Image" \
  --field board=rk3568_jvl \
  --field build_type=full-build
```

**Option 2: Create a release (recommended)**
```bash
# Creates v0.1.1 and triggers automatic build
./scripts/release.sh patch
```

## Build Configuration

### What Gets Built

Our defconfig (`external/jvl/configs/rk3568_jvl_defconfig`) includes:

**Architecture:**
- ARM64 Cortex-A55
- glibc toolchain with C++ support

**Kernel:**
- Linux 5.10.160
- Device tree: `rockchip/rk3568-evb1-ddr4-v10.dtb`

**Bootloader:**
- U-Boot 2017.09 with SPL support

**Init System:**
- systemd

**Core Packages:**
- Networking: dhcpcd, dropbear (SSH), ethtool, iproute2
- Hardware tools: i2c-tools, pciutils, usbutils
- Filesystem: e2fsprogs, dosfstools

### Modifying the Configuration

```bash
cd buildroot
BR2_EXTERNAL=../external/jvl make menuconfig

# Save changes back to defconfig
BR2_EXTERNAL=../external/jvl make savedefconfig
cp defconfig ../external/jvl/configs/rk3568_jvl_defconfig
```

## Build Outputs

After a successful build, you'll find in `buildroot/output/images/`:

- `rootfs.tar.gz` - Complete root filesystem
- `Image` - Linux kernel binary
- `rk3568-evb1-ddr4-v10.dtb` - Device tree blob
- `u-boot.bin` - U-Boot bootloader
- `u-boot-spl.bin` - U-Boot SPL (if applicable)

## Build Times

| Component | Time (8 cores) | Time (4 cores) |
|-----------|----------------|----------------|
| Toolchain | ~15 min | ~30 min |
| Kernel | ~10 min | ~20 min |
| U-Boot | ~2 min | ~4 min |
| Packages | ~5 min | ~10 min |
| **Total** | **~35-60 min** | **~70-90 min** |

Times vary based on:
- CPU cores/threads
- Network speed (first build downloads sources)
- Disk I/O performance

## Troubleshooting

### Build Fails with "No rule to make target"

Make sure `BR2_EXTERNAL` is set correctly:
```bash
BR2_EXTERNAL=$PWD/../external/jvl make rk3568_jvl_defconfig
```

### Clean Build

```bash
cd buildroot
make clean  # Clean build artifacts
make distclean  # Complete clean (removes config too)
```

### Download Issues

Downloads are cached in `buildroot/dl/`. If a download fails:
```bash
# Remove the specific package
rm buildroot/dl/packagename-*

# Try build again
BR2_EXTERNAL=../external/jvl make
```

### Out of Disk Space

Buildroot needs ~10GB for a full build. Free space:
```bash
# Remove build output (keeps downloads)
rm -rf buildroot/output

# Remove downloaded sources (will re-download)
rm -rf buildroot/dl
```

## Advanced Topics

### Ccache (Build Acceleration)

Ccache is enabled by default. On subsequent builds, compilation is much faster:
- First build: ~60 min
- Rebuild after small change: ~5-15 min

Cache location: `buildroot/output/host/var/cache/ccache`

### Cross-Compilation

The toolchain is located at `buildroot/output/host/bin/`. To use it:
```bash
export PATH="$PWD/buildroot/output/host/bin:$PATH"
export ARCH=arm64
export CROSS_COMPILE=aarch64-buildroot-linux-gnu-

# Now you can compile ARM64 code
aarch64-buildroot-linux-gnu-gcc myapp.c -o myapp
```

### Custom Packages

See `external/jvl/package/` for adding custom packages to Buildroot.

## See Also

- [GitHub Actions Workflow](GITHUB-ACTIONS.md)
- [Release Process](../RELEASES.md)
- [Buildroot Documentation](https://buildroot.org/downloads/manual/manual.html)
