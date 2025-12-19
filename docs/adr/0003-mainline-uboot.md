# ADR-0003: Mainline U-Boot

**Status:** Accepted

**Date:** 2025-12-01

**Deciders:** @aaronsb

**Technical Story:** Commits `0189347` through `1c00dd4`

## Context

RK3568 boards require a bootloader. Two primary options exist:

1. **Rockchip U-Boot fork** - Vendor-maintained, includes proprietary extensions
2. **Mainline U-Boot** - Community-maintained, upstream-first approach

Initial U-Boot work used the Rockchip fork (via Buildroot integration). When transitioning to Debian builds, we needed to make an explicit choice.

## Decision Drivers

- Long-term maintainability over vendor lock-in
- Compatibility with mainline kernel
- Community support and documentation
- Boot reliability and debugging

## Considered Options

### Option 1: Rockchip U-Boot fork

**Description:** Use Rockchip's maintained fork with RK3568-specific patches.

**Pros:**
- Vendor-tested with their hardware
- May include optimizations
- Matches vendor SDK approach

**Cons:**
- Lags behind mainline features
- Vendor-specific patches may conflict with upstream
- Less community documentation
- Ties us to vendor release cycle

### Option 2: Mainline U-Boot (selected)

**Description:** Use upstream U-Boot with standard RK3568 support.

**Pros:**
- Active community development
- Well-documented
- Clean integration with mainline kernel
- Future-proof (upstream-first)
- Easier to debug with community help

**Cons:**
- May lack some vendor-specific features
- Requires testing our specific boards
- Need to integrate Rockchip TPL/ATF blobs separately

## Decision

We use mainline U-Boot (2024.10+) for the bootloader.

Key implementation:
- U-Boot source cloned during build (not stored in git)
- Rockchip blobs (`rkbin/`) provide TPL, ATF components
- Docker-based build for reproducibility
- `manage-uboot` tool for on-board U-Boot management

## Consequences

### Positive

- Clean mainline stack (U-Boot + kernel both upstream)
- Better long-term maintainability
- Strong community support for debugging
- Standard boot flow documentation applies

### Negative

- Must verify each board works with mainline (done for SZ3568)
- Rockchip blobs still required (TPL, ATF) - not fully open

### Neutral

- Build process downloads U-Boot during build
- `rkbin/` submodule provides vendor blobs

## Implementation Notes

Build integration:
```bash
./scripts/build-uboot.sh    # Builds mainline U-Boot
./scripts/assemble-debian-image.sh  # Integrates into image
```

On-board management:
```bash
manage-uboot status         # Check current U-Boot
manage-uboot flash          # Flash new U-Boot to eMMC
```

The U-Boot source is downloaded during build, not stored in git, to keep repository size manageable.

## References

- U-Boot mainline: https://source.denx.de/u-boot/u-boot
- Rockchip blobs: `rkbin/` submodule
- Commit `1c00dd4`: Migration to mainline
