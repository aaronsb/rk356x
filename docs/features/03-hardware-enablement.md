# Hardware Enablement Features

**Category:** Hardware Enablement
**Phase:** 2
**Priority:** P0 (Critical Path)
**Dependencies:** Features 1-4 (Foundation & Build Environment)
**Status:** ✅ **COMPLETE** - Generic RK3568 EVB configuration with U-Boot 2024.07

## Overview

These features configure device trees and drivers specific to the target hardware platform, and establish bootloader functionality for SD and eMMC boot paths.

**Implementation:**
- Feature 5: Device tree configured for RK3568 EVB (rk3568-evb1-v10.dtb) - Users can select different DTBs in defconfig
- Feature 6: U-Boot 2024.07 with Rockchip vendor blobs (TPL for DRAM init, BL31 for ARM Trusted Firmware)

---

## Feature 5: Device Tree, Drivers & Hardware Enablement Package

**Status:** ⏸️ Planning
**Estimated Effort:** 5-10 days
**Owner:** TBD

### Description

Prepare and customize the Device Tree Source (DTS) for target hardware, enable and configure required drivers, and validate that all peripherals are recognized and functional.

### Business Value

Proper device tree configuration is essential for hardware to function. This feature enables all platform-specific peripherals and provides the foundation for application development.

### User Stories

#### Story 5.1: Prepare Device Tree for target hardware

**As a** firmware engineer
**I want** to customize the device tree
**So that** all hardware peripherals are correctly configured

**Tasks:**
- [ ] Identify base DTB from vendor (closest to target hardware)
- [ ] Copy base DTS to custom location
- [ ] Review hardware inventory from Feature 2
- [ ] Identify required peripherals and interfaces
- [ ] Create custom DTS overlay or modify base DTS
- [ ] Configure pinmux for all required pins
- [ ] Configure I²C buses and devices
- [ ] Configure SPI buses and devices
- [ ] Configure UART ports (especially for peripherals)
- [ ] Configure USB host/device
- [ ] Configure Ethernet (if used)
- [ ] Configure display interface (MIPI-DSI, LVDS, HDMI, or eDP)
- [ ] Configure audio codec
- [ ] Configure GPIO for buttons, LEDs, sensors
- [ ] Document DTS changes in `docs/device-tree-customization.md`

**Acceptance Criteria:**
- Custom DTS created based on vendor reference
- All required peripherals defined in DTS
- Pinmux configuration complete
- DTS compiles to DTB without errors or warnings
- DTS changes documented
- DTS files in version control

---

#### Story 5.2: Compile DTB and validate on the board

**As a** firmware engineer
**I want** to test the custom device tree
**So that** I can verify hardware is correctly described

**Tasks:**
- [ ] Compile custom DTS to DTB
- [ ] Replace DTB in boot partition
- [ ] Boot system with custom DTB
- [ ] Capture boot log
- [ ] Review dmesg for device tree related errors
- [ ] Verify all expected devices appear in /sys
- [ ] Check I²C buses enumerate correctly (`i2cdetect`)
- [ ] Check SPI buses enumerate correctly
- [ ] Check GPIO pins accessible
- [ ] Document validation procedure

**Acceptance Criteria:**
- DTB compiles without warnings
- Board boots with custom DTB
- No device tree errors in dmesg
- All buses (I²C, SPI, USB) enumerated
- GPIO pins accessible from userspace
- Device tree loading confirmed in boot log

---

#### Story 5.3: Enable and test core drivers

**As a** firmware engineer
**I want** to enable all required kernel drivers
**So that** peripherals are functional

**Tasks:**
- [ ] Enable required drivers in kernel config:
  - [ ] USB drivers (host, device, hubs)
  - [ ] Ethernet drivers (if applicable)
  - [ ] Wi-Fi drivers (if applicable)
  - [ ] I²C drivers
  - [ ] SPI drivers
  - [ ] Display/graphics drivers
  - [ ] Touchscreen driver
  - [ ] Storage drivers (eMMC, SD)
  - [ ] Audio codec drivers
  - [ ] GPIO drivers
  - [ ] PWM drivers (if needed for backlight, etc.)
  - [ ] RTC drivers
  - [ ] Watchdog drivers
- [ ] Rebuild kernel with enabled drivers
- [ ] Test each peripheral:
  - [ ] USB: Detect and mount USB storage
  - [ ] Ethernet: Obtain IP address
  - [ ] Wi-Fi: Scan networks
  - [ ] I²C: Detect devices on bus
  - [ ] SPI: Access SPI devices
  - [ ] Display: Output visible image
  - [ ] Touch: Receive touch events
  - [ ] Storage: Read/write to eMMC and SD
  - [ ] Audio: Play test sound
  - [ ] GPIO: Toggle pins, read inputs
  - [ ] RTC: Read/set time
