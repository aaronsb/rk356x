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
- **PHY Chip**: Realtek RTL8211F (OUI 0x1EDD11)
- **PHY IDs**: 001c.c942 (Realtek RTL8211F)
- **PHY Addresses**: 0, 1, 2, 3 (four PHYs detected)
- **Active PHY**: Address 0
- **Reset GPIO**: GPIO3_A1 (gpio3 pin 1)
- **Reset Delays**: 0, 20ms, 100ms
- **Reset Active Low**: Yes
- **PHY Supply**: vcc3v3-phy (3.3V fixed regulator)

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
| PHY Chip | Motorcomm YT8512 | Realtek RTL8211F |
| Clock Mode | OUTPUT (to PHY) | INPUT (from PHY) |
| Clock Rate | 50MHz | 125MHz |
| TX Delay | 0x3c (60) | 0x4f (79) |
| Reset GPIO | GPIO3_D3 | GPIO3_A1 |
| PHY Count | 1 | 4 |

## Required Kernel Drivers

### Ethernet Drivers
- `stmmac` - Synopsys MAC driver
- `dwmac-rk` - Rockchip GMAC platform driver
- `realtek` - Realtek PHY driver (CONFIG_REALTEK_PHY)
- `libphy` - Generic PHY library

### PHY Driver Details
The Realtek RTL8211F PHY requires:
```
CONFIG_REALTEK_PHY=y
```

Driver file: `drivers/net/phy/realtek.c`
- Supports RTL8211F (PHY ID 0x001cc916)
- Gigabit capable
- RGMII interface support
- Auto-negotiation support

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
2. ⏳ Create custom device tree for Buildroot
3. ⏳ Configure kernel with Realtek PHY driver
4. ⏳ Build custom firmware
5. ⏳ Test boot from SD card (NOT eMMC)
6. ⏳ Verify ethernet functionality

## Notes

- Do NOT flash to eMMC until fully tested on SD card
- Vendor firmware uses kernel 4.19.232, we use 6.1 BSP
- Vendor uses systemd (Ubuntu), we can use systemd or other init
- PHY driver must support RTL8211F specifically
