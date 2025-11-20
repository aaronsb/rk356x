# System Assembly Features

**Category:** System Assembly
**Phase:** 3
**Priority:** P0 (Critical Path)
**Dependencies:** Features 1-6 (Foundation, Build Environment, Hardware)
**Status:** ✅ **COMPLETE** - Buildroot creates complete image assembly

## Overview

These features build the root filesystem and create the complete firmware image assembly pipeline.

**Implementation:**
- Feature 7: 512MB ext4 rootfs with systemd, networking packages (dhcpcd, dropbear SSH, ethtool, iproute2), hardware tools (i2c-tools, pciutils, usbutils)
- Feature 8: Buildroot assembles complete bootable image with kernel (Image), device tree (DTB), rootfs, and U-Boot binaries

---

## Feature 7: Root File System Construction

**Status:** ⏸️ Planning
**Estimated Effort:** 5-7 days
**Owner:** TBD

### Description

Build a minimal Ubuntu/Debian-based root filesystem with required packages and directory structure for the user platform application.

### User Stories

#### Story 7.1: Build minimal Ubuntu/Debian rootfs

**Tasks:**
- [ ] Choose Debian/Ubuntu release (bookworm, jammy, etc.)
- [ ] Set up debootstrap environment
- [ ] Create base rootfs with debootstrap
- [ ] Configure apt sources
- [ ] Install base system packages
- [ ] Configure locales and timezone
- [ ] Set up systemd init
- [ ] Configure network (NetworkManager or systemd-networkd)
- [ ] Set up SSH server
- [ ] Create default user accounts
- [ ] Configure serial console
- [ ] Document rootfs build in `docs/rootfs-build.md`

**Acceptance Criteria:**
- Rootfs builds successfully
- System boots to login prompt
- Network configuration functional
- SSH accessible
- Serial console works
- User accounts created

---

#### Story 7.2: Add required packages and base directory structure

**Tasks:**
- [ ] Install application dependencies:
  - [ ] Database (SQLite, PostgreSQL, etc.)
  - [ ] GUI framework (if using Qt, GTK, etc.)
  - [ ] Networking tools
  - [ ] Development tools (for debugging)
  - [ ] Peripheral access libraries
- [ ] Create application directory structure:
  - [ ] `/opt/platform-app/` - Application binaries
  - [ ] `/etc/platform-app/` - Configuration files
  - [ ] `/var/lib/platform-app/` - Application data
  - [ ] `/var/log/platform-app/` - Log files
- [ ] Configure system services
- [ ] Set up log rotation
- [ ] Configure firewall (if needed)
- [ ] Create rootfs overlay mechanism

**Acceptance Criteria:**
- All required packages installed
- Directory structure created with correct permissions
- System services configured
- Package list documented
- Rootfs tarball created

### Dependencies

**Upstream:**
- Feature 4: Kernel Build (kernel modules to install)
- Feature 5: Device Tree & Hardware Enablement (hardware working)

**Downstream:**
- Feature 8: Image Assembly (uses rootfs)
- Feature 12: Application Integration (installs into rootfs)

### Validation Checklist

- [ ] Debootstrap completes successfully
- [ ] Base system packages installed
- [ ] Systemd functional
- [ ] Network configured
- [ ] SSH server running
- [ ] Application dependencies installed
- [ ] Directory structure created
- [ ] Permissions set correctly
- [ ] Rootfs size acceptable (< 2GB recommended)
- [ ] Rootfs tarball created

### Artifacts

- `docs/rootfs-build.md` - Rootfs build procedure
- `scripts/build-rootfs.sh` - Automated rootfs build
- `config/package-list.txt` - Installed packages
- `config/rootfs-overlay/` - Overlay files
- `output/rootfs.tar.gz` - Rootfs tarball

---

## Feature 8: Image Assembly System

**Status:** ⏸️ Planning
**Estimated Effort:** 3-5 days
**Owner:** TBD

### Description

Create an automated system to assemble U-Boot, kernel, device tree, and rootfs into a complete, flashable firmware image.

### User Stories

#### Story 8.1: Create structure for assembling the full image

**Tasks:**
- [ ] Define partition layout:
  - [ ] Reserved space (0-32KB)
  - [ ] U-Boot idbloader (32KB-8MB)
  - [ ] U-Boot proper (8MB-16MB)
  - [ ] Boot partition (16MB-~256MB, FAT32 or ext4)
  - [ ] Root partition (256MB-end, ext4)
- [ ] Create image creation script
- [ ] Implement partition creation
- [ ] Implement U-Boot installation
- [ ] Implement boot partition population
- [ ] Implement rootfs extraction
- [ ] Add checksum generation
- [ ] Document image layout in `docs/image-layout.md`

**Acceptance Criteria:**
- Partition layout defined and documented
- Script creates image file
- Partitions created correctly
- U-Boot installed at correct offsets
- Boot files installed correctly
- Checksums generated

---

#### Story 8.2: Build and test complete image

**Tasks:**
- [ ] Run image assembly script
- [ ] Verify image structure
- [ ] Flash image to test hardware
- [ ] Capture boot sequence
- [ ] Verify all components load correctly
- [ ] Test system functionality
- [ ] Measure boot time
- [ ] Document image flash procedure
- [ ] Create compressed image for distribution

**Acceptance Criteria:**
- Complete firmware image created
- Image structure validated
- Image boots fully on hardware
- All subsystems functional
- Boot time acceptable
- Assembly process automated
- Flash procedure documented

### Dependencies

**Upstream:**
- Feature 6: U-Boot Build (bootloader binaries)
- Feature 4: Kernel Build (kernel Image and modules)
- Feature 5: Device Tree (DTB files)
- Feature 7: Rootfs Construction (rootfs tarball)

**Downstream:**
- Feature 9: Full SD Update (uses complete image)
- Feature 10: USB Update (uses complete image)
- Feature 16: CI/CD Pipeline (automates assembly)

### Validation Checklist

- [ ] Image creation script functional
- [ ] Partition layout correct
- [ ] U-Boot at correct offsets
- [ ] Boot partition contains kernel and DTB
- [ ] Rootfs extracted correctly
- [ ] Image boots on hardware
- [ ] All hardware functional
- [ ] Boot time measured
- [ ] Compressed image created
- [ ] Checksums generated

### Artifacts

- `docs/image-layout.md` - Image structure documentation
- `docs/flash-procedure.md` - Flashing instructions
- `scripts/assemble-image.sh` - Image assembly script
- `scripts/flash-image.sh` - Flash helper script
- `output/firmware.img` - Complete firmware image
- `output/firmware.img.xz` - Compressed image
- `output/SHA256SUMS` - Checksums

---

## Phase Completion Criteria

System Assembly phase is complete when:

- ✅ Rootfs builds successfully
- ✅ All required packages installed
- ✅ Application directory structure created
- ✅ Image assembly script functional
- ✅ Complete firmware image boots on hardware
- ✅ All hardware subsystems functional
- ✅ Boot time acceptable
- ✅ Flash procedure documented
- ✅ Compressed images available
- ✅ Engineering lead sign-off obtained

## Next Steps

After completing this phase:

1. Proceed to [Update Mechanisms](./05-update-mechanisms.md) (Features 9-11)
2. Implement field update capabilities
3. Test update procedures
4. Prepare for application integration
