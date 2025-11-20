# DC-A568-V06 Board

Dingchang Electronics RK3568 development board.

## Hardware

- **SoC:** Rockchip RK3568 (Quad Cortex-A55)
- **RAM:** 4GB LPDDR4X
- **Storage:** 32GB eMMC
- **Ethernet:** Dual GbE (not working with EVB DTB)
- **Display:** HDMI, MIPI DSI, LVDS
- **Debug:** UART2 @ 1500000 baud (3-pin header)

## Current Status

- **U-Boot:** Working (evb-rk3568 defconfig + SARADC disabled)
- **Kernel:** Boots with EVB device tree
- **Ethernet:** Not working (EVB DTB mismatch)
- **Display:** Not tested

## Known Issues

1. **SARADC causes boot loop** - The EVB's download key ADC pin floats on this board, causing false detection. Disabled in uboot.config.

2. **No ethernet** - EVB device tree doesn't match DC-A568 ethernet configuration.

## TODO

- [ ] Create proper device tree using extracted vendor DTB as reference
- [ ] Enable ethernet
- [ ] Test display outputs
- [ ] Document GPIO/pinout differences from EVB

## Files

- `board.conf` - Board configuration variables
- `uboot.config` - U-Boot config fragment (disables SARADC)
- `dtb/dc-a568-v06.dtb` - Extracted vendor device tree (for reference)