- [ ] Document driver testing in `docs/driver-validation.md`

**Acceptance Criteria:**
- All required drivers enabled in kernel config
- Kernel rebuilds successfully
- Each listed peripheral tests successfully:
  - USB functional (enumerate devices)
  - Ethernet functional (if present)
  - I²C buses functional
  - SPI functional (if used)
  - Display shows output
  - Touch input works
  - Storage (eMMC, SD) read/write OK
  - Audio output works
  - GPIO read/write works
- Test results documented
- Known issues documented

### Dependencies

**Upstream:**
- Feature 2: Supplier Image Boot (hardware inventory)
- Feature 4: Kernel Build (build environment)

**Downstream:**
- Feature 8: Image Assembly (uses custom DTB)
- Feature 13: Hardware Interface Test Suite (validates drivers)
- Feature 14: Board Bring-Up Procedures (depends on working drivers)

### Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Incorrect pinmux causes hardware damage | Critical | Review pinmux with hardware engineer before testing |
| Missing device tree bindings | High | Check kernel documentation and vendor examples |
| Driver not available for peripheral | High | Identify early, plan driver development or alternate solution |
| Performance issues with drivers | Medium | Profile and optimize, consider vendor vs mainline drivers |
| Conflicts between peripherals | Medium | Review pin assignments and resource allocations |

### Technical Notes

**Device Tree Structure Example:**
```dts
/dts-v1/;
#include "rk3568.dtsi"

/ {
    model = "JVL Platform Device";
    compatible = "jvl,platform-device", "rockchip,rk3568";

    gpio-keys {
        compatible = "gpio-keys";
        status = "okay";

        button-1 {
            label = "User Button 1";
            gpios = <&gpio0 RK_PA0 GPIO_ACTIVE_LOW>;
            linux,code = <KEY_F1>;
        };
    };

    leds {
        compatible = "gpio-leds";

        led-status {
            label = "status";
            gpios = <&gpio0 RK_PB0 GPIO_ACTIVE_HIGH>;
            default-state = "on";
        };
    };
};

&i2c0 {
    status = "okay";
    clock-frequency = <400000>;

    touchscreen@38 {
        compatible = "edt,edt-ft5x06";
        reg = <0x38>;
        interrupt-parent = <&gpio0>;
        interrupts = <RK_PB5 IRQ_TYPE_EDGE_FALLING>;
    };
};

&spi1 {
    status = "okay";
    /* SPI devices here */
};

&uart2 {
    status = "okay";
    /* Peripheral UART configuration */
};
```

**Useful Commands for Driver Validation:**
```bash
# I²C bus scan
i2cdetect -y 0
i2cdetect -y 1

# List USB devices
lsusb -t

# GPIO operations (using sysfs or gpiotools)
gpiodetect
gpioinfo

# Display information
cat /sys/class/drm/card*/status
xrandr  # If X11 running

# Storage devices
lsblk
df -h

# Input devices
evtest /dev/input/event*

# Audio devices
aplay -l
speaker-test

# Network
ip link show
iw dev wlan0 scan  # Wi-Fi

# Kernel modules loaded
lsmod
```

**Common Device Tree Issues:**

1. **Device not appearing:**
   - Check `status = "okay"` in DTS
   - Verify compatible string matches driver
   - Check reg address correct
   - Review dmesg for probe failures

2. **Pinmux conflicts:**
   - Use `pinctrl-names` and `pinctrl-0` correctly
   - Check RK3568 datasheet for valid pin functions
   - Ensure no pin used twice

3. **I²C device not detected:**
   - Verify pull-up resistors on hardware
   - Check I²C address with i2cdetect
   - Verify clock-frequency setting

4. **Interrupt not working:**
   - Check interrupt-parent and interrupts properties
   - Verify IRQ type (edge/level, high/low)
   - Check GPIO configuration for interrupt pin

### Validation Checklist

**Device Tree:**
- [ ] Base DTS identified and copied
- [ ] All peripherals defined in custom DTS
- [ ] Pinmux configured for all pins
- [ ] I²C devices defined
- [ ] SPI devices defined
- [ ] GPIO defined (LEDs, buttons, etc.)
- [ ] Display interface configured
- [ ] Audio configured
- [ ] DTS compiles without errors/warnings
- [ ] Boot successful with custom DTB
- [ ] No DT errors in dmesg

