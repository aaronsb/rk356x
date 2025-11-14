# Foundation & Validation Features

**Category:** Foundation
**Phase:** 1
**Priority:** P0 (Critical Path)
**Dependencies:** None

## Overview

These features establish the foundation for all RK-3568 development by importing and validating the vendor BSP and confirming the supplier reference implementation works correctly.

---

## Feature 1: BSP Import & Validation

**Status:** ⏸️ Planning
**Estimated Effort:** 3-5 days
**Owner:** TBD

### Description

Import the vendor Board Support Package (BSP) into the JVL development environment and validate that it can be built successfully. This provides the foundation for all subsequent customization work.

### Business Value

Without a validated BSP, no custom development can proceed. This feature de-risks the entire project by confirming the vendor-supplied components are complete and functional.

### User Stories

#### Story 1.1: Import the vendor BSP into the JVL environment

**As a** firmware engineer
**I want** to import the complete vendor BSP
**So that** I have a validated starting point for development

**Tasks:**
- [ ] Obtain vendor BSP from supplier (SDK download link, credentials, version)
- [ ] Extract BSP to development environment
- [ ] Verify BSP contents against vendor manifest
- [ ] Document BSP structure and key components
- [ ] Commit BSP to version control (if licensing permits) or document retrieval process
- [ ] Create `docs/bsp-structure.md` documenting layout

**Acceptance Criteria:**
- BSP extracted to known location
- All expected directories present (kernel, u-boot, rootfs, tools, docs)
- BSP structure documented
- Version and source documented

---

#### Story 1.2: Build and validate the default BSP configuration

**As a** firmware engineer
**I want** to build the BSP with default configuration
**So that** I can confirm the toolchain and build environment are correct

**Tasks:**
- [ ] Install BSP build prerequisites
- [ ] Run default BSP build procedure
- [ ] Capture and review build output
- [ ] Flash built image to target hardware
- [ ] Capture boot logs via serial console
- [ ] Document build procedure in `docs/bsp-build-procedure.md`
- [ ] Create reference build script

**Acceptance Criteria:**
- BSP compiles successfully without errors
- Build completes in reasonable time (< 2 hours)
- Board boots using default BSP output
- Serial console accessible and shows boot messages
- BSP build procedure documented
- Reference build script created

### Dependencies

**Upstream:**
- None (this is the starting point)

**Downstream:**
- Feature 2: Supplier Image Boot Verification (uses build output)
- Feature 3: Toolchain Installation (uses BSP toolchain)
- Feature 4: Kernel Build Configuration (uses BSP kernel sources)

### Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| BSP incompatible with dev environment | High | Validate host OS requirements before starting |
| Missing BSP components | High | Verify BSP completeness against vendor docs |
| Build failures due to missing dependencies | Medium | Create docker/VM with clean environment |
| Vendor toolchain incompatible with host | Medium | Document toolchain requirements, consider containerization |

### Technical Notes

**Expected BSP Structure:**
```
vendor-bsp/
├── kernel/           # Linux kernel sources
├── u-boot/          # U-Boot bootloader sources
├── buildroot/       # Root filesystem build system
├── tools/           # Build and flash tools
├── rkbin/           # Rockchip binary blobs
├── docs/            # Vendor documentation
├── build.sh         # Main build script
└── device/rockchip/ # Device-specific configs
```

**Build Environment Requirements:**
- Ubuntu 20.04 or 22.04 (typical vendor requirement)
- 50+ GB free disk space
- 8+ GB RAM
- build-essential, git, python3, etc.

### Validation Checklist

- [ ] BSP sources extracted and inventoried
- [ ] Build prerequisites installed
- [ ] Default build completes successfully
- [ ] Build output includes: kernel Image, DTB, u-boot binaries, rootfs
- [ ] Serial console configured (115200 or 1500000 baud)
- [ ] Boot logs captured and reviewed
- [ ] Documentation completed

### Artifacts

- `docs/bsp-structure.md` - BSP layout documentation
- `docs/bsp-build-procedure.md` - Build instructions
- `scripts/build-bsp-default.sh` - Reference build script
- `logs/bsp-first-build.log` - Initial build log
- `logs/bsp-first-boot.log` - Initial boot log

---

## Feature 2: Supplier Image Boot Verification

**Status:** ⏸️ Planning
**Estimated Effort:** 2-3 days
**Owner:** TBD

### Description

Boot the board using the supplier-provided pre-built reference image and document all working hardware. This establishes a known-good baseline before any customization begins.

### Business Value

Validates that the hardware is functioning correctly and provides a reference point for troubleshooting. Identifies what hardware is expected to work before customization begins.

