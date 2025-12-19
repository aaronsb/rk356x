# ADR-0006: Wayland/Sway Desktop Environment

**Status:** Accepted

**Date:** 2025-12-16

**Deciders:** @aaronsb

**Technical Story:** Commit `17d1c7e`

## Context

Initial desktop work used X11 with XFCE - a traditional, well-understood stack. However, on ARM with Panfrost GPU:

- X11 compositing has overhead
- XFCE is relatively heavy for embedded
- Wayland is the modern Linux display path
- Panfrost has excellent Wayland support

After desktop stability was achieved, we evaluated switching to Wayland.

## Decision Drivers

- Performance on ARM SoC
- GPU driver compatibility (Panfrost)
- Resource efficiency (RAM, CPU)
- Modern display protocol support
- Tiling window manager preference

## Considered Options

### Option 1: X11 + XFCE (previous)

**Description:** Traditional X11 display server with XFCE desktop.

**Pros:**
- Well-understood, widely documented
- Broad application compatibility
- Team familiarity

**Cons:**
- X11 compositing overhead
- XFCE relatively heavy for embedded
- Legacy architecture
- Panfrost X11 support less optimized

### Option 2: X11 + lightweight WM

**Description:** X11 with minimal window manager (openbox, i3).

**Pros:**
- Lower resource usage than XFCE
- Still X11 compatible

**Cons:**
- Still X11 overhead
- Not leveraging Wayland improvements

### Option 3: Wayland + sway (selected)

**Description:** Wayland compositor with sway (i3-compatible tiling WM).

**Pros:**
- Native Wayland - best Panfrost path
- sway is lightweight and fast
- Tiling WM efficient for embedded use
- Modern protocol (HiDPI, smooth scrolling, etc.)
- Lower latency than X11

**Cons:**
- Some X11 apps need XWayland
- Less documentation than XFCE
- Tiling WM learning curve

### Option 4: Wayland + weston

**Description:** Reference Wayland compositor.

**Pros:**
- Simple, minimal
- Good for kiosk use

**Cons:**
- Not a full desktop environment
- Limited window management

## Decision

We use Wayland with sway as the desktop environment.

Key implementation:
- sway installed as compositor
- Minimal sway config in rootfs overlay
- foot terminal as default (Wayland-native)
- Firefox ESR + Chromium (both Wayland-capable)
- XWayland available for legacy apps

## Consequences

### Positive

- Noticeably smoother display performance
- Lower CPU usage during compositing
- Better Panfrost integration
- Modern display features (per-monitor scaling, etc.)
- Efficient tiling workflow
- Firefox/Chromium work well in Wayland mode

### Negative

- Some legacy X11 apps need XWayland
- sway config differs from XFCE workflow
- Debugging tools differ from X11

### Neutral

- Display server choice independent of other ADRs
- Can revert to X11 if needed (packages still available)

## Implementation Notes

Rootfs overlay includes minimal sway config:
```
/etc/skel/.config/sway/config
```

Key packages:
- `sway` - Wayland compositor
- `foot` - Wayland-native terminal
- `xwayland` - X11 compatibility layer
- `wl-clipboard` - Clipboard utilities

Auto-start on login via `/etc/profile.d/` or display manager.

## References

- sway: https://swaywm.org/
- Commit `17d1c7e`: Switch to Wayland/sway
- Panfrost Wayland support: native path, best performance
