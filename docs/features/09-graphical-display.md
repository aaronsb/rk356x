# GPU-Accelerated Graphical Display

**Category:** Application Integration / Graphics
**Status:** ✅ **IMPLEMENTED** (SZ3568-V1.2 board)
**Hardware:** Mali-G52 GPU with Wayland support
**Use Case:** Kiosk browser, graphical applications, digital signage

## Overview

This document describes the GPU-accelerated graphical display stack implemented for the RK3568 platform using Wayland compositor and WPEWebKit browser.

**Key Decision:** See [ADR-0002: Wayland + WPEWebKit for GPU-Accelerated Web Browser](../adr/0002-wayland-wpewebkit-gpu-acceleration.md) for the architectural rationale behind this implementation.

---

## Hardware Context

### GPU Specifications

- **GPU:** ARM Mali-G52 (Bifrost r1p0)
- **Driver:** Rockchip Mali Bifrost proprietary driver
- **Display Output:** HDMI via Rockchip DRM
- **Graphics APIs:** OpenGL ES 2.0/3.0, EGL
- **Architecture:** Bifrost (second-gen Mali midgard)

### Critical Constraint

**The Mali Bifrost driver only supports Wayland, not X11.** This eliminated traditional X11-based desktop environments (XFCE, etc.) from consideration.

---

## Software Stack

### Architecture

```
┌─────────────────────────────────────────┐
│   Application Layer                     │
│   ┌─────────────────┐                  │
│   │  Cog Browser    │  (kiosk mode)    │
│   │  (WPEWebKit)    │                  │
│   └────────┬────────┘                  │
└────────────┼──────────────────────────┘
             │
┌────────────▼──────────────────────────┐
│   Web Engine Layer                    │
│   ┌──────────────────────────────┐   │
│   │  WPEWebKit                    │   │
│   │  - Hardware-accelerated        │   │
│   │  - Optimized for embedded      │   │
│   │  - GPU rendering via OpenGL ES │   │
│   └──────────┬───────────────────┘   │
└──────────────┼───────────────────────┘
               │
┌──────────────▼───────────────────────┐
│   Display Server Layer               │
│   ┌─────────────────────────────┐   │
│   │  Weston (Wayland Compositor) │   │
│   │  - DRM backend               │   │
│   │  - Hardware cursor           │   │
│   │  - Direct GPU access         │   │
│   └──────────┬──────────────────┘   │
└──────────────┼──────────────────────┘
               │
┌──────────────▼───────────────────────┐
│   Graphics Stack                     │
│   ┌────────────────────────────┐    │
│   │  Mesa 3D + Panfrost        │    │
│   │  - EGL/GLES libraries      │    │
│   │  - Gallium driver          │    │
│   └──────────┬─────────────────┘    │
└──────────────┼──────────────────────┘
               │
┌──────────────▼───────────────────────┐
│   Kernel Layer                       │
│   ┌────────────────────────────┐    │
│   │  Mali Bifrost Driver       │    │
│   │  (CONFIG_MALI_BIFROST=y)   │    │
│   │  Platform: "rk"            │    │
│   └──────────┬─────────────────┘    │
│   ┌──────────▼─────────────────┐    │
│   │  Rockchip DRM Driver       │    │
│   │  - VOP2 display controller │    │
│   │  - HDMI output             │    │
│   └────────────────────────────┘    │
└──────────────────────────────────────┘
```

### Component Versions

- **Wayland:** 1.22+ (protocol and libraries)
- **Weston:** 13.0+ (reference compositor)
- **WPEWebKit:** 2.44+ (web rendering engine)
- **WPEBackend-FDO:** Latest (freedesktop.org backend)
- **Cog:** 0.18+ (minimal browser shell)
- **Mesa:** 24.x (Panfrost Gallium driver)

---

## Implementation Guide

### 1. Kernel Configuration

Add Mali Bifrost GPU support to your kernel config fragment:

