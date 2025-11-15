# Feature 1 Implementation: BSP Setup with Buildroot

**Related ADR:** [ADR-0001: Build System Selection](../adr/0001-build-system-selection.md)

**Status:** ⏸️ Planning → 🚧 In Progress

**Estimated Effort:** 1-2 weeks

**Owner:** TBD

## Overview

Following ADR-0001, we're implementing Feature 1 (BSP Import & Validation) using Buildroot instead of manual Debian construction. This provides a minimal, reproducible embedded Linux system optimized for the RK3568 platform.

## Implementation Approach

Instead of importing a vendor BSP directly, we'll use Buildroot with Rockchip support to achieve the same goals more efficiently.

---

## Task 1.1: Download and Setup Buildroot

### Objective
Download Buildroot stable release and set up the build environment.

### Steps

```bash
cd /home/aaron/Projects/jvl/rk356x

# Download Buildroot stable release
wget https://buildroot.org/downloads/buildroot-2024.02.3.tar.gz

# Extract
tar xzf buildroot-2024.02.3.tar.gz
mv buildroot-2024.02.3 buildroot

# Create external tree for JVL customizations
mkdir -p external/custom/{board,configs,package}

# Document Buildroot version
cat > buildroot/VERSION.txt << EOF
Buildroot Version: 2024.02.3
Download URL: https://buildroot.org/downloads/buildroot-2024.02.3.tar.gz
SHA256: $(sha256sum buildroot-2024.02.3.tar.gz | cut -d' ' -f1)
Date Downloaded: $(date)
EOF
```

### Validation

- [ ] Buildroot extracted to `buildroot/` directory
- [ ] Version documented in `buildroot/VERSION.txt`
- [ ] External tree created in `external/custom/`
- [ ] `make menuconfig` launches successfully

---

## Task 1.2: Create Initial RK3568 Configuration

### Objective
Create minimal Buildroot defconfig for RK3568 hardware.

### Steps

```bash
cd buildroot

# Start with ARM64 Cortex-A55 base
make qemu_aarch64_virt_defconfig

# Enter menuconfig
make menuconfig
```

### Configuration Settings

**Target options:**
```
Target Architecture: AArch64 (little endian)
Target Architecture Variant: cortex-a55
```

**Build options:**
```
Enable compiler cache: YES
Number of jobs: $(nproc)
```

**Toolchain:**
```
Toolchain type: Buildroot toolchain
Kernel Headers: Linux 5.10.x (matches Rockchip kernel)
C library: glibc
GCC compiler Version: gcc 11.x
```

**System configuration:**
```
System hostname: rk3568-jvl
System banner: JVL RK3568 Platform
Root password: (set to 'root' for development)
Run a getty after boot: YES
  TTY port: ttyS2  (RK3568 serial console)
  Baudrate: 1500000
Init system: systemd
/dev management: udev
```

**Kernel:**
```
Kernel: Linux
Kernel version: Custom Git repository
  URL: https://github.com/rockchip-linux/kernel.git
  Branch: stable-5.10-rk3568
Kernel configuration: Using a custom config file
  Path: ../external/custom/board/rk3568/linux.config
Device Tree Source: In-tree Device Tree
  DTB name: rk3568-evb  (will customize later)
```

**Target packages:**

Minimal set:
```
BusyBox: YES
  Networking: YES
  Process utilities: YES
Hardware handling:
  usbutils: YES
  pciutils: YES
  i2c-tools: YES
Networking:
  dropbear (SSH): YES
  dhcpcd: YES
System tools:
  htop: YES
  util-linux: YES
```

### Save Configuration

```bash
# Save as defconfig
make savedefconfig BR2_DEFCONFIG=../external/custom/configs/rk3568_custom_defconfig

# Copy to external tree
cp .config ../external/custom/configs/rk3568_jvl.config
```

### Validation

- [ ] Configuration saved to `external/custom/configs/rk3568_custom_defconfig`
- [ ] Settings match requirements above
- [ ] Configuration loads: `make rk3568_custom_defconfig BR2_EXTERNAL=../external/custom`

---

## Task 1.3: Set Up U-Boot in Buildroot

