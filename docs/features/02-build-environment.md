# Build Environment Features

**Category:** Build Environment
**Phase:** 1
**Priority:** P0 (Critical Path)
**Dependencies:** Features 1-2 (Foundation)

## Overview

These features establish a consistent and reproducible build environment with locked toolchain versions and validated kernel build configuration.

---

## Feature 3: Toolchain Installation & Version Control

**Status:** ⏸️ Planning
**Estimated Effort:** 2-3 days
**Owner:** TBD

### Description

Install, test, and document the official RK-3568 cross-compilation toolchain. Lock the toolchain version to ensure all developers and CI builds use identical compilers, preventing "works on my machine" issues.

### Business Value

Consistent toolchains eliminate build variability and ensure reproducible builds across all development environments. Version control prevents unexpected breakage from toolchain updates.

### User Stories

#### Story 3.1: Install and test the official RK-3568 toolchain

**As a** firmware engineer
**I want** to install the correct cross-compilation toolchain
**So that** I can build ARM64 code for RK-3568

**Tasks:**
- [ ] Identify recommended toolchain from BSP documentation
- [ ] Document toolchain source (vendor, ARM, Linaro, etc.)
- [ ] Download and verify toolchain (checksums)
- [ ] Install toolchain to standard location
- [ ] Add toolchain to PATH
- [ ] Create test program to verify toolchain
- [ ] Document installation procedure in `docs/toolchain-setup.md`
- [ ] Create automated installation script

**Acceptance Criteria:**
- Toolchain downloads successfully
- Installation completes without errors
- Toolchain binaries executable
- Test program compiles successfully for ARM64
- Test program runs on target hardware
- Installation documented and scriptable

---

#### Story 3.2: Document and lock the toolchain version

**As a** firmware engineer
**I want** to lock the toolchain version
**So that** all developers use the same compiler

**Tasks:**
- [ ] Document exact toolchain version (GCC, binutils, glibc versions)
- [ ] Create toolchain version file (`toolchain-version.txt`)
- [ ] Archive toolchain for internal hosting (if licensing permits)
- [ ] Create Docker image with locked toolchain
- [ ] Update CI/CD to use locked toolchain
- [ ] Document version in all build scripts
- [ ] Create toolchain verification script

**Acceptance Criteria:**
- Toolchain version documented precisely (including commit hash if from git)
- All developers confirm using same version
- CI/CD uses locked toolchain
- Version verification script works
- Docker image available (optional but recommended)
- Toolchain archived or documented for retrieval

### Dependencies

**Upstream:**
- Feature 1: BSP Import & Validation (identifies required toolchain)

**Downstream:**
- Feature 4: Kernel Build (uses toolchain)
- Feature 6: U-Boot Build (uses toolchain)
- Feature 15: Build Reproducibility (depends on locked versions)

### Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Toolchain incompatible with host OS | High | Use Docker container or VM |
| Toolchain produces broken binaries | High | Validate with known-good test on hardware |
| Toolchain no longer available from vendor | Medium | Archive toolchain internally |
| Version drift across developers | Medium | Enforce version check in build scripts |

### Technical Notes

**Common Toolchain Options for RK-3568:**

1. **Vendor Toolchain (Rockchip SDK)**
   - `gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu`
   - Pre-tested with BSP
   - Located in BSP under `prebuilts/gcc/`

2. **Linaro Toolchain**
   - `gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu`
   - Community supported
   - Available from releases.linaro.org

3. **ARM Official Toolchain**
   - `gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu`
   - Latest features
   - From developer.arm.com

4. **Distribution Toolchain**
   - `gcc-aarch64-linux-gnu` (Ubuntu/Debian package)
   - Convenient but version varies by distro
   - May not match vendor testing

**Recommended:** Use vendor toolchain from BSP for initial development.

