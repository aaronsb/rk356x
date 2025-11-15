# JVL RK3568 Buildroot External Tree

This directory contains the Buildroot external tree for the JVL RK3568 platform.

## Structure

```
external/custom/
├── Config.in              # External configuration entry point
├── external.desc          # External tree description
├── external.mk            # External makefile
├── board/rk3568/          # Board-specific files
│   ├── rootfs-overlay/    # Files to copy to rootfs
│   ├── post-build.sh      # Post-build script
│   ├── linux.config       # Kernel config fragment
│   └── uboot.config       # U-Boot config fragment
├── configs/               # Board defconfigs
│   └── rk3568_custom_defconfig
└── package/               # Custom packages
    └── Config.in
```

## Usage

### Initial Setup

```bash
cd buildroot
export BR2_EXTERNAL=../external/custom
make list-defconfigs  # Should show rk3568_custom_defconfig
```

### Building

```bash
make rk3568_custom_defconfig
make -j$(nproc)
```

### Configuration

```bash
make menuconfig          # Build system config
make linux-menuconfig    # Kernel config
make uboot-menuconfig    # U-Boot config
make busybox-menuconfig  # BusyBox config
```

### Saving Configuration

```bash
make savedefconfig BR2_DEFCONFIG=../external/custom/configs/rk3568_custom_defconfig
make linux-update-defconfig
make uboot-update-defconfig
```

## Adding Custom Packages

Create a new directory in `package/`:

```bash
external/custom/package/mypackage/
├── Config.in
├── mypackage.mk
└── mypackage.hash
```

Then add to `package/Config.in`:
```
source "$BR2_EXTERNAL_JVL_PATH/package/mypackage/Config.in"
```

## Rootfs Overlay

Files in `board/rk3568/rootfs-overlay/` are copied directly to the rootfs:

```
rootfs-overlay/
├── etc/
│   └── myconfig
├── opt/
│   └── platform-app/
└── usr/
    └── local/
        └── bin/
```

## Post-Build Script

`board/rk3568/post-build.sh` runs after rootfs is built but before image creation. Use for:
- Final file modifications
- Copying binaries
- Setting permissions
- Generating files

## References

- [Buildroot Manual - External Trees](https://buildroot.org/downloads/manual/manual.html#outside-br-custom)
- [Buildroot Training](https://bootlin.com/doc/training/buildroot/)