### Objective
Configure U-Boot bootloader for RK3568.

### Configuration

In `make menuconfig`:

**Bootloaders:**
```
U-Boot: YES
U-Boot Version: Custom Git repository
  URL: https://github.com/rockchip-linux/u-boot.git
  Branch: stable-4.19-rk3568
Build system: Kconfig
Board defconfig: rk3568_defconfig
U-Boot needs: OpenSSL
```

### U-Boot Additional Files

Create `external/custom/board/rk3568/uboot.config`:
```makefile
# Additional U-Boot config options
CONFIG_BOOTDELAY=1
CONFIG_USE_BOOTCOMMAND=y
CONFIG_BOOTCOMMAND="run distro_bootcmd"
```

### Rockchip Binary Blobs

Create `external/custom/board/rk3568/post-build.sh`:
```bash
#!/bin/bash
# Fetch rkbin for BL31 and TPL
RKBIN_DIR="${BUILD_DIR}/rkbin"

if [ ! -d "${RKBIN_DIR}" ]; then
    git clone https://github.com/rockchip-linux/rkbin.git "${RKBIN_DIR}"
fi

# Copy BL31 for U-Boot build
cp "${RKBIN_DIR}/bin/rk35/rk3568_bl31_v1.44.elf" "${BINARIES_DIR}/"
cp "${RKBIN_DIR}/bin/rk35/rk3568_ddr_1560MHz_v1.18.bin" "${BINARIES_DIR}/"
```

Make executable:
```bash
chmod +x external/custom/board/rk3568/post-build.sh
```

### Validation

- [ ] U-Boot configured for RK3568
- [ ] Post-build script created
- [ ] rkbin clone specified

---

## Task 1.4: Perform First Build

### Objective
Execute first Buildroot build to validate configuration.

### Build Commands

```bash
cd buildroot

# Set external tree
export BR2_EXTERNAL=../external/custom

# Load our config
make rk3568_custom_defconfig

# Build (this will take 30-60 minutes first time)
make -j$(nproc)
```

### Monitor Build

```bash
# In another terminal, watch progress
watch -n 5 'tail -20 build/build-time.log'
```

### Expected Outputs

After successful build, check `output/images/`:
```bash
ls -lh output/images/

# Should contain:
# - Image (kernel)
# - rootfs.tar
# - rk3568-evb.dtb (device tree)
# - u-boot.bin, u-boot.itb (if U-Boot configured)
```

### Build Troubleshooting

**If build fails:**

1. **Check build log:**
```bash
tail -100 output/build-time.log
```

2. **Common issues:**
   - Missing host tools: Install with apt
   - Network timeouts: Retry `make`
   - Git clone failures: Check network/firewall

3. **Clean and rebuild:**
```bash
make clean
make -j$(nproc)
```

### Validation

- [ ] Build completes without errors
- [ ] `output/images/Image` exists (kernel)
- [ ] `output/images/rootfs.tar` exists
- [ ] `output/images/*.dtb` exists
- [ ] Build time documented (expect 30-60 min first build)

---

## Task 1.5: Create SD Card Image Script

### Objective
Create script to assemble bootable SD card image.

### Script: `scripts/create-sd-image.sh`