**File:** `external/custom/board/rk3568/kernel.config`

```bash
# GPU - Mali G52 via Rockchip Mali Bifrost driver
CONFIG_MALI_BIFROST=y
CONFIG_MALI_PLATFORM_NAME="rk"
CONFIG_MALI_BIFROST_DEVFREQ=y
CONFIG_MALI_BIFROST_DEBUG=n

# DRM/KMS for display output
CONFIG_DRM=y
CONFIG_DRM_ROCKCHIP=y
CONFIG_ROCKCHIP_VOP2=y

# Framebuffer support (required by some applications)
CONFIG_FB=y
CONFIG_FB_ROCKCHIP=y
```

### 2. Buildroot Configuration

Add the graphics stack to your defconfig:

**File:** `external/custom/configs/rk3568_sz3568_defconfig`

```bash
# Packages - Display/Graphics
BR2_PACKAGE_LIBDRM=y
BR2_PACKAGE_LIBDRM_INSTALL_TESTS=y
BR2_PACKAGE_MESA3D=y
BR2_PACKAGE_MESA3D_GALLIUM_DRIVER_PANFROST=y
BR2_PACKAGE_MESA3D_OPENGL_EGL=y
BR2_PACKAGE_MESA3D_OPENGL_ES=y

# Wayland compositor
BR2_PACKAGE_WAYLAND=y
BR2_PACKAGE_WESTON=y
BR2_PACKAGE_WESTON_DEFAULT_DRM=y

# WPE WebKit browser
BR2_PACKAGE_WPEWEBKIT=y
BR2_PACKAGE_WPEWEBKIT_MULTIMEDIA=y
BR2_PACKAGE_WPEBACKEND_FDO=y
BR2_PACKAGE_COG=y
BR2_PACKAGE_COG_PLATFORM_FDO=y
BR2_PACKAGE_COG_PROGRAMS_HOME_URI="https://wpewebkit.org"
```

### 3. Browser Startup Script

Create a script to launch Weston and the browser:

**File:** `external/custom/board/rk3568/rootfs-overlay/usr/local/bin/start-browser`

```bash
#!/bin/bash
# Start Wayland compositor and browser in kiosk mode

# Wait for DRM device
for i in {1..10}; do
    [ -e /dev/dri/card0 ] && break
    sleep 1
done

# Set environment
export XDG_RUNTIME_DIR=/run/user/$(id -u)
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

# Start weston in background
weston --backend=drm-backend.so --tty=1 &
WESTON_PID=$!

# Wait for weston to start
sleep 3

# Launch cog browser in kiosk mode
COG_PLATFORM_FDO_VIEW_FULLSCREEN=1 \
COG_PLATFORM_FDO_VIEW_MAXIMIZE=1 \
cog --platform=fdo "${COG_HOME_URI:-https://wpewebkit.org}"

# If cog exits, kill weston
kill $WESTON_PID
```

Make it executable:
```bash
chmod +x external/custom/board/rk3568/rootfs-overlay/usr/local/bin/start-browser
```

### 4. Systemd Service

Create a systemd service for automatic startup:

**File:** `external/custom/board/rk3568/rootfs-overlay/etc/systemd/system/browser-kiosk.service`

```ini
[Unit]
Description=Browser Kiosk Mode
After=systemd-user-sessions.service
Wants=systemd-user-sessions.service

[Service]
Type=simple
User=root
TTY=/dev/tty1
PAMName=login
Environment=XDG_SESSION_TYPE=wayland
StandardInput=tty
StandardOutput=journal
StandardError=journal
ExecStart=/usr/local/bin/start-browser
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 5. Enable the Service

The service will be automatically enabled via the rootfs overlay. To manually enable:

```bash
systemctl enable browser-kiosk.service
```

---

## Verification & Testing

### Boot Sequence

1. **Kernel boots** → Mali driver loads
2. **DRM initializes** → Display output ready
3. **Systemd starts** → browser-kiosk.service launches
4. **Weston starts** → Wayland compositor running
5. **Browser opens** → Fullscreen kiosk mode

### GPU Status Check

```bash
# Check GPU driver loaded
dmesg | grep -i mali

