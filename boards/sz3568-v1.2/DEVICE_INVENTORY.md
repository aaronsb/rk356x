# SZ3568-V1.2 Device Inventory

Comparison of vendor 4.19 kernel vs our 6.1 kernel device support.

## Status Legend
- ✅ Working on our kernel
- ⚠️ Present but untested
- ❌ Not implemented
- 🔧 Needs driver work

---

## Networking

| Device | Address | Vendor Status | Our Status | Notes |
|--------|---------|---------------|------------|-------|
| GMAC1 (Gigabit Ethernet) | fe010000 | ✅ Working | ✅ Working | MAE0621A PHY, 1Gbps |
| GMAC0 (Ethernet) | fe2a0000 | Present | ❌ Not configured | Second ethernet port |
| WiFi (RTL8723DS) | - | ✅ Working | ❌ Not implemented | 8723ds module |
| Bluetooth | - | Present | ❌ Not implemented | Part of RTL8723DS |
| CAN Bus 0 | fe570000 | Present | ❌ Not implemented | |
| CAN Bus 1 | fe580000 | Present | ❌ Not implemented | |
| CAN Bus 2 | fe590000 | Present | ❌ Not implemented | |

## Display / Video Output

| Device | Address | Vendor Status | Our Status | Notes |
|--------|---------|---------------|------------|-------|
| VOP (Video Output) | fe040000 | ✅ Working | ⚠️ Untested | Display controller |
| HDMI | fe0a0000 | ✅ Working | ⚠️ Untested | |
| MIPI DSI 0 | fe060000 | Present | ❌ Not implemented | |
| MIPI DSI 1 | fe070000 | Present | ❌ Not implemented | |
| eDP | fe0c0000 | Present | ❌ Not implemented | |

## Camera / Media

| Device | Address | Vendor Status | Our Status | Notes |
|--------|---------|---------------|------------|-------|
| RKCIF (Camera IF) | fdfe0000 | Present | ❌ Not implemented | |
| RKISP (Image Processor) | fdff0000 | Present | ❌ Not implemented | |
| CSI2 DPHY | fe870000 | Present | ❌ Not implemented | Camera PHY |
| RKVDEC (Video Decoder) | fdf80200 | Present | ⚠️ Untested | H.264/H.265 decode |
| RKVENC (Video Encoder) | fdf40000 | Present | ⚠️ Untested | H.264/H.265 encode |
| RGA (2D Graphics) | fdeb0000 | Present | ⚠️ Untested | 2D acceleration |
| IEP (Image Enhance) | fdef0000 | Present | ❌ Not implemented | |
| JPEGD (JPEG Decoder) | fded0000 | Present | ❌ Not implemented | |

## AI / Accelerators

| Device | Address | Vendor Status | Our Status | Notes |
|--------|---------|---------------|------------|-------|
| NPU | fde40000 | Present | ❌ Not implemented | Neural Processing Unit |
| GPU (Mali G52) | fde60000 | ✅ Working | ⚠️ Untested | Needs Mali driver |
| Crypto Engine | fe380000 | Present | ⚠️ Untested | HW crypto acceleration |

## Storage

| Device | Address | Vendor Status | Our Status | Notes |
|--------|---------|---------------|------------|-------|
| SDHCI (eMMC/SD) | fe310000 | ✅ Working | ✅ Working | Boot device |
| DWMMC 0 (SD Card) | fe000000 | ❌ Broken | ✅ Working | Fixed in 6.1! |
| DWMMC 1 | fe2b0000 | Present | ⚠️ Untested | |
| DWMMC 2 | fe2c0000 | Present | ⚠️ Untested | |
| SATA 0 | fc000000 | Present | ❌ Not implemented | |
| SATA 1 | fc400000 | Present | ❌ Not implemented | |
| SATA 2 | fc800000 | Present | ❌ Not implemented | |
| NANDC | fe330000 | Present | ❌ Not implemented | NAND controller |
| SFC (SPI Flash) | fe300000 | Present | ❌ Not implemented | |

## PCIe

