# ADR-0004: Panfrost Open-Source GPU Driver

**Status:** Accepted

**Date:** 2025-12-02

**Deciders:** @aaronsb

**Technical Story:** Commits `9b08f47` and `4747ef3`

## Context

The RK3568 includes a Mali-G52 GPU (Bifrost architecture). Two driver options exist:

1. **Proprietary Mali blob** - ARM's closed-source userspace driver
2. **Panfrost** - Open-source reverse-engineered driver in Mesa

Initial GPU work (`9b08f47`) used the proprietary Mali driver. This worked for basic acceleration but had issues with desktop OpenGL applications.

## Decision Drivers

- Desktop OpenGL compatibility (Chromium WebGL, desktop compositing)
- Long-term maintainability
- Debian package availability
- Debugging capability

## Considered Options

### Option 1: Proprietary Mali driver

**Description:** ARM's official closed-source driver (libmali).

**Pros:**
- Vendor-supported
- Complete OpenGL ES implementation
- Known to work with vendor kernels

**Cons:**
- Closed source - no debugging possible
- Integration complexity (binary blobs, version matching)
- Poor desktop OpenGL support (designed for embedded ES)
- Requires specific kernel versions
- Not in Debian repos

### Option 2: Panfrost (selected)

**Description:** Open-source Mesa driver for Mali Midgard/Bifrost GPUs.

**Pros:**
- Open source - full debugging capability
- In Debian repos (`mesa` packages)
- Desktop OpenGL support (not just ES)
- Active development, improving rapidly
- Works with mainline kernels
- Chromium WebGL works

**Cons:**
- Not 100% feature-complete vs proprietary
- Performance may be slightly lower in some cases
- Requires kernel DRM/Panfrost driver enabled

## Decision

We use Panfrost (via Mesa) for GPU acceleration.

Key implementation:
- Kernel config enables `CONFIG_DRM_PANFROST`
- Device tree includes GPU OPP table for hardware acceleration
- Debian's mesa packages provide userspace
- Chromium configured with GPU flags for WebGL

## Consequences

### Positive

- Desktop OpenGL works (compositing, WebGL)
- Simple integration via apt packages
- Debuggable when issues arise
- Aligns with mainline kernel strategy
- No binary blob management

### Negative

- Some OpenGL ES edge cases may differ from proprietary
- Performance tuning may be needed (GPU OPP table)

### Neutral

- GPU firmware loaded from `/lib/firmware/`
- Standard Mesa configuration applies

## Implementation Notes

Kernel config:
```
CONFIG_DRM_PANFROST=y
```

Device tree GPU OPP table added in `b2387e5` for proper frequency scaling.

Chromium GPU flags (`/etc/chromium.d/`):
```
--enable-features=VaapiVideoDecoder
--enable-gpu-rasterization
--enable-zero-copy
```

## References

- Panfrost: https://docs.mesa3d.org/drivers/panfrost.html
- Commit `9b08f47`: Initial Mali driver (superseded)
- Commit `4747ef3`: Switch to Panfrost
- Commit `b2387e5`: GPU OPP table for acceleration
