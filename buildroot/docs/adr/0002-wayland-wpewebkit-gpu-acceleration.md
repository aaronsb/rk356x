# ADR-0002: Wayland + WPEWebKit for GPU-Accelerated Web Browser

**Status:** Accepted

**Date:** 2025-11-25

**Author:** System Architect

**Reviewers:** Engineering Team

## Context

The SZ3568-V1.2 board features a Mali-G52 GPU (Bifrost architecture) with hardware acceleration capabilities. We need to provide a web browsing solution that can take full advantage of GPU acceleration for rendering web content.

### Requirements

- **GPU Acceleration**: Must utilize Mali-G52 GPU hardware acceleration
- **Embedded-optimized**: Suitable for embedded Linux platform
- **Mali Bifrost Support**: Compatible with Rockchip Mali Bifrost proprietary driver
- **OpenGL ES**: Works with existing Mesa/EGL libraries
- **Minimal footprint**: Appropriate size for embedded system
- **Maintainability**: Available in Buildroot with reasonable maintenance burden

### Hardware Context

- **GPU**: Mali-G52 (Bifrost r1p0)
- **Driver**: Rockchip Mali Bifrost proprietary driver (CONFIG_MALI_PLATFORM_NAME="rk")
- **Graphics Stack**: Mesa 3D with Panfrost support, EGL/GLES libraries
- **Display**: HDMI output via Rockchip DRM (display-subsystem)

### Constraints

- Mali Bifrost driver **only supports Wayland**, not X11
- Chromium is not available in Buildroot
- Must work with existing Mali kernel driver and Mesa userspace

## Decision

**We will use Wayland with WPEWebKit (cog browser) for GPU-accelerated web browsing.**

This decision prioritizes GPU acceleration performance over X11-based desktop environments like XFCE.

## Options Considered

### Option 1: XFCE + Qt WebEngine (Rejected)

**Description:**
Traditional X11-based XFCE desktop environment with Qt WebEngine browser.

**Pros:**
- Familiar desktop metaphor (windows, menus, taskbar)
- Qt WebEngine supports OpenGL ES 2 acceleration
- Full desktop environment features
- Multiple applications easily manageable

**Cons:**
- **Mali Bifrost driver does not support X11** - would require software rendering
- No GPU acceleration with current driver
- Qt WebEngine is heavy (Chromium-based)
- Larger memory footprint (~300-400 MB for XFCE + Qt)
- X11 overhead unnecessary for single-app kiosk

**Cost/Effort:**
- Initial: Medium (XFCE configuration)
- Performance: Poor (no GPU acceleration)

### Option 2: Wayland + XFCE (XWayland) (Rejected)

**Description:**
Run XFCE on top of Wayland using XWayland compatibility layer.

**Pros:**
- Keeps XFCE desktop environment
- Theoretically allows GPU acceleration via Wayland
- Familiar interface

**Cons:**
- XWayland adds complexity and overhead
- XFCE not designed for Wayland (poor integration)
- Performance overhead from X11→Wayland translation
- Still large footprint
- Not well-tested on embedded ARM

**Cost/Effort:**
- Initial: High (complex configuration, debugging)
- Ongoing: High (compatibility issues)

### Option 3: Wayland + WPEWebKit + cog (Selected)

**Description:**
Minimal Wayland compositor (weston) with WPEWebKit rendering engine and cog browser for kiosk-style operation.

**Pros:**
- **Native Wayland support** - works with Mali Bifrost driver
- **Hardware GPU acceleration** via OpenGL ES
- **Designed for embedded Linux** - optimized for resource-constrained systems
- **Fastest browser option** for ARM embedded platforms
- Minimal footprint (~100-150 MB)
- **Buildroot support** - patches available for Mali Bifrost
- Kiosk mode built-in (single fullscreen app)
- Well-maintained by Igalia

**Cons:**
- No traditional desktop environment
- Single-app focus (kiosk mode)
- Less familiar than XFCE for desktop users
- Wayland ecosystem still maturing

**Cost/Effort:**
- Initial: Low-Medium (straightforward Buildroot config)
- Ongoing: Low (well-supported)
- Performance: Excellent (full GPU acceleration)

### Option 4: Firefox (Rejected)

**Description:**
Mozilla Firefox browser with Mesa GPU acceleration.

**Pros:**
- Full-featured modern browser
- Open source
- Good standards compliance
- Available in Buildroot

**Cons:**
- **Requires OpenGL 3.2+ or GLES 3.0+** (we have GLES 2.0)
- Very heavy for embedded (~500 MB+ footprint)
- ARM64 GPU acceleration has known issues
- Slow startup on embedded systems
- High memory usage (400+ MB)