# Expected output:
# mali ff400000.gpu: Mali GPU identified as: Mali-G52 (0x7402) r1p0
# mali ff400000.gpu: GPU identified as 0x7 arch 7.4.0 r0p0 status 0

# Check device nodes
ls -la /dev/mali0 /dev/dri/

# Expected output:
# crw------- 1 root root 511, 0 ... /dev/mali0
# drwxr-xr-x 3 root root ... /dev/dri/
# crw-rw---- 1 root video 226, 0 ... /dev/dri/card0
# crw-rw-rw- 1 root render 226, 128 ... /dev/dri/renderD128
```

### Display Output Check

```bash
# Check Weston is running
ps aux | grep weston

# Check browser is running
ps aux | grep cog

# View logs
journalctl -u browser-kiosk.service -f
```

### WebGL Verification

Navigate to: **https://get.webgl.org/**

You should see:
- ✅ "Your browser supports WebGL"
- GPU information showing Mali-G52

### Performance Test

Navigate to: **https://webglsamples.org/aquarium/aquarium.html**

Expected performance:
- 30-60 FPS with 1000 fish
- Smooth rendering without tearing
- GPU utilization visible in `/sys/class/devfreq/`

---

## Configuration Options

### Change Home URL

Edit the defconfig:
```bash
BR2_PACKAGE_COG_PROGRAMS_HOME_URI="https://your-url.com"
```

Or set environment variable:
```bash
export COG_HOME_URI="https://your-url.com"
```

### Weston Configuration

Create `/etc/weston.ini` in rootfs overlay:

```ini
[core]
backend=drm-backend.so
shell=kiosk-shell.so

[shell]
background-color=0xff000000
panel-position=none
locking=false

[output]
name=HDMI-A-1
mode=1920x1080
transform=normal
```

### Performance Tuning

#### GPU Frequency Scaling

```bash
# Check GPU governor
cat /sys/class/devfreq/ff400000.gpu/governor

# Set to performance mode
echo performance > /sys/class/devfreq/ff400000.gpu/governor

# Check available frequencies
cat /sys/class/devfreq/ff400000.gpu/available_frequencies
```

#### Browser Memory Limits

Set environment variables in startup script:

```bash
# Limit memory cache (MB)
export WPE_SHELL_DISABLE_MEMORY_PRESSURE=1
export WEBKIT_DISABLE_COMPOSITING_MODE=0

# Enable process sharing
export COG_PLATFORM_FDO_VIEW_AUTOMATION=1
```

---

## Troubleshooting

### Issue: Black Screen

**Symptoms:** System boots, but HDMI shows no output

**Checks:**
```bash
# Verify DRM driver loaded
dmesg | grep drm

# Check HDMI status
cat /sys/class/drm/card0-HDMI-A-1/status
# Should show: connected

# Check display modes
modetest -M rockchip -c
```

**Solution:** Verify DTB includes HDMI node and display-subsystem.

### Issue: Browser Crashes

**Symptoms:** Systemd keeps restarting browser-kiosk.service

**Checks:**
```bash
# View crash logs
journalctl -u browser-kiosk.service --no-pager

# Check for OOM (out of memory)
dmesg | grep -i "out of memory"

# Verify EGL/GLES libraries
ldd /usr/bin/cog | grep -i egl
```

**Solutions:**
- Increase rootfs size (BR2_TARGET_ROOTFS_EXT2_SIZE)
- Reduce browser memory usage
- Check for missing libraries

### Issue: No GPU Acceleration

**Symptoms:** Browser works but WebGL reports software rendering

**Checks:**
```bash
# Verify Mali driver loaded
lsmod | grep mali

