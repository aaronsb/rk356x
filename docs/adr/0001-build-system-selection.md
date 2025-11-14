# ADR-0001: Build System Selection - Buildroot vs Yocto/Debian

**Status:** Accepted

**Date:** 2025-11-14

**Author:** System Architect

**Reviewers:** Engineering Lead

## Context

The JVL RK356X platform requires a Linux-based embedded operating system to run the user platform application on RK3568 hardware. We need to select a build system and base OS approach that balances:

- **Team size**: Small embedded team (2-5 engineers)
- **Maintenance burden**: Limited resources for build system maintenance
- **Image size**: Storage constraints and update bandwidth considerations
- **Boot time**: Fast startup required for user-facing device
- **Security**: Minimal attack surface, easier to patch
- **Reproducibility**: Consistent builds across environments
- **Development velocity**: Quick iteration cycles

Initial implementation used full Debian (bookworm) with debootstrap, resulting in:
- 2-4 GB rootfs
- 30-60 second boot times
- Includes unnecessary components (NTFS, desktop packages, etc.)
- Large update packages
- Complex dependency management

The platform is a purpose-built embedded device, not a general-purpose computer, so a minimal custom Linux distribution is more appropriate than a full desktop-oriented distribution.

## Decision

**We will use Buildroot as the primary build system for the RK356X platform.**

Buildroot will generate a minimal custom Linux distribution with only the components necessary for the user platform application and hardware support.

## Options Considered

### Option 1: Full Debian (Current Approach)

**Description:**
Use standard Debian distribution (bookworm/bullseye) built with debootstrap, as currently implemented in the repository.

**Pros:**
- Familiar to most developers
- Extensive package repository (APT)
- Well-documented
- Easy to add new packages
- Quick initial setup (existing scripts work)

**Cons:**
- Large image size (2-4 GB)
- Slow boot times (30-60s)
- Includes many unnecessary components
- Larger attack surface
- More packages to maintain/patch
- Larger OTA updates
- Not optimized for embedded use

**Cost/Effort:**
- Initial: Low (already implemented)
- Ongoing: High (maintenance, updates, size management)

### Option 2: Minimal Debian

**Description:**
Use debootstrap with `--variant=minbase` and carefully curated package list to reduce Debian footprint.

**Pros:**
- Still Debian-based (familiar)
- Can use APT for packages
- Smaller than full Debian (200-500 MB)
- Moderate learning curve

**Cons:**
- Still larger than necessary
- Boot time only moderately improved
- Requires ongoing discipline to keep minimal
- Package dependencies can pull in unwanted components
- Not purpose-built for embedded

**Cost/Effort:**
- Initial: Medium (refactor existing approach)
- Ongoing: Medium-High (discipline required)

### Option 3: Yocto/OpenEmbedded

**Description:**
Industry-standard meta-build system used by automotive and industrial embedded Linux.

**Pros:**
- Industry standard
- Extremely flexible
- Layer-based architecture
- Professional tooling ecosystem
- CVE tracking built-in
- Used by major companies

**Cons:**
- **Steep learning curve** (weeks to months)
- Complex to debug
- Very long initial builds (4-8 hours)
- Requires dedicated build infrastructure
- **Overkill for small teams**
- Complex layer management
- Maintenance overhead high

**Cost/Effort:**
- Initial: Very High (weeks of learning + setup)
- Ongoing: High (requires Yocto expertise)

### Option 4: Buildroot (Selected)

**Description:**
Purpose-built system for generating embedded Linux systems through simple configuration and compilation from source.

**Pros:**
- **Designed for embedded devices**
- Minimal output (50-200 MB typical)
- Fast boot times (5-15s achievable)
- Simple configuration (single .config file)
- **Moderate learning curve** (days, not weeks)
- Reproducible builds
- Cross-compilation built-in
- Good for small teams
- Active community
- Rockchip BSP support available

**Cons:**
- No package manager at runtime (by design)
- Rebuilds required for package changes
- Less familiar than Debian to most developers
- Smaller package ecosystem than Debian
- Initial build time (30-60 min)

**Cost/Effort:**
- Initial: Medium (1-2 weeks setup and learning)
- Ongoing: Low-Medium (simple config management)

### Option 5: Alpine Linux

**Description:**
Minimal distribution using musl libc and busybox, with APK package manager.