**Cost/Effort:**
- Initial: Medium
- Performance: Poor (likely software rendering)
- Resource usage: Very High

## Consequences

### Positive

- **Full GPU acceleration**: WPEWebKit utilizes Mali-G52 hardware rendering
- **Best performance**: Fastest browser option for ARM embedded platforms
- **Minimal footprint**: ~100-150 MB vs 300-500 MB for desktop alternatives
- **Fast boot**: Weston compositor starts quickly
- **Lower power consumption**: Hardware acceleration reduces CPU usage
- **Embedded-optimized**: Purpose-built for this use case
- **Kiosk-ready**: Built-in fullscreen/kiosk mode
- **Well-supported**: Active development by Igalia, Buildroot patches available

### Negative

- **No desktop environment**: Single fullscreen application model
  - Mitigation: Appropriate for kiosk/appliance use case
  - Can add minimal window management if needed later
- **Less familiar**: Not traditional desktop metaphor
  - Mitigation: Simpler to use (fewer options to configure)
  - Better for appliance-style devices
- **Wayland-only**: Cannot run X11 applications
  - Mitigation: WPEWebKit provides all needed functionality
  - Wayland is the future direction for Linux graphics

### Neutral

- **Different development workflow**: Testing/debugging differs from X11
- **Compositor choice**: Using weston (reference compositor)
  - Could swap for sway, labwc, or other if needed
- **Application model**: Single-app focus vs multi-window desktop
  - Cleaner separation of concerns
  - Simpler user experience

## Implementation

### Phase 1: Buildroot Configuration (Day 1)

1. Enable Wayland support in kernel config
2. Add weston compositor package
3. Add WPEWebKit and cog packages
4. Configure Mesa for Wayland backend
5. Test basic build

### Phase 2: GPU Integration (Day 2)

1. Verify Mali Bifrost driver Wayland support
2. Configure weston for Mali DRM backend
3. Test compositor with GPU acceleration
4. Verify EGL/GLES functionality

### Phase 3: Browser Setup (Day 3)

1. Configure cog browser
2. Set up auto-login
3. Configure kiosk mode startup
4. Add rootfs overlay scripts
5. Test browser rendering

### Phase 4: Testing & Optimization (Day 4)

1. Test WebGL acceleration
2. Verify video playback
3. Optimize compositor settings
4. Performance benchmarking
5. Memory usage profiling

### Deliverables

- Updated `rk3568_sz3568_defconfig` with Wayland packages
- Weston compositor configuration
- Cog browser startup scripts in rootfs overlay
- Auto-login configuration
- GPU acceleration verification tests
- Documentation update

## References

- [WPEWebKit Hardware Acceleration](https://www.mail-archive.com/webkit-gtk@lists.webkit.org/msg03672.html)
- [Mali Bifrost Buildroot Patches](http://lists.busybox.net/pipermail/buildroot/2021-September/623777.html)
- [Mali Bifrost GPU Guide](https://docs.linuxfactory.or.kr/guides/gpu_bifrost.html)
- [WPEWebKit Documentation](https://wpewebkit.org/)
- [Cog Browser](https://github.com/Igalia/cog)
- [Weston Compositor](https://wayland.freedesktop.org/weston.html)

## Notes

### GPU Acceleration Verification

To verify GPU acceleration is working:
```bash
# Check GPU driver
ls -la /dev/mali0 /dev/dri/renderD128

# Run GPU status script
gpu-status

# Check weston is using DRM backend
weston-info | grep -i drm

# WebGL test in browser
# Navigate to: https://get.webgl.org/
```

### Alternative Compositors

While we're starting with weston (reference implementation), we can swap to:
- **sway**: i3-like tiling compositor (if keyboard/mouse needed)
- **labwc**: Openbox-like stacking compositor
- **cage**: Ultra-minimal kiosk compositor

All support Wayland and Mali DRM.

### Future Desktop Environment

If full desktop environment becomes required:
- **Option 1**: Wayfire + wf-shell (lightweight Wayland desktop)
- **Option 2**: KDE Plasma Wayland (heavier, full-featured)
- **Option 3**: Return to X11 + XFCE (sacrifice GPU acceleration)

Current decision optimizes for GPU performance and embedded use case.

### Comparison to Industry

Similar approach used by:
- Automotive infotainment systems (Qt Wayland + WebEngine)
- Digital signage (WPEWebKit kiosks)
- Smart displays (Wayland compositors)
- Raspberry Pi kiosk solutions

This is industry best practice for embedded web display with GPU acceleration.
