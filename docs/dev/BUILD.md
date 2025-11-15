# Build System Guide

This guide explains how to build RK356X images locally and via GitHub Actions.

## Overview

The build system uses **Buildroot** to create minimal embedded Linux images for RK356X (RK3566/RK3568) processors. Buildroot compiles everything from source: toolchain, kernel, bootloader, and root filesystem.

## Prerequisites

Before building, ensure you have:

1. **Git submodules initialized** (for vendor blobs):
   ```bash
   git submodule update --init --recursive
   ```

2. **Docker** (recommended) or native build dependencies

## Quick Start

### Option 1: Docker Build (Recommended)

Docker ensures a consistent build environment matching GitHub Actions:

```bash
# 1. Clone and initialize submodules
git clone https://github.com/aaronsb/rk356x.git
cd rk356x
git submodule update --init --recursive

# 2. Download and extract Buildroot
wget https://buildroot.org/downloads/buildroot-2024.08.1.tar.gz
tar xzf buildroot-2024.08.1.tar.gz
mv buildroot-2024.08.1 buildroot

# 3. Build with Docker (faster, isolated environment)
docker run --rm \
  -v $(pwd):/work \
  -w /work/buildroot \
  ubuntu:22.04 bash -c '\
  apt-get update && \
  apt-get install -y build-essential libssl-dev libncurses-dev \
    bc rsync file wget cpio unzip python3 python3-pyelftools git && \
  BR2_EXTERNAL=../external/custom make rk3568_custom_defconfig && \
  FORCE_UNSAFE_CONFIGURE=1 BR2_EXTERNAL=../external/custom make -j$(nproc)'

# 4. Find output
ls -lh buildroot/output/images/
```

### Option 2: Native Build

```bash
# 1. Install dependencies (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y build-essential libssl-dev libncurses-dev \
  bc rsync file wget cpio unzip python3 python3-pyelftools git

# 2. Download Buildroot
wget https://buildroot.org/downloads/buildroot-2024.08.1.tar.gz
tar xzf buildroot-2024.08.1.tar.gz
mv buildroot-2024.08.1 buildroot

# 3. Load configuration
cd buildroot
BR2_EXTERNAL=../external/custom make rk3568_custom_defconfig

# 4. Build (takes ~15-60 minutes depending on cores)
BR2_EXTERNAL=../external/custom make -j$(nproc)

# 5. Find output
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

Our defconfig (`external/custom/configs/rk3568_custom_defconfig`) includes:

**Architecture:**
- ARM64 Cortex-A55
- glibc toolchain with C++ support
- Buildroot 2024.08.1

**Kernel:**
- Linux 6.6.62 LTS
- Device tree: `rockchip/rk3568-evb1-ddr4-v10.dtb`

**Bootloader:**
- U-Boot 2024.07 (latest) with SPL support
- Vendor blobs from rkbin (TPL for DRAM init, BL31 for ARM Trusted Firmware)

**Init System:**
- systemd

**Core Packages:**
- Networking: dhcpcd, dropbear (SSH), ethtool, iproute2
- Hardware tools: i2c-tools, pciutils, usbutils
- Filesystem: e2fsprogs, dosfstools

### Modifying the Configuration

```bash
cd buildroot
BR2_EXTERNAL=../external/custom make menuconfig

# Save changes back to defconfig
BR2_EXTERNAL=../external/custom make savedefconfig
cp defconfig ../external/custom/configs/rk3568_custom_defconfig
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
BR2_EXTERNAL=$PWD/../external/custom make rk3568_custom_defconfig
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
BR2_EXTERNAL=../external/custom make
```

### Out of Disk Space

Buildroot needs ~10GB for a full build. Free space:
```bash
# Remove build output (keeps downloads)
rm -rf buildroot/output

# Remove downloaded sources (will re-download)
rm -rf buildroot/dl
```

### U-Boot Build Fails: "Missing external blobs"

**Error:**
```
Image 'simple-bin' is missing external blobs and is non-functional: rockchip-tpl atf-bl31
```

**Solution:**
Ensure rkbin submodule is initialized:
```bash
git submodule update --init --recursive
```

### U-Boot Build Fails: "No such file or directory: rk3568_defconfig"

**Error:**
```
cc1: fatal error: ./arch/../configs/rk3568_defconfig: No such file or directory
```

**Cause:**
U-Boot 2024.07 uses `evb-rk3568_defconfig`, not `rk3568_defconfig`.

**Solution:**
The defconfig is already updated to use `BR2_TARGET_UBOOT_BOARD_DEFCONFIG="evb-rk3568"`.

### Docker Build Fails: "you should not run configure as root"

**Error:**
```
configure: error: you should not run configure as root
```

**Solution:**
Add `FORCE_UNSAFE_CONFIGURE=1` to the build command (already included in Docker examples above).

### U-Boot Build Fails: "No module named 'elftools'"

**Error:**
```
binman: Node '/binman/simple-bin/fit': subnode 'images/@atf-SEQ': Failed to read ELF file: Python: No module named 'elftools'
```

**Cause:**
U-Boot's binman tool needs the Python `pyelftools` module to process ELF binaries (like the BL31 blob).

**Solution:**
Install `python3-pyelftools`:
```bash
# Ubuntu/Debian
sudo apt-get install python3-pyelftools

# Or in Docker (already included in examples above)
apt-get install -y python3-pyelftools
```

## Vendor Blobs (rkbin)

RK3568 requires proprietary binary blobs from Rockchip for boot functionality:

**Required Blobs:**
- **TPL (Tiny Program Loader)**: `rk3568_ddr_1560MHz_v1.23.bin` - Initializes DRAM
- **BL31 (ARM Trusted Firmware)**: `rk3568_bl31_v1.45.elf` - Handles secure world operations

**Source:**
The `rkbin` git submodule contains these blobs. They are automatically referenced during U-Boot build via `BR2_TARGET_UBOOT_CUSTOM_MAKEOPTS` in the defconfig.

**Location:**
```
rkbin/bin/rk35/
├── rk3568_ddr_1560MHz_v1.23.bin
├── rk3568_bl31_v1.45.elf
└── rk3568_bl32_v2.15.bin (optional OP-TEE)
```

**Important:** Always initialize git submodules before building:
```bash
git submodule update --init --recursive
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

See `external/custom/package/` for adding custom packages to Buildroot.

## See Also

- [GitHub Actions Workflow](GITHUB-ACTIONS.md)
- [Release Process](../RELEASES.md)
- [Buildroot Documentation](https://buildroot.org/downloads/manual/manual.html)
