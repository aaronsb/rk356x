# Configuration Directory

This directory contains board-specific configurations and customization files.

## Directory Structure

```
config/
├── boards/              # Board configuration files
│   ├── rock-3a.conf
│   ├── quartz64-a.conf
│   ├── nanopi-r5s.conf
│   ├── station-m2.conf
│   └── evb-rk3568.conf
├── kernel/              # Kernel config fragments
├── u-boot/              # U-Boot config fragments
├── patches/             # Patches for kernel/u-boot
│   ├── kernel/
│   └── u-boot/
├── rootfs-overlay/      # Files to copy to rootfs
│   ├── common/
│   └── [board-name]/
└── scripts/             # Board-specific setup scripts
```

## Board Configuration Files

Each board has a `.conf` file that defines:

- Board name and SoC type
- Repository URLs for U-Boot and kernel
- Branch/tag to use
- Defconfig and DTB files
- Rootfs settings (Debian release, hostname, credentials)
- Image size parameters
- Extra packages to install

### Example: `rock-3a.conf`

```bash
BOARD_NAME="Radxa Rock 3A"
SOC="RK3568"
UBOOT_REPO="https://github.com/radxa/u-boot.git"
UBOOT_BRANCH="stable-4.19-rock3"
KERNEL_REPO="https://github.com/radxa/kernel.git"
KERNEL_BRANCH="stable-4.19-rock3"
DTB_FILE="rk3568-rock-3a.dtb"
```

## Adding a New Board

1. Create a new config file: `config/boards/myboard.conf`
2. Define all required variables (use existing configs as template)
3. Optionally create custom overlays in `config/rootfs-overlay/myboard/`
4. Optionally add patches in `config/patches/kernel/myboard/` or `config/patches/u-boot/myboard/`
5. Build: `./scripts/assemble-image.sh myboard`

## Kernel Config Fragments

Place kernel configuration fragments in `config/kernel/[board].config`:

```
CONFIG_MY_DRIVER=y
CONFIG_ANOTHER_OPTION=m
# CONFIG_DISABLED_FEATURE is not set
```

These will be merged with the base defconfig during build.

## U-Boot Config Fragments

Similar to kernel configs, place U-Boot fragments in `config/u-boot/[board].config`.

## Patches

Patches are applied in alphabetical order:

```
config/patches/kernel/rock-3a/
├── 0001-add-new-feature.patch
├── 0002-fix-bug.patch
└── 0003-enable-hardware.patch
```

## Rootfs Overlay

Files in these directories are copied directly to the rootfs:

- `common/` - Applied to all boards
- `[board-name]/` - Board-specific files

Example structure:
```
config/rootfs-overlay/
├── common/
│   └── etc/
│       └── motd
└── rock-3a/
    └── etc/
        └── network/
            └── interfaces
```

## Board-Specific Setup Scripts

Create `config/scripts/[board]-setup.sh` for custom post-install tasks:

```bash
#!/bin/bash
# This runs inside the chroot during rootfs build

# Example: Install board-specific packages
apt-get install -y custom-package

# Example: Configure hardware
echo "options module_name param=value" > /etc/modprobe.d/custom.conf
```

Make it executable: `chmod +x config/scripts/[board]-setup.sh`