```bash
#!/bin/bash
set -e

BUILDROOT_DIR="buildroot"
OUTPUT_DIR="output"
IMAGE_NAME="rk3568-jvl-$(date +%Y%m%d).img"

echo "Creating SD card image: ${IMAGE_NAME}"

# Create 2GB image
dd if=/dev/zero of="${OUTPUT_DIR}/${IMAGE_NAME}" bs=1M count=2048

# Create partition table
parted -s "${OUTPUT_DIR}/${IMAGE_NAME}" mklabel gpt
parted -s "${OUTPUT_DIR}/${IMAGE_NAME}" mkpart primary ext4 32768s 100%

# Flash U-Boot
dd if="${BUILDROOT_DIR}/output/images/idbloader.img" \
   of="${OUTPUT_DIR}/${IMAGE_NAME}" seek=64 conv=notrunc

dd if="${BUILDROOT_DIR}/output/images/u-boot.itb" \
   of="${OUTPUT_DIR}/${IMAGE_NAME}" seek=16384 conv=notrunc

# Mount and extract rootfs
LOOP_DEV=$(sudo losetup -f --show -P "${OUTPUT_DIR}/${IMAGE_NAME}")
sudo mkfs.ext4 "${LOOP_DEV}p1"
sudo mount "${LOOP_DEV}p1" /mnt

sudo tar -xf "${BUILDROOT_DIR}/output/images/rootfs.tar" -C /mnt
sudo cp "${BUILDROOT_DIR}/output/images/Image" /mnt/boot/
sudo cp "${BUILDROOT_DIR}/output/images"/*.dtb /mnt/boot/

# Unmount
sudo umount /mnt
sudo losetup -d "${LOOP_DEV}"

# Compress
pixz "${OUTPUT_DIR}/${IMAGE_NAME}"

echo "Image created: ${OUTPUT_DIR}/${IMAGE_NAME}.xz"
echo "Flash with: sudo dd if=${IMAGE_NAME}.xz of=/dev/sdX bs=4M status=progress"
```

### Validation

- [ ] Script created and executable
- [ ] Image assembles successfully
- [ ] Compressed image created

---

## Task 1.6: Test Boot on Hardware

### Objective
Flash image to SD card and verify boot.

### Steps

1. **Flash to SD card:**
```bash
xz -d output/rk3568-jvl-*.img.xz
sudo dd if=output/rk3568-jvl-*.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

2. **Connect serial console:**
   - Baud: 1500000
   - Port: ttyS2
   ```bash
   sudo screen /dev/ttyUSB0 1500000
   ```

3. **Insert SD and power on**

4. **Observe boot:**
   - U-Boot should start
   - Kernel should load
   - System should boot to login

5. **Login:**
   - Username: root
   - Password: root

6. **Basic validation:**
```bash
# Check kernel version
uname -a

# Check storage
df -h

# Check network interfaces
ip addr

# Check running services
systemctl status
```

### Validation

- [ ] U-Boot starts and loads kernel
- [ ] Kernel boots without critical errors
- [ ] Login prompt appears
- [ ] Root login successful
- [ ] Basic commands work
- [ ] Boot time < 20 seconds
- [ ] Serial console functional at 1500000 baud

---

## Feature 1 Completion Checklist

- [ ] Buildroot downloaded and set up
- [ ] RK3568 defconfig created
- [ ] U-Boot configured
- [ ] Kernel configured
- [ ] First build successful
- [ ] SD image creation script works
- [ ] Hardware boots successfully
- [ ] Serial console accessible
- [ ] Basic system functional
- [ ] Build time documented
- [ ] Configuration committed to git
- [ ] Documentation updated

## Next Steps

Upon completion:
1. Proceed to Feature 5: Device Tree & Hardware Enablement
2. Customize device tree for actual hardware
3. Enable specific peripheral drivers
4. Test all hardware interfaces

## Files Created

```
external/custom/
├── board/rk3568/
│   ├── linux.config
│   ├── uboot.config
│   ├── post-build.sh
│   └── rootfs-overlay/
├── configs/
│   └── rk3568_custom_defconfig
└── Config.in

buildroot/
├── VERSION.txt
└── [buildroot standard structure]

scripts/
└── create-sd-image.sh

docs/
└── buildroot-quickstart.md
```

## Time Estimates

- Task 1.1: Setup Buildroot: 1-2 hours
- Task 1.2: Create configuration: 2-3 hours
- Task 1.3: Configure U-Boot: 1-2 hours
- Task 1.4: First build: 1-2 hours (+ 30-60 min build time)
- Task 1.5: SD image script: 1 hour
- Task 1.6: Hardware testing: 2-3 hours

**Total: 1-2 days for experienced engineer, 3-4 days for learning**

## References

- [Buildroot User Manual](https://buildroot.org/downloads/manual/manual.html)
- [Buildroot Training](https://bootlin.com/doc/training/buildroot/)
- [Rockchip Linux GitHub](https://github.com/rockchip-linux)
- [ADR-0001](../adr/0001-build-system-selection.md)