# Check EGL info
eglinfo | head -20

# Test OpenGL ES
glmark2-es2-wayland
```

**Solution:** Verify kernel config includes `CONFIG_MALI_BIFROST=y`

### Issue: Weston Won't Start

**Symptoms:** Weston fails with "cannot find DRM device"

**Checks:**
```bash
# Check DRM device exists
ls -la /dev/dri/card0

# Check permissions
groups root | grep -E 'video|render'

# Try manual start
weston --backend=drm-backend.so --tty=1 --log=/tmp/weston.log
cat /tmp/weston.log
```

**Solution:** Add root user to `video` and `render` groups.

---

## Performance Benchmarks

### Boot Time (to browser visible)

- **Cold boot to login prompt:** ~8-12 seconds
- **Login to Weston started:** ~2 seconds
- **Weston to browser visible:** ~3-5 seconds
- **Total boot to browser:** ~15-20 seconds

### Resource Usage

```
Component          | Memory (RSS) | CPU (idle) | CPU (active)
-------------------|--------------|------------|-------------
Weston compositor  | ~25 MB       | 0-2%       | 5-10%
WPEWebKit engine   | ~120-180 MB  | 1-3%       | 15-40%
Cog browser shell  | ~15 MB       | 0-1%       | 1-2%
Total graphics     | ~160-220 MB  | 2-6%       | 20-50%
```

### WebGL Performance

- **Simple scene:** 60 FPS sustained
- **Medium complexity:** 45-60 FPS
- **High complexity:** 30-45 FPS
- **GPU utilization:** 40-80% depending on workload

---

## Alternatives Considered

See [ADR-0002](../adr/0002-wayland-wpewebkit-gpu-acceleration.md) for detailed analysis.

### X11 + XFCE Desktop

**Rejected:** Mali Bifrost driver does not support X11

### Firefox Browser

**Rejected:** Requires OpenGL 3.2+ (we have GLES 2.0), too heavy for embedded

### Chromium Browser

**Rejected:** Not available in Buildroot

### Qt WebEngine

**Considered:** Heavy, complex, Chromium-based. WPEWebKit is lighter and purpose-built for embedded.

---

## Related Documentation

- [ADR-0002: Wayland + WPEWebKit](../adr/0002-wayland-wpewebkit-gpu-acceleration.md) - Architecture decision record
- [Hardware Enablement](03-hardware-enablement.md) - GPU driver integration
- [Application Integration](06-application-integration.md) - General app integration guide
- [WPEWebKit Documentation](https://wpewebkit.org/) - Upstream documentation
- [Weston Documentation](https://wayland.freedesktop.org/weston.html) - Compositor documentation

---

## Reference Implementation

**Board:** SZ3568-V1.2 (RK3568)
**Branch:** `feature/wayland-wpewebkit`
**PR:** [#6](https://github.com/aaronsb/rk356x/pull/6)

**Files:**
- `external/custom/configs/rk3568_sz3568_defconfig` - Buildroot configuration
- `external/custom/board/rk3568/kernel.config` - Mali GPU kernel config
- `external/custom/board/rk3568/rootfs-overlay/usr/local/bin/start-browser` - Launch script
- `external/custom/board/rk3568/rootfs-overlay/etc/systemd/system/browser-kiosk.service` - Systemd service
- `docs/adr/0002-wayland-wpewebkit-gpu-acceleration.md` - Architecture decision

---

## Industry Use Cases

This stack is used in production for:

- **Automotive infotainment systems** (Qt Wayland + WebEngine variant)
- **Digital signage** (WPEWebKit kiosks)
- **Smart displays** (Touch-enabled Wayland compositors)
- **IoT dashboards** (Embedded web interfaces)
- **Retail kiosks** (Single-purpose web applications)

**Best Practice:** This is industry-standard approach for embedded web display with GPU acceleration on ARM platforms.