**Pros:**
- Small base (~130 MB)
- Package manager available
- Faster than Debian
- Growing embedded usage

**Cons:**
- musl libc compatibility issues with some software
- Less hardware support than Debian
- Smaller ecosystem
- Still not as minimal as Buildroot
- Less control over exact components

**Cost/Effort:**
- Initial: Medium
- Ongoing: Medium

## Consequences

### Positive

- **Significant size reduction**: 50-200 MB vs 2-4 GB (90%+ reduction)
- **Faster boot times**: 5-15 seconds vs 30-60 seconds (70%+ improvement)
- **Reduced attack surface**: Only components we need are included
- **Easier security maintenance**: Fewer packages to track and patch
- **Smaller OTA updates**: Faster field updates, less bandwidth
- **Better suited for embedded use**: Purpose-built tooling
- **Reproducible builds**: Buildroot emphasizes reproducibility
- **Appropriate for team size**: Manageable for 2-5 person team
- **Cost effective**: No runtime package management reduces complexity

### Negative

- **No runtime package manager**: Cannot `apt install` on device
  - Mitigation: Use partial update mechanism (Feature 11)
  - Updates deployed as built artifacts, not individual packages
- **Learning curve**: Team needs to learn Buildroot basics
  - Mitigation: Good documentation, active community, ~1 week learning
- **Rebuild for changes**: Package changes require rebuild
  - Mitigation: Incremental builds are fast (5-10 min)
  - CI/CD automates this
- **Less familiar**: Most developers know Debian better
  - Mitigation: Buildroot is simpler than it appears
  - menuconfig interface similar to kernel config

### Neutral

- **Build process changes**: Existing scripts need adaptation
  - Scripts become simpler (less debootstrap complexity)
  - CI/CD workflow similar structure
- **Application packaging**: Apps bundled in image vs installed via APT
  - Cleaner separation of OS and application
  - Better version control
- **Development workflow**: Slightly different than Debian development
  - More structured, less ad-hoc changes

## Implementation

### Phase 1: Setup and Validation (Week 1)

1. Download and extract Buildroot stable release
2. Create initial RK3568 defconfig
3. Validate toolchain and basic build
4. Test boot on hardware with minimal config

### Phase 2: Hardware Enablement (Weeks 2-3)

1. Configure U-Boot for RK3568
2. Configure kernel with RK3568 drivers
3. Add device tree
4. Enable required peripherals
5. Test all hardware interfaces

### Phase 3: Application Integration (Week 3-4)

1. Add rootfs overlay for application
2. Configure systemd services
3. Add application dependencies
4. Test application startup
5. Optimize boot time

### Phase 4: Update Mechanism (Week 4-5)

1. Implement image-based updates
2. Create update packages
3. Test update and rollback
4. Integrate with CI/CD

### Deliverables

- `buildroot/configs/rk3568_jvl_defconfig` - Board configuration
- `buildroot/board/jvl/rk3568/` - Board-specific files
- `buildroot/board/jvl/rk3568/rootfs-overlay/` - Application overlay
- Updated CI/CD workflow for Buildroot
- Documentation in docs/features/

## References

- [Buildroot Official Documentation](https://buildroot.org/docs.html)
- [Buildroot Training Materials](https://bootlin.com/doc/training/buildroot/)
- [Feature 1: BSP Import & Validation](../features/01-foundation-validation.md)
- [Rockchip Buildroot Support](https://github.com/rockchip-linux/buildroot)
- [Embedded Linux Size Comparison](https://elinux.org/Toolchains#Size_Comparison)

## Notes

### Migration Path

Existing Debian-based scripts remain in repository as reference:
- `scripts/build-rootfs.sh` - Debian approach (reference)
- `scripts/build-buildroot.sh` - New Buildroot approach (active)

Both approaches documented to help teams evaluate trade-offs for their specific needs.

### Future Considerations

If requirements change (e.g., need for runtime package management, much larger team, automotive certification), we can revisit this decision. Buildroot to Yocto migration is possible but would be a significant effort.

### Team Training

Budget 1 week for team to complete Buildroot training:
- Day 1-2: Buildroot basics, menuconfig
- Day 3: Kernel and U-Boot configuration
- Day 4: Package addition and rootfs overlay
- Day 5: Testing and troubleshooting

Bootlin provides free Buildroot training materials.
