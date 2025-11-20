# RK356X Buildroot Template Documentation

This documentation covers the complete feature set and implementation of the RK356X Buildroot template for embedded Linux development.

## Overview

This template provides a production-ready foundation for building embedded Linux images for RK356X (RK3566/RK3568) boards using Buildroot. It includes the complete build infrastructure, CI/CD automation, and release management - ready for you to customize with your specific hardware and applications in `external/custom/`.

## Documentation Structure

### Feature Categories

1. **Foundation & Validation** ([Features 1-2](./features/01-foundation-validation.md))
   - BSP Import & Validation
   - Supplier Image Boot Verification

2. **Build Environment** ([Features 3-4](./features/02-build-environment.md))
   - Toolchain Installation & Version Control
   - Kernel Build Configuration

3. **Hardware Enablement** ([Features 5-6](./features/03-hardware-enablement.md))
   - Device Tree, Drivers & Hardware Enablement Package
   - U-Boot Build & Boot Path Configuration

4. **System Assembly** ([Features 7-8](./features/04-system-assembly.md))
   - Root File System Construction
   - Image Assembly System

5. **Update Mechanisms** ([Features 9-11](./features/05-update-mechanisms.md))
   - Full SD Update Mechanism
   - USB Update Mechanism
   - Partial Update Engine

6. **Application Integration** ([Features 12-14](./features/06-application-integration.md))
   - User Platform Application Integration
   - Hardware Interface Test Suite
   - Board Bring-Up Test Procedures

7. **Build Infrastructure** ([Features 15-17](./features/07-build-infrastructure.md))
   - Build Reproducibility Framework
   - CI/CD Pipeline Construction
   - Automated Artifact Packaging

8. **Release Management** ([Features 18-19](./features/08-release-management.md))
   - Release Versioning System
   - Technical Documentation Package

### Developer Guides

**Getting Started:**
- [Quick Reference](./dev/QUICK-REFERENCE.md) - ⚡ Start here! Build cheat sheet
- [Build System Guide](./dev/BUILD.md) - Complete local build instructions
- [GitHub Actions Workflow](./dev/GITHUB-ACTIONS.md) - CI/CD deep dive

**Important:**
- 🛡️ **Pushing to main only runs 2-minute config validation** (not full 60-min build)
- 🏗️ **Full builds require manual trigger or release tag**
- 📦 **Use `./scripts/release.sh` to create releases**

See [RELEASES.md](./RELEASES.md) for release management details.

## Quick Reference

### Feature List

**Template Foundation (Provided):**
| # | Feature | Status | Category |
|---|---------|--------|----------|
| 3 | Toolchain Installation & Version Control | ✅ Complete | Build Environment |
| 4 | Kernel Build Configuration | ✅ Complete | Build Environment |
| 5 | Device Tree, Drivers & Hardware Enablement | ✅ Complete | Hardware |
| 6 | U-Boot Build & Boot Path Configuration | ✅ Complete | Hardware |
| 7 | Root File System Construction | ✅ Complete | System |
| 8 | Image Assembly System | ✅ Complete | System |
| 15 | Build Reproducibility Framework | ✅ Complete | Infrastructure |
| 16 | CI/CD Pipeline Construction | ✅ Complete | Infrastructure |
| 17 | Automated Artifact Packaging | ✅ Complete | Infrastructure |
| 18 | Release Versioning System | ✅ Complete | Release |
| 19 | Technical Documentation Package | 🚧 Core docs complete | Release |

**User Implementation (Add to external/custom/):**
| # | Feature | Scope | Category |
|---|---------|-------|----------|
| 1 | BSP Import & Validation | N/A - Using mainline | Foundation |
| 2 | Supplier Image Boot Verification | N/A - Using mainline | Foundation |
| 9 | Full SD Update Mechanism | User-specific | Updates |
| 10 | USB Update Mechanism | User-specific | Updates |
| 11 | Partial Update Engine | User-specific | Updates |
| 12 | Application Integration | User-specific | Application |
| 13 | Hardware Interface Test Suite | Board-specific | Testing |
| 14 | Board Bring-Up Test Procedures | Board-specific | Testing |

## What's Included

### ✅ Production-Ready Build System
- **Buildroot 2024.08.1** with external tree support
- **Linux Kernel 6.6.62 LTS** - Mainline with ARM64 default config
- **U-Boot 2024.07** - Latest bootloader with Rockchip vendor blobs
- **systemd** - Modern init system with networking
- **512MB rootfs** - Essential packages (SSH, networking tools, hardware utils)

