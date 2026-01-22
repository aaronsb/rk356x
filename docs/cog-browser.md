# Cog Browser for WebGL

Cog is a lightweight WebKit-based browser optimized for embedded ARM devices. It provides smooth WebGL rendering on the RK3568 with Panfrost GPU, avoiding buffer management issues present in Chromium.

![Cog running WebGL Aquarium at 38 FPS](media/cog-webgl-aquarium-38fps.jpg)

## Why Cog?

| Browser | WebGL Performance | Notes |
|---------|-------------------|-------|
| Chromium | Stutters badly | SharedImageManager mailbox bug on ARM |
| Firefox | Good, occasional pauses | Solid alternative |
| **Cog (WPE WebKit)** | **~38 FPS, smooth** | Best performance on this platform |

Cog uses WPE WebKit, which handles GPU buffer lifecycle correctly on ARM/Panfrost. It's designed specifically for embedded Wayland environments.

## Usage

### Quick Start

```bash
# Run the included demo
./webgl-demo.sh

# Or launch any URL
cog https://webglsamples.org/aquarium/aquarium.html
```

### From SSH

Cog needs Wayland environment variables. If running from SSH while sway is active on tty1:

```bash
sudo -u user WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1001 cog https://example.com
```

### Keyboard Shortcuts

Cog runs fullscreen by default. Use sway's window management:

| Key | Action |
|-----|--------|
| `Super+Shift+Q` | Close Cog |
| `Super+F` | Toggle fullscreen |
| `Super+1-4` | Switch workspace |

## Technical Details

### Packages

- `cog` - WPE WebKit launcher and webapp container
- `wpewebkit-driver` - WebDriver support for automation

### Why Chromium Stutters

Chromium on ARM/Wayland has a known issue with `SharedImageManager::ProduceSkia` where mailbox buffers are accessed after being destroyed, causing frame drops. This manifests as smooth animation interrupted by brief "reversions" to previous frames.

The issue is in Chromium's multi-process GPU architecture, not the Panfrost driver - native GL apps and WPE WebKit work smoothly.

### Resources

- [Cog GitHub](https://github.com/Igalia/cog)
- [WPE WebKit](https://wpewebkit.org/)
- [Panfrost Driver](https://docs.mesa3d.org/drivers/panfrost.html)
