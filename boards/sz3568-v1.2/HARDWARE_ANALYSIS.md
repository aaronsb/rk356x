# SZ3568-V1.2 Hardware Analysis

## Board Overview
- **Model**: SZ3568-V1.2
- **SoC**: Rockchip RK3568
- **RAM**: 2GB LPDDR4
- **Storage**: 14.6GB eMMC
- **OS**: Ubuntu 18.04.6 LTS
- **Kernel**: 4.19.232
- **Serial Console**: UARTD (TRG pins), 1500000 baud, 3.3V
- **Default Credentials**: ubuntu/ubuntu

## Ethernet Hardware Configuration

### Controller
- **MAC**: gmac1 (not gmac0)
- **Base Address**: 0xfe010000
- **Compatible**: "rockchip,rk3568-gmac", "snps,dwmac-4.20a"
- **Driver**: dwmac-rk (Rockchip GMAC driver)

### PHY Configuration
- **PHY Mode**: RGMII (Reduced Gigabit MII)
- **PHY Chip**: Maxio MAE0621A (PHY ID 0x7b744411)
- **Active PHY**: Address 0
- **Reset GPIO**: GPIO3_A1 (gpio3 pin 1)
- **Reset Delays**: 0, 20ms, 100ms
- **Reset Active Low**: Yes
- **PHY Supply**: vcc3v3-phy (3.3V fixed regulator)
- **Driver**: maxio.c (from CoreELEC, requires vendor-specific init)

### Clock Configuration
- **Clock Mode**: INPUT (clock comes FROM PHY, not output)
- **External Clock**: 125MHz (0x7735940 Hz) from PHY
- **Clock Source**: external-gmac1-clock
- **TX Delay**: 0x4f (79 decimal)
- **RX Delay**: Not explicitly set (default)

### Pinctrl Groups
All pinmux on GPIO3 (multiplexing mode 3):
- gmac1m0-miim: MDIO management interface
- gmac1m0-tx-bus2: TX data bus (2 data lines)
- gmac1m0-rx-bus2: RX data bus (2 data lines)
- gmac1m0-rgmii-clk: RGMII clock signals
- gmac1m0-rgmii-bus: Additional RGMII data lines (for gigabit)
- gmac1m0-clkinout: Clock input/output pin

### Network Configuration
- **Interface**: eth0
- **MAC Address**: de:41:7a:89:be:66
- **IP**: 192.168.1.21/24 (DHCP)
- **Link Status**: UP, working
- **Additional Interfaces**: wlan0, p2p0 (WiFi present but not configured)

## Key Differences from DC-A568 Board

| Feature | DC-A568-V06 | SZ3568-V1.2 |
|---------|-------------|-------------|
| MAC Controller | gmac0 (0xfe2a0000) | gmac1 (0xfe010000) |
| PHY Mode | RMII (100Mbps) | RGMII (1Gbps) |
| PHY Chip | Motorcomm YT8512 | Maxio MAE0621A |
| Clock Mode | OUTPUT (to PHY) | INPUT (from PHY) |
| Clock Rate | 50MHz | 125MHz |
| TX Delay | 0x3c (60) | 0x4f (79) |
| Reset GPIO | GPIO3_D3 | GPIO3_A1 |
| PHY Count | 1 | 4 |

## Required Kernel Drivers

### Ethernet Drivers
- `stmmac` - Synopsys MAC driver
- `dwmac-rk` - Rockchip GMAC platform driver
- `maxio` - Maxio MAE0621A PHY driver (CONFIG_MAXIO_PHY)
- `libphy` - Generic PHY library

### PHY Driver Details
The Maxio MAE0621A PHY requires:
```
CONFIG_MAXIO_PHY=y
```

Driver file: `external/custom/patches/linux/maxio.c` (from CoreELEC)
- PHY ID 0x7b744411
- Gigabit capable
- RGMII interface support
- Requires vendor-specific clock initialization (maxio_mae0621a_clk_init)
- Generic PHY driver does NOT work - requires full config_init sequence

## eMMC Partition Layout

```
Device         Size  Type       Mountpoint    Purpose
mmcblk0p1      4M    Unknown                  U-Boot/idbloader
mmcblk0p2      4M    Unknown                  Misc/environment
mmcblk0p3      64M   Unknown                  Boot (kernel, DTB, initramfs)
mmcblk0p4      128M  Unknown                  Recovery
mmcblk0p5      32M   Unknown                  Resource (DTB files)
mmcblk0p6      6G    ext4       /             Root filesystem
mmcblk0p7      128M  ext4       /oem          Vendor files
mmcblk0p8      8.2G  ext4       /userdata     User data
```

## Backup Files

Located in `/home/aaron/Projects/jvl/rk356x/boards/sz3568-v1.2/backup/`:

- `p1-uboot.img` - U-Boot bootloader
- `p2-misc.img` - Misc partition
- `p3-boot.img` - Boot partition (kernel + DTB)
- `p5-resource.img` - Resource partition (DTBs)
- `p7-oem.img` - OEM vendor files
- `vendor.dtb` - Extracted device tree blob
- `vendor.dts` - Decompiled device tree source (6774 lines)

## Next Steps

1. ✅ Extract and analyze vendor device tree
2. ✅ Create custom device tree for Buildroot
3. ✅ Configure kernel with Maxio MAE0621A PHY driver
4. ✅ Build custom firmware
5. ✅ Test boot from SD card (NOT eMMC)
6. ✅ Verify ethernet functionality (1Gbps working!)
7. ✅ SD card reader working (fixed in 6.1 kernel!)
8. ⏳ Add WiFi support (RTL8723DS)
9. ⏳ Test HDMI/display output
10. ⏳ Test USB host/device modes
11. ⏳ Add remaining peripherals as needed

## Notes

- Do NOT flash to eMMC until fully tested on SD card
- Vendor firmware uses kernel 4.19.232, we use 6.1.118 LTS
- Vendor uses systemd (Ubuntu), we use BusyBox init
- MAE0621A PHY requires CoreELEC out-of-tree driver
- SD card reader broken on 4.19, works on 6.1