### User Stories

#### Story 2.1: Boot the board using the supplier reference image

**As a** firmware engineer
**I want** to boot the pre-built supplier image
**So that** I can verify hardware is functional

**Tasks:**
- [ ] Obtain supplier reference image (download link, version)
- [ ] Document image source and version
- [ ] Flash image to SD card or eMMC per vendor instructions
- [ ] Connect serial console
- [ ] Power on board and capture boot sequence
- [ ] Document boot procedure in `docs/supplier-image-boot.md`
- [ ] Take photos/screenshots of boot process

**Acceptance Criteria:**
- Supplier image obtained and version documented
- Image flashes successfully to storage media
- Board boots to login prompt or GUI
- Boot time documented
- No critical errors in boot log
- Login credentials work (if provided)

---

#### Story 2.2: Capture boot logs and document working hardware

**As a** firmware engineer
**I want** to document all working hardware
**So that** I have a baseline for future validation

**Tasks:**
- [ ] Capture complete boot log via serial console
- [ ] Log into system (console or SSH)
- [ ] Run hardware inventory commands (`lsusb`, `lspci`, `lsblk`, `ip addr`, etc.)
- [ ] Test each peripheral (if accessible from reference image)
- [ ] Document kernel version and key drivers
- [ ] Create hardware inventory document
- [ ] Photograph all external connectors and interfaces

**Acceptance Criteria:**
- Complete boot log saved to `logs/supplier-image-boot.log`
- Hardware inventory documented in `docs/hardware-inventory.md`
- Working peripherals identified and listed
- Kernel version and critical drivers documented
- Photos of hardware connectors archived
- Known issues or non-working hardware documented

### Dependencies

**Upstream:**
- Feature 1: BSP Import & Validation (provides context)

**Downstream:**
- Feature 5: Device Tree & Hardware Enablement (uses hardware inventory)
- Feature 13: Hardware Interface Test Suite (uses as reference)
- Feature 14: Board Bring-Up Test Procedures (uses as baseline)

### Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Supplier image fails to boot | High | Contact supplier support, try alternate image version |
| Hardware DOA (dead on arrival) | High | Test with known-good supplier image first |
| Missing login credentials | Medium | Request from supplier or review documentation |
| Incomplete hardware documentation | Low | Best-effort documentation, escalate to supplier |

### Technical Notes

**Common Vendor Image Locations:**
- TFTP/FTP server from supplier
- Google Drive / Dropbox links
- Supplier wiki or download portal
- Included on USB stick with dev kit

**Hardware Enumeration Commands:**
```bash
# Kernel and system info
uname -a
cat /proc/cpuinfo
cat /proc/meminfo

# Storage devices
lsblk
df -h

# USB devices
lsusb -t

# PCI devices
lspci

# Network interfaces
ip addr
ip link

# Loaded kernel modules
lsmod

# Device tree
cat /proc/device-tree/model
cat /proc/device-tree/compatible

# Boot messages
dmesg | less
journalctl -b
```

### Validation Checklist

- [ ] Supplier image source documented
- [ ] Image version recorded
- [ ] Flash procedure documented
- [ ] Boot successful to user interface
- [ ] Serial console logs captured
- [ ] System info captured (uname, cpuinfo, meminfo)
- [ ] Storage devices enumerated
- [ ] Network interfaces identified
- [ ] USB hub and devices tested
- [ ] Display output confirmed (if applicable)
- [ ] Audio output confirmed (if applicable)
- [ ] All connectors photographed and labeled
- [ ] Hardware inventory document completed

### Artifacts

- `docs/supplier-image-boot.md` - Boot procedure
- `docs/hardware-inventory.md` - Complete hardware list
- `logs/supplier-image-boot.log` - Boot log
- `logs/supplier-image-dmesg.log` - Kernel messages
- `logs/supplier-image-hardware.txt` - Hardware enumeration output
- `photos/hardware-connectors/` - Connector photos
- `reference/supplier-image-version.txt` - Image version info

---

## Phase Completion Criteria

Foundation & Validation phase is complete when:

- ✅ Vendor BSP imported and documented
- ✅ BSP builds successfully with default config
- ✅ Supplier reference image boots
- ✅ Hardware inventory completed
- ✅ Boot logs and system info captured
- ✅ All documentation artifacts created
- ✅ Engineering lead sign-off obtained

## Next Steps

After completing this phase:

1. Proceed to [Build Environment](./02-build-environment.md) (Features 3-4)
2. Use hardware inventory to inform device tree configuration
3. Use BSP structure knowledge to plan customization approach
