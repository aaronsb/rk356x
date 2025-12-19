# ADR-0005: Mainline Kernel Strategy

**Status:** Accepted

**Date:** 2025-12-03

**Deciders:** @aaronsb

**Technical Story:** Commits `71bf593`, `cf58950`, `a88a619`

## Context

RK3568 kernel options range from vendor BSP kernels to fully mainline. Our journey:

1. **Nov 20** - Rockchip 6.1 BSP kernel (vendor patches, MAXIO PHY support)
2. **Dec 2** - Tried 6.1 LTS for "proven Panfrost"
3. **Dec 3** - Moved to 6.12 mainline for better Panfrost and long-term support

The key tension: vendor BSP kernels include board-specific drivers but lag behind mainline features. Mainline kernels have better GPU/display support but may need custom device trees.

## Decision Drivers

- Panfrost GPU driver maturity
- Long-term kernel support (LTS)
- Device tree compatibility
- Reduce vendor dependency
- Community support for debugging

## Considered Options

### Option 1: Rockchip BSP kernel (6.1)

**Description:** Vendor-maintained kernel with RK3568-specific patches.

**Pros:**
- Includes vendor drivers (NPU, ISP, etc.)
- Tested with vendor hardware
- MAXIO PHY driver included

**Cons:**
- Lags behind mainline Panfrost improvements
- Vendor-specific patches complicate debugging
- Tied to vendor release cycle
- May conflict with mainline device trees

### Option 2: LTS kernel (6.1 or 6.6)

**Description:** Use kernel.org LTS releases with custom device tree.

**Pros:**
- Long-term security support
- Stable API
- Balance of features and stability

**Cons:**
- Panfrost improvements lag behind latest mainline
- May still need out-of-tree drivers

### Option 3: Latest mainline (6.12) (selected)

**Description:** Track recent mainline for best Panfrost/DRM support.

**Pros:**
- Latest Panfrost improvements
- Best GPU/display support
- Active community development
- Cleanest device tree integration
- Future-proof

**Cons:**
- Must rewrite device tree for mainline compatibility
- Some vendor drivers unavailable (NPU - disabled anyway)
- More frequent updates needed

## Decision

We use mainline kernel 6.12 with custom device tree for SZ3568.

Key implementation:
- Kernel source downloaded during build (not stored in git)
- Custom device tree (`rk3568-sz3568.dts`) written for mainline
- DMA reset patch for MAXIO PHY timing
- NPU disabled (causes kernel panics, not needed)

## Consequences

### Positive

- Best Panfrost GPU support (desktop OpenGL, WebGL)
- Clean mainline stack (kernel + U-Boot both upstream)
- Active community for debugging
- Device tree follows mainline conventions
- Strong long-term support path

### Negative

- NPU not available (acceptable - not in scope)
- Device tree required manual rewrite for mainline (`fa905ae`)
- Must track mainline for security updates

### Neutral

- Kernel version managed centrally in build config
- Custom patches minimal (DMA reset timeout only)

## Implementation Notes

The kernel version journey reflects learning:

```
6.1 BSP → 6.6 → 6.1 LTS → 6.12 mainline
```

Each step taught us something:
- BSP: Complex vendor patches, hard to debug
- 6.6: DTS compatibility issues
- 6.1 LTS: Panfrost not mature enough
- 6.12: Best balance for desktop GPU use

Device tree rewrite (`fa905ae`) was significant - 556 lines, mainline-compatible, cleanly structured.

Current patches:
- `0002-increase-dma-reset-timeout.patch` - MAXIO PHY requires blocking delay

## References

- Kernel mainline: https://kernel.org
- Commit `a88a619`: Switch to 6.12
- Commit `fa905ae`: Device tree rewrite
- Panfrost requires kernel `CONFIG_DRM_PANFROST=y`
