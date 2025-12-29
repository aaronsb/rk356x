# Device Tree Sources

## Active (rockchip/)

These are the **actively used** DTS files, compiled into the kernel:

| File | Board | Description |
|------|-------|-------------|
| `rk3568-sz3568.dts` | SZ3568-V1.2 | Clean mainline DTS (kernel 6.12+) |
| `rk3568-dc-a568.dts` | DC-A568-V06 | Alternate board support |

These include only mainline `rk3568.dtsi` from the kernel tree - no vendor extensions.

## Reference (reference/)

Historical and vendor files kept for reference when adding new hardware support:

| File | Purpose |
|------|---------|
| `rk3568-sz3568-custom-working.dts` | Our older working DTS before mainline rewrite |
| `rk3568-sz3568-custom.dts.disabled` | Disabled experimental DTS |
| `vendor/rk3568-sz3568.dtsi` | OEM vendor common hardware (36KB) |
| `vendor/rk3568-sz3568-v10.dtsi` | OEM vendor board variant (14KB) |
| `vendor/rk3568-linux.dtsi` | Rockchip vendor Linux extensions |

## History

- **Nov 2025**: Started with Rockchip BSP kernel and vendor DTS
- **Dec 2025**: Rewrote to clean mainline DTS (commit `fa905ae`)
- **Dec 2025**: Moved unused vendor files to reference/

## Adding New Hardware

When enabling new peripherals (LVDS, DSI, etc.):
1. Check `reference/vendor/` files for pin mappings and register values
2. Translate to mainline DTS syntax
3. Add to active `rockchip/rk3568-sz3568.dts`