| Device | Address | Vendor Status | Our Status | Notes |
|--------|---------|---------------|------------|-------|
| PCIe 2.0 | fe260000 | Present | ❌ Not implemented | |
| PCIe 3.0 x1 | fe270000 | Present | ❌ Not implemented | |
| PCIe 3.0 x2 | fe280000 | Present | ❌ Not implemented | |

## USB

| Device | Address | Vendor Status | Our Status | Notes |
|--------|---------|---------------|------------|-------|
| USB 3.0 DRD | fd800000 | ✅ Working | ⚠️ Untested | OTG capable |
| USB 3.0 Host | fd840000 | ✅ Working | ⚠️ Untested | |
| USB 2.0 Host | fd880000 | ✅ Working | ⚠️ Untested | |
| USB 2.0 Host | fd8c0000 | ✅ Working | ⚠️ Untested | |
| USB2 PHY 0 | fe8a0000 | ✅ Working | ⚠️ Untested | |
| USB2 PHY 1 | fe8b0000 | ✅ Working | ⚠️ Untested | |

## Serial / Communication

| Device | Address | Vendor Status | Our Status | Notes |
|--------|---------|---------------|------------|-------|
| UART2 (Debug) | fe670000 | ✅ Working | ✅ Working | 1500000 baud |
| UART0-9 | fe650000+ | Present | ⚠️ Untested | Multiple UARTs |
| I2C 0-5 | fe5a0000+ | Present | ⚠️ Untested | |
| SPI 0-3 | fe610000+ | Present | ⚠️ Untested | |

## Audio

| Device | Address | Vendor Status | Our Status | Notes |
|--------|---------|---------------|------------|-------|
| I2S 0-3 | fe400000+ | Present | ❌ Not implemented | |
| PDM | fe440000 | Present | ❌ Not implemented | Digital mic |
| SPDIF | fe460000 | Present | ❌ Not implemented | |
| Audio PWM | fe470000 | Present | ❌ Not implemented | |
| VAD | fe450000 | Present | ❌ Not implemented | Voice Activity |

## Other Peripherals

| Device | Address | Vendor Status | Our Status | Notes |
|--------|---------|---------------|------------|-------|
| PWM 0-15 | fe6e0000+ | Present | ⚠️ Untested | Multiple PWM channels |
| SARADC | fe720000 | Present | ⚠️ Untested | 6-channel ADC |
| TSADC | fe710000 | Present | ⚠️ Untested | Thermal sensor |
| Watchdog | fe600000 | Present | ⚠️ Untested | |
| OTP | fe38c000 | Present | ⚠️ Untested | One-time programmable |
| RNG | fe388000 | Present | ⚠️ Untested | Random number gen |

---

## Priority List for Implementation

### High Priority
1. **WiFi (RTL8723DS)** - Common use case
2. **HDMI** - Display output
3. **USB** - Verify host/device modes
4. **GPU (Mali G52)** - Graphics acceleration

### Medium Priority
5. **PCIe** - NVMe/expansion cards
6. **SATA** - Storage expansion
7. **CAN Bus** - Industrial applications
8. **Video Codec** - Media playback

### Low Priority
9. **NPU** - AI inference
10. **Camera** - CSI interface
11. **Audio** - I2S/SPDIF
12. **Second Ethernet** - GMAC0

---

## Driver Sources

| Device | Driver Location | Notes |
|--------|-----------------|-------|
| MAE0621A PHY | external/custom/patches/linux/maxio.c | From CoreELEC |
| RTL8723DS WiFi | out-of-tree | Realtek driver needed |
| Mali G52 GPU | out-of-tree | ARM Mali driver |
| NPU | Rockchip BSP | RKNN toolkit |
| Video Codec | mainline + patches | rkvdec/rkvenc |

---

## Notes

- Vendor kernel: 4.19.232 (Rockchip BSP)
- Our kernel: 6.1.118 LTS
- Many drivers available in mainline 6.1, just need DT configuration
- Some devices (NPU, Mali) require out-of-tree drivers
- WiFi chip (RTL8723DS) needs Realtek out-of-tree driver