**Toolchain Test Program:**
```c
// toolchain-test.c
#include <stdio.h>
int main() {
    printf("Hello from ARM64!\\n");
    printf("GCC Version: %s\\n", __VERSION__);
    return 0;
}
```

**Build Test:**
```bash
aarch64-linux-gnu-gcc -o toolchain-test toolchain-test.c
file toolchain-test  # Should show ARM aarch64
# Copy to target and run
```

**Version Capture:**
```bash
aarch64-linux-gnu-gcc --version
aarch64-linux-gnu-ld --version
aarch64-linux-gnu-as --version
```

### Validation Checklist

- [ ] Toolchain source identified and documented
- [ ] Toolchain downloaded and checksum verified
- [ ] Installation procedure documented
- [ ] Toolchain accessible in PATH
- [ ] Test program compiles for ARM64
- [ ] Test program runs on target hardware
- [ ] Exact version documented (GCC, binutils, glibc)
- [ ] All team members using same version
- [ ] CI/CD configured with locked version
- [ ] Version verification script created

### Artifacts

- `docs/toolchain-setup.md` - Installation guide
- `scripts/install-toolchain.sh` - Automated installation
- `scripts/verify-toolchain.sh` - Version verification
- `config/toolchain-version.txt` - Locked version info
- `tests/toolchain-test.c` - Validation test program
- `docker/Dockerfile.toolchain` - Docker image (optional)

---

## Feature 4: Kernel Build Configuration

**Status:** ⏸️ Planning
**Estimated Effort:** 3-5 days
**Owner:** TBD

### Description

Configure and build the Linux kernel for RK-3568 hardware. Validate that the custom-built kernel boots and initializes core hardware correctly.

### Business Value

Building the kernel in-house enables customization for specific hardware requirements, security patches, and performance tuning. Validates the complete build chain before adding custom drivers.

### User Stories

#### Story 4.1: Configure and build the RK-3568 kernel

**As a** firmware engineer
**I want** to build the Linux kernel from source
**So that** I can customize it for our hardware

**Tasks:**
- [ ] Identify kernel sources in BSP (version, patches)
- [ ] Review default kernel configuration (`rockchip_linux_defconfig`)
- [ ] Document any vendor-specific patches
- [ ] Configure kernel build environment
- [ ] Perform clean build of kernel with default config
- [ ] Document build procedure in `docs/kernel-build.md`
- [ ] Capture kernel config to version control
- [ ] Note build time and output artifacts

**Acceptance Criteria:**
- Kernel sources located and documented
- Kernel version identified (e.g., 5.10, 6.1)
- Vendor patches documented
- Clean build completes successfully in reasonable time
- Build outputs include: Image (or zImage), modules, DTBs
- `.config` file saved to version control
- Build procedure documented

---

#### Story 4.2: Test the new kernel on hardware

**As a** firmware engineer
**I want** to boot the custom-built kernel
**So that** I can verify the build is correct

**Tasks:**
- [ ] Replace kernel in boot partition with custom build
- [ ] Ensure DTB matches hardware
- [ ] Boot system with new kernel
- [ ] Capture boot logs via serial console
- [ ] Verify core subsystems initialize (storage, network, USB)
- [ ] Compare boot log with vendor kernel boot log
- [ ] Document any differences or issues
- [ ] Run basic hardware tests

**Acceptance Criteria:**
- Board boots successfully with custom kernel
- Boot completes to login prompt or GUI
- No critical errors in boot log
- Core subsystems initialize:
  - Storage (eMMC, SD) accessible
  - Network interfaces present
  - USB functional
  - I²C/SPI buses detected
  - Display/graphics working
- Boot time similar to vendor kernel
- Kernel version in `uname -r` matches build

### Dependencies

**Upstream:**
- Feature 1: BSP Import & Validation (provides kernel sources)
- Feature 3: Toolchain Installation (provides compiler)

**Downstream:**
- Feature 5: Device Tree & Hardware Enablement (kernel customization)
- Feature 8: Image Assembly (uses kernel output)
- Feature 13: Hardware Interface Test Suite (validates drivers)

### Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Kernel fails to build | High | Start with vendor defconfig unmodified |
| Kernel boots but hardware broken | High | Compare with vendor kernel, review DTB |
| Build takes too long (>1 hour) | Medium | Use `ccache`, optimize `-j` parameter |
| Missing kernel modules | Medium | Verify modules built and installed |
| Kernel version mismatch causes module issues | Low | Rebuild modules after kernel changes |

### Technical Notes

**Typical Kernel Build Procedure:**
```bash
cd kernel/
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export PATH=/path/to/toolchain/bin:$PATH

# Configure
make rockchip_linux_defconfig

# Build (adjust -j based on CPU cores)
make -j$(nproc) Image modules dtbs

# Output locations:
# arch/arm64/boot/Image
# arch/arm64/boot/dts/rockchip/*.dtb
# Various *.ko modules
```

**Key Configuration Options for RK-3568:**
- `CONFIG_ARCH_ROCKCHIP=y`
- `CONFIG_ARM64=y`
- `CONFIG_ROCKCHIP_IOMMU=y`
- `CONFIG_PHY_ROCKCHIP_*=y`
- `CONFIG_DRM_ROCKCHIP=y`
- `CONFIG_ROCKCHIP_VOP2=y` (display)
- `CONFIG_MMC_SDHCI_OF_DWCMSHC=y` (eMMC/SD)
- `CONFIG_DWMAC_ROCKCHIP=y` (Ethernet)

**Common Build Issues:**

1. **Missing headers:**
   ```bash
   sudo apt-get install libssl-dev libncurses-dev flex bison bc
   ```

2. **Toolchain not found:**
   - Verify CROSS_COMPILE and PATH
   - Check toolchain installation

3. **DTB not building:**
   - Enable CONFIG_OF in kernel config
   - Check `arch/arm64/boot/dts/rockchip/Makefile`

**Boot Testing Commands:**
```bash
# After boot, verify kernel
uname -a
cat /proc/version
cat /proc/cmdline

# Check core hardware
lsblk           # Storage
ip link         # Network
lsusb           # USB
dmesg | grep -i error
dmesg | grep -i fail
```

### Validation Checklist

- [ ] Kernel sources identified in BSP
- [ ] Kernel version documented
- [ ] Vendor patches documented
- [ ] Build environment configured
- [ ] Clean build completes successfully
- [ ] Build time documented
- [ ] Kernel Image generated
- [ ] DTB files generated
- [ ] Modules compiled
- [ ] Boot test successful
- [ ] Core hardware initializes
- [ ] Boot log captured and reviewed
- [ ] No critical errors in dmesg
- [ ] Build procedure documented

### Artifacts

- `docs/kernel-build.md` - Build procedure
- `config/kernel.config` - Kernel configuration
- `logs/kernel-build.log` - Build output
- `logs/kernel-boot.log` - Boot log with custom kernel
- `logs/kernel-dmesg.log` - Kernel messages
- `scripts/build-kernel.sh` - Automated build script
- `reference/vendor-kernel-patches.md` - Documentation of vendor patches

---

## Phase Completion Criteria

Build Environment phase is complete when:

- ✅ Toolchain installed and version locked
- ✅ All developers using same toolchain version
- ✅ Toolchain test program runs on hardware
- ✅ Kernel builds successfully from source
- ✅ Custom kernel boots on hardware
- ✅ Core hardware functional with custom kernel
- ✅ Build procedures documented and scripted
- ✅ CI/CD updated to use locked toolchain
- ✅ Engineering lead sign-off obtained

## Next Steps

After completing this phase:

1. Proceed to [Hardware Enablement](./03-hardware-enablement.md) (Features 5-6)
2. Begin device tree customization for specific hardware
3. Add or configure drivers as needed
4. Configure U-Boot for boot path requirements