**Drivers:**
- [ ] USB host driver functional
- [ ] USB device driver functional (if used)
- [ ] Ethernet driver functional (if applicable)
- [ ] Wi-Fi driver functional (if applicable)
- [ ] I²C bus drivers loaded
- [ ] SPI bus drivers loaded
- [ ] Display/DRM driver functional
- [ ] Touchscreen driver functional
- [ ] Storage drivers (eMMC, SD) functional
- [ ] Audio codec driver functional
- [ ] GPIO driver functional
- [ ] RTC driver functional
- [ ] Watchdog driver functional
- [ ] All platform-specific peripherals working:
  - [ ] Card reader
  - [ ] Barcode scanner
  - [ ] Printer
  - [ ] Cash acceptor (if present)
  - [ ] Door sensor
  - [ ] Custom peripherals

### Artifacts

- `arch/arm64/boot/dts/rockchip/rk3568-jvl-platform.dts` - Custom device tree
- `docs/device-tree-customization.md` - DTS documentation
- `docs/driver-validation.md` - Driver test results
- `docs/pinmux-configuration.md` - Pin assignment documentation
- `config/kernel-drivers.config` - Driver configuration fragment
- `logs/device-tree-boot.log` - Boot log with custom DTB
- `tests/hardware-validation.sh` - Automated hardware test script

---

## Feature 6: U-Boot Build & Boot Path Configuration

**Status:** ⏸️ Planning
**Estimated Effort:** 3-5 days
**Owner:** TBD

### Description

Build U-Boot bootloader with support for both SD card and eMMC boot paths. Configure boot scripts and environment to support field updates and recovery modes.

### Business Value

Flexible boot configuration enables field updates, recovery mechanisms, and development flexibility. Proper U-Boot configuration is essential for production deployment.

### User Stories

#### Story 6.1: Build U-Boot with SD and eMMC boot support

**As a** firmware engineer
**I want** to build U-Boot for multiple boot sources
**So that** the system can boot from SD or eMMC

**Tasks:**
- [ ] Identify U-Boot sources in BSP
- [ ] Review U-Boot defconfig for target board
- [ ] Configure U-Boot for both SD and eMMC support
- [ ] Enable required U-Boot features:
  - [ ] EXT4 filesystem support
  - [ ] FAT filesystem support
  - [ ] USB support (for recovery)
  - [ ] Ethernet support (for network boot, if needed)
  - [ ] Environment in eMMC
  - [ ] Fastboot or rkdevelop support (for flashing)
- [ ] Build U-Boot and required components:
  - [ ] idbloader.img (TPL + SPL)
  - [ ] u-boot.itb (U-Boot proper + ATF)
- [ ] Document U-Boot build in `docs/uboot-build.md`
- [ ] Create U-Boot build script

**Acceptance Criteria:**
- U-Boot builds successfully
- idbloader.img generated
- u-boot.itb generated
- Build time reasonable (< 5 minutes)
- Build procedure documented
- Build script created

---

#### Story 6.2: Test boot sequence on hardware

**As a** firmware engineer
**I want** to test U-Boot boots from both SD and eMMC
**So that** I can confirm boot path flexibility

**Tasks:**
- [ ] Flash U-Boot to SD card
- [ ] Test SD boot path:
  - [ ] Boot from SD card
  - [ ] Capture U-Boot console output
  - [ ] Verify U-Boot finds kernel on SD
  - [ ] Verify boot to kernel
- [ ] Flash U-Boot to eMMC
- [ ] Test eMMC boot path:
  - [ ] Boot from eMMC
  - [ ] Capture U-Boot console output
  - [ ] Verify U-Boot finds kernel on eMMC
  - [ ] Verify boot to kernel
- [ ] Test boot priority (SD vs eMMC)
- [ ] Configure boot scripts or extlinux.conf
- [ ] Test bootloader update procedure
- [ ] Document boot sequence in `docs/boot-sequence.md`

**Acceptance Criteria:**
- U-Boot boots from SD card successfully
- U-Boot boots from eMMC successfully
- Boot priority configurable (SD first or eMMC first)
- U-Boot finds and loads kernel from both sources
- Boot log stable and clean
- Boot scripts configured correctly
- U-Boot can be updated safely
- Recovery boot mode works (SD fallback)

### Dependencies

**Upstream:**
- Feature 1: BSP Import (provides U-Boot sources)
- Feature 3: Toolchain Installation (build environment)

**Downstream:**
- Feature 8: Image Assembly (uses U-Boot binaries)
- Feature 9: Full SD Update (depends on boot path)
- Feature 10: USB Update (may use U-Boot fastboot)

### Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| U-Boot build failure | High | Start with vendor defconfig unmodified |
| Bricked board (bad U-Boot flash) | Critical | Test on SD first, keep recovery SD card |
| Boot loop | High | Enable U-Boot console access, test incrementally |
| eMMC not accessible from U-Boot | High | Verify eMMC driver enabled in U-Boot config |
| Environment corruption | Medium | Test environment save/load before production |

