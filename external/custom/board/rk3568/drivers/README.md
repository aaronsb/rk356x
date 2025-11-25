# Driver Sources

Reference copies of vendor drivers used in kernel patches.

## maxio.c - MAXIO MAE0621A PHY Driver

**Source:** https://github.com/CoreELEC/common_drivers/blob/c758f3df5449105018701c8ce04869c7ab8811c4/drivers/net/phy/maxio.c

**Version:** v1.8.1.4

**Purpose:** Gigabit ethernet PHY driver for MAXIO MAE0621A used on SZ3568-V1.2 board.

**Key feature:** `maxio_mae0621a_clk_init()` function with 1000ms delay for clock stabilization - required for proper GMAC DMA reset.

This file is embedded into `patches/linux/0001-add-maxio-phy-driver.patch` for kernel integration.