### ✅ Docker-Based Reproducible Builds
- Ubuntu 22.04 build environment matching GitHub Actions
- Fast local builds (15-20 min on 32 cores, 60 min on 4 cores)
- Isolated, consistent builds across all platforms

### ✅ Three Build Workflows
1. **Local Build** - Quick iteration (`./scripts/buildroot-build.sh`)
2. **Local + Release** - Build locally, publish to GitHub (`./scripts/local-release.sh`)
3. **Remote Build** - Trigger GitHub Actions (`./scripts/build-remote.sh`)

### ✅ Automated CI/CD Pipeline
- Config validation on every push (2 minutes)
- Full builds on tags and manual triggers
- Artifact packaging and GitHub releases
- 30-day artifact retention

### ✅ Release Management
- Semantic versioning (v1.2.3)
- Automated version bumping
- Release artifact packaging
- GitHub release creation

### 📦 What You Add (external/custom/)
The template is ready for you to customize:
- **Your board-specific device trees**
- **Your applications and services**
- **Board bring-up procedures**
- **Hardware test suites**
- **Update mechanisms** (OTA, USB, SD card)
- **Custom packages and configurations**

## Document Conventions

### Status Indicators
- ⏸️ **Planning** - Feature in planning phase
- 🚧 **In Progress** - Active development
- ✅ **Complete** - Implementation finished
- ✔️ **Validated** - Tested and verified
- ⚠️ **Blocked** - Waiting on dependencies

### Priority Levels
- **P0** - Critical path, blocking other work
- **P1** - High priority, needed soon
- **P2** - Medium priority, planned
- **P3** - Low priority, future enhancement

## Getting Started

### Quick Start
```bash
# Clone with submodules
git clone --recursive https://github.com/aaronsb/rk356x.git
cd rk356x

# Build everything (15-60 minutes)
./scripts/buildroot-build.sh

# Find your images
ls -lh buildroot/output/images/
```

### Customize for Your Board
1. Fork this repository
2. Update device tree in `external/custom/configs/rk3568_custom_defconfig`:
   ```
   BR2_LINUX_KERNEL_INTREE_DTS_NAME="rockchip/rk3568-yourboard"
   ```
3. Add your packages to `external/custom/package/`
4. Add board-specific files to `external/custom/board/`
5. Build and test with `./scripts/buildroot-build.sh`

## Related Documentation

- **[Quick Reference](./dev/QUICK-REFERENCE.md)** - Build cheat sheet and common commands
- **[Build Guide](./dev/BUILD.md)** - Comprehensive build instructions
- **[GitHub Actions](./dev/GITHUB-ACTIONS.md)** - CI/CD workflow documentation
- **[Feature Specifications](./features/)** - Detailed feature documentation

## Terminology

- **BSP** - Board Support Package
- **DTB/DTS** - Device Tree Binary/Source
- **Rootfs** - Root File System
- **eMMC** - Embedded MultiMediaCard (on-board storage)
- **User Platform Application** - Primary application software running on the device
- **Bring-Up** - Initial hardware validation and testing process

## Template Customization

This is a **template repository** designed to be forked and customized:

### What to Customize
1. **Board Configuration**: Update defconfig for your specific RK356X board
2. **Device Trees**: Select or create DTB for your hardware
3. **Packages**: Add your applications in `external/custom/package/`
4. **Rootfs Overlay**: Add custom files in `external/custom/board/rootfs-overlay/`
5. **Build Scripts**: Extend with board-specific post-build scripts
6. **CI/CD**: Adapt workflows for your testing and release process

### External Tree Structure
```
external/custom/
├── configs/
│   └── rk3568_custom_defconfig    # Your board config
├── package/
│   └── myapp/                     # Your applications
├── board/
│   └── mycompany/
│       ├── rootfs-overlay/         # Files copied to rootfs
│       └── post-build.sh          # Post-build scripts
└── patches/
    ├── linux/                     # Kernel patches
    └── uboot/                     # U-Boot patches
```

See [Buildroot External Tree Documentation](https://buildroot.org/downloads/manual/manual.html#outside-br-custom) for complete details.

## Support

- **Issues**: Report bugs at https://github.com/aaronsb/rk356x/issues
- **Documentation**: Check `docs/` for guides and references
- **Buildroot Help**: See https://buildroot.org/support.html