### Technical Notes

**U-Boot Build Procedure:**
```bash
cd u-boot/
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export BL31=/path/to/rkbin/rk3568_bl31_v*.elf

# Configure
make rk3568_defconfig  # Or board-specific defconfig

# Customize if needed
make menuconfig

# Build
make -j$(nproc)

# Outputs:
# idbloader.img
# u-boot.itb
```

**Flashing U-Boot:**
```bash
# To SD card (/dev/sdX)
sudo dd if=idbloader.img of=/dev/sdX seek=64 conv=notrunc
sudo dd if=u-boot.itb of=/dev/sdX seek=16384 conv=notrunc

# To eMMC (/dev/mmcblk0 - from booted system)
sudo dd if=idbloader.img of=/dev/mmcblk0 seek=64 conv=notrunc
sudo dd if=u-boot.itb of=/dev/mmcblk0 seek=16384 conv=notrunc
```

**Boot Script Example (boot.cmd):**
```
# U-Boot boot script
setenv bootargs "console=ttyS2,1500000 root=/dev/mmcblk0p2 rootwait rw"

# Try eMMC first
if load mmc 0:1 ${kernel_addr_r} /boot/Image; then
    load mmc 0:1 ${fdt_addr_r} /boot/dtbs/rockchip/rk3568-jvl-platform.dtb
    booti ${kernel_addr_r} - ${fdt_addr_r}
fi

# Fallback to SD
if load mmc 1:1 ${kernel_addr_r} /boot/Image; then
    load mmc 1:1 ${fdt_addr_r} /boot/dtbs/rockchip/rk3568-jvl-platform.dtb
    booti ${kernel_addr_r} - ${fdt_addr_r}
fi

echo "Boot failed!"
```

Compile boot script:
```bash
mkimage -C none -A arm64 -T script -d boot.cmd boot.scr
```

**Extlinux Config (Alternative to boot.scr):**
```
# /boot/extlinux/extlinux.conf
default linux
timeout 30

label linux
    kernel /boot/Image
    fdt /boot/dtbs/rockchip/rk3568-jvl-platform.dtb
    append console=ttyS2,1500000 root=/dev/mmcblk0p2 rootwait rw
```

**U-Boot Environment Configuration:**

Key variables to configure:
- `bootcmd` - Default boot command
- `bootdelay` - Delay before auto-boot
- `baudrate` - Serial console baud rate
- `fdtfile` - Device tree file name
- `console` - Kernel console parameter

Save environment:
```
# In U-Boot console
env save
```

**Boot Order Configuration:**

To prioritize SD over eMMC:
```
setenv bootcmd 'run bootcmd_sd; run bootcmd_mmc'
saveenv
```

### Validation Checklist

- [ ] U-Boot sources identified
- [ ] U-Boot defconfig reviewed
- [ ] Required features enabled
- [ ] U-Boot builds successfully
- [ ] idbloader.img generated
- [ ] u-boot.itb generated
- [ ] U-Boot flashed to SD card
- [ ] SD card boot successful
- [ ] U-Boot flashed to eMMC
- [ ] eMMC boot successful
- [ ] Boot script/extlinux configured
- [ ] Kernel loads from both SD and eMMC
- [ ] Boot priority tested
- [ ] U-Boot console accessible
- [ ] Environment save/load tested
- [ ] Recovery mode tested (SD fallback)
- [ ] Boot sequence documented

### Artifacts

- `docs/uboot-build.md` - U-Boot build procedure
- `docs/boot-sequence.md` - Boot flow documentation
- `scripts/build-uboot.sh` - U-Boot build script
- `scripts/flash-uboot.sh` - U-Boot flash script
- `config/boot.cmd` - Boot script source
- `config/extlinux.conf` - Extlinux configuration
- `logs/uboot-build.log` - Build output
- `logs/uboot-sd-boot.log` - SD boot log
- `logs/uboot-emmc-boot.log` - eMMC boot log

---

## Phase Completion Criteria

Hardware Enablement phase is complete when:

- ✅ Device tree customized for target hardware
- ✅ All required peripherals defined in DTS
- ✅ DTB compiles and boots successfully
- ✅ All core drivers enabled and functional
- ✅ Hardware validation tests pass
- ✅ U-Boot builds successfully
- ✅ Boot from SD card works
- ✅ Boot from eMMC works
- ✅ Boot priority configurable
- ✅ Recovery boot mode functional
- ✅ All documentation complete
- ✅ Engineering lead sign-off obtained

## Next Steps

After completing this phase:

1. Proceed to [System Assembly](./04-system-assembly.md) (Features 7-8)
2. Begin rootfs construction
3. Assemble complete firmware image
4. Prepare for update mechanism development
