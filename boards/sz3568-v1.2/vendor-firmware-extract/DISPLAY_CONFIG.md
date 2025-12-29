# Vendor Display Configuration

Extracted from: `sz3568_Ubuntu1804_20250619_lvds_1024x600.rar`

## Native LVDS Panel (1024x600)

Uses Rockchip BSP `rockchip,rk3568-lvds` driver (not in mainline).

```
clock-frequency: 66 MHz
hactive: 1024
vactive: 600
hback-porch: 200
hfront-porch: 110
vback-porch: 20
vfront-porch: 13
hsync-len: 10
vsync-len: 2
width-mm: 217
height-mm: 136
```

## DSI Panel via GM8775C (1920x1080)

Uses Rockchip BSP `simple-panel-dsi` with `panel-init-sequence`.

```
clock-frequency: 132 MHz
hactive: 1920
vactive: 1080
hfront-porch: 15
hsync-len: 2
hback-porch: 30
vfront-porch: 15
vsync-len: 2
vback-porch: 15
dsi,lanes: 4
dsi,format: RGB888 (0x00)
dsi,flags: 0xa03
```

### GM8775C Panel Init Sequence

This is sent via DSI generic write commands to configure the GM8775C bridge.
Format: `[type delay len data...]` where type 0x23 = generic short write.

```
23 00 02 fe 21   # Register 0xFE = 0x21 (select page)
23 00 02 04 00   # Register 0x04 = 0x00
23 00 02 00 64   # Register 0x00 = 0x64
23 00 02 2a 00
23 00 02 26 64
... (continues with gamma/timing setup)
23 00 02 fe 00   # Back to page 0
23 00 02 35 00   # Tearing effect line on
05 78 01 11      # Sleep out (0x11), delay 120ms
05 1e 01 29      # Display on (0x29), delay 30ms
```

Full sequence in vendor DTS at line 2785.

## Key GPIOs

| Function | GPIO | Notes |
|----------|------|-------|
| Panel Reset | gpio0-0 (RK_PA0) | Active low |
| TC358775 Power | gpio0-8 (RK_PB0) | Active high |
| TC358775 Reset | gpio3-29 (RK_PD5) | Active high per vendor |
| Backlight Enable | gpio0-29 | Active high |
| LCD Power (lcd1) | gpio0-21 (RK_PC5) | vcc3v3_lcd1_n |

## Display Routing

```
VOP2 VP1 -> DSI0 -> GM8775C -> LVDS Panel
VOP2 VP1 -> Native LVDS -> LVDS Panel (BSP only)
VOP2 VP0 -> HDMI
```

## Notes

1. Native LVDS requires Rockchip BSP kernel - not available in mainline
2. DSI->GM8775C requires `simple-panel-dsi` driver with `panel-init-sequence` - BSP only
3. TC358775 at I2C2 0x0f has mainline driver but chip doesn't respond (may not be populated)
4. For mainline, need to either:
   - Write custom DRM panel driver for GM8775C
   - Port RK3568 LVDS support to mainline rockchip_lvds.c
