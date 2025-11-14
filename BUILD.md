# RK356X Build System

Automated build system for creating Debian-based images for RK356X (RK3566/RK3568) development boards.

## Features

- **Automated CI/CD** with GitHub Actions
- **Multiple board support** (Rock 3A, Quartz64, NanoPi R5S, etc.)
- **Modular build system** (U-Boot, Kernel, Rootfs can be built independently)
- **Customizable** with board-specific configurations
- **Ready-to-flash images** with proper partition layout

## Quick Start

### Prerequisites

On Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install -y \
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    build-essential \
    libssl-dev \
    libncurses-dev \
    flex \
    bison \
    bc \
    kmod \
    cpio \
    rsync \
    debootstrap \
    qemu-user-static \
    binfmt-support \
    device-tree-compiler \
    python3 \
    python3-setuptools \
    swig \
    u-boot-tools \
    parted \
    dosfstools \
    e2fsprogs \
    git \
    wget \
    pixz
```

### Building a Complete Image

```bash
# Clone this repository
git clone https://github.com/yourusername/rk356x.git
cd rk356x

# Make scripts executable
chmod +x scripts/*.sh

# Build for Rock 3A (or any supported board)
./scripts/build-uboot.sh rock-3a
sudo ./scripts/build-kernel.sh rock-3a
sudo ./scripts/build-rootfs.sh rock-3a
sudo ./scripts/assemble-image.sh rock-3a
```

The final image will be in `output/rock-3a-debian-YYYYMMDD.img.xz`

### Flashing the Image

```bash
# Decompress
xz -d output/rock-3a-debian-YYYYMMDD.img.xz

# Flash to SD card (replace /dev/sdX with your device)
sudo dd if=output/rock-3a-debian-YYYYMMDD.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Or use [balenaEtcher](https://www.balena.io/etcher/) for a GUI option.

## Supported Boards

| Board | SoC | Config | Status |
|-------|-----|--------|--------|
| Radxa Rock 3A | RK3568 | `rock-3a` | ✅ Tested |
| Pine64 Quartz64-A | RK3566 | `quartz64-a` | ✅ Tested |
| FriendlyELEC NanoPi R5S | RK3568 | `nanopi-r5s` | ✅ Tested |
| Firefly Station M2 | RK3566 | `station-m2` | ⚠️ Untested |
| Generic RK3568 EVB | RK3568 | `evb-rk3568` | ⚠️ Untested |

## Build Scripts

### Individual Components

Build only specific components:

```bash
# Build U-Boot only
./scripts/build-uboot.sh rock-3a

# Build Kernel only
sudo ./scripts/build-kernel.sh rock-3a

# Build Rootfs only
sudo ./scripts/build-rootfs.sh rock-3a
```

### Full Image Assembly

```bash
# Assemble everything into a flashable image
sudo ./scripts/assemble-image.sh rock-3a
```

This requires that U-Boot, kernel, and rootfs have already been built.

## Directory Structure

```
rk356x/
├── .github/
│   └── workflows/
│       └── build-image.yml      # GitHub Actions workflow
├── scripts/
│   ├── build-uboot.sh           # Build U-Boot bootloader
│   ├── build-kernel.sh          # Build Linux kernel
│   ├── build-rootfs.sh          # Create Debian rootfs
│   └── assemble-image.sh        # Assemble final image
├── config/
│   ├── boards/                  # Board configurations
│   ├── kernel/                  # Kernel config fragments
│   ├── u-boot/                  # U-Boot config fragments
│   ├── patches/                 # Patches
│   ├── rootfs-overlay/          # Custom rootfs files
│   └── scripts/                 # Board-specific setup
├── build/                       # Build artifacts (gitignored)
├── output/                      # Final outputs (gitignored)
├── BUILD.md                     # This file
└── README.md                    # Project overview
```

## GitHub Actions

The repository includes automated builds via GitHub Actions.

### Manual Trigger

Go to Actions → Build RK356X Image → Run workflow

Select:
- Board: `rock-3a`, `quartz64-a`, etc.
- Build type: `full`, `uboot-only`, `kernel-only`, or `rootfs-only`

### Automatic Builds

Builds trigger automatically on:
- Push to `main` or `develop` branches
- Pull requests to `main`

### Artifacts

Built images are available as workflow artifacts for 30 days.

### Releases

Tag a commit to create a release:
```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

The workflow will automatically create a GitHub release with the built image.

## Customization

### Adding a New Board

1. Create board config: `config/boards/myboard.conf`
2. Set all required variables (see existing configs)
3. Add to GitHub Actions workflow (optional)
4. Build: `./scripts/assemble-image.sh myboard`

See [config/README.md](config/README.md) for details.

### Custom Kernel Configuration

Create `config/kernel/myboard.config`:
```
CONFIG_MY_DRIVER=y
CONFIG_ANOTHER_OPTION=m
```

This will be merged with the base defconfig.

### Custom Rootfs Files

Add files to:
- `config/rootfs-overlay/common/` - All boards
- `config/rootfs-overlay/myboard/` - Specific board

Files are copied directly to the rootfs.

### Applying Patches

Place patches in:
- `config/patches/kernel/myboard/*.patch`
- `config/patches/u-boot/myboard/*.patch`

Patches are applied alphabetically.

### Post-Install Scripts

Create `config/scripts/myboard-setup.sh` for custom setup:
```bash
#!/bin/bash
# Runs inside chroot during rootfs build

apt-get install -y my-package
systemctl enable my-service
```

Make it executable: `chmod +x config/scripts/myboard-setup.sh`

## Image Layout

The generated image has the following partition layout:

```
Offset      | Size     | Content
------------|----------|---------------------------
0 KB        | 32 KB    | Reserved
32 KB       | ~8 MB    | idbloader.img (TPL + SPL)
8 MB        | ~8 MB    | u-boot.itb (U-Boot + ATF)
16 MB       | 256 MB   | Boot partition (ext4)
272 MB      | Rest     | Root partition (ext4)
```

### Boot Partition

Contains:
- `/Image` - Linux kernel
- `/dtbs/rockchip/*.dtb` - Device trees
- `/boot.scr` - U-Boot script
- `/extlinux/extlinux.conf` - Extlinux config

### Root Partition

Standard Debian filesystem with:
- Kernel modules
- Systemd init
- NetworkManager
- OpenSSH server
- Basic utilities

## Default Credentials

**Username:** Varies by board (see config files)
- Rock 3A: `rock` / `rock`
- Quartz64: `pine64` / `pine64`
- NanoPi R5S: `pi` / `pi`
- Others: `debian` / `debian`

**Root password:** Same as user password

⚠️ **Change these immediately after first boot!**

```bash
passwd              # Change user password
sudo passwd root    # Change root password
```

## Network Configuration

The system uses NetworkManager for network management.

### Wired (Ethernet)

DHCP is configured by default. Just plug in the cable.

### Wireless

```bash
# TUI interface
nmtui

# Or command line
nmcli device wifi list
nmcli device wifi connect "SSID" password "PASSWORD"
```

### Static IP

```bash
nmtui
# Navigate to: Edit a connection → Select interface → IPv4 Configuration → Manual
```

Or edit `/etc/systemd/network/20-wired.network`:
```ini
[Match]
Name=eth0

[Network]
Address=192.168.1.100/24
Gateway=192.168.1.1
DNS=8.8.8.8
```

## Serial Console

RK356X boards typically use UART2 (ttyS2) at 1500000 baud.

### Connection

```bash
# Linux
sudo screen /dev/ttyUSB0 1500000

# Or use minicom
sudo minicom -D /dev/ttyUSB0 -b 1500000
```

### Hardware

Connect a USB-TTL adapter:
- TX → RX
- RX → TX
- GND → GND

Pin locations vary by board - check your board's documentation.

## Troubleshooting

### Build Issues

**Error: "Cannot find cross compiler"**
```bash
sudo apt-get install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
```

**Error: "debootstrap: command not found"**
```bash
sudo apt-get install debootstrap qemu-user-static binfmt-support
```

**Error: "mkimage: command not found"**
```bash
sudo apt-get install u-boot-tools
```

### Boot Issues

**Board doesn't boot**
1. Check U-Boot on serial console
2. Verify correct image for your board
3. Ensure SD card is properly flashed
4. Try re-flashing with different tool

**Kernel panic**
1. Check device tree matches your board
2. Verify kernel has required drivers
3. Check rootfs is valid

**No display output**
1. Check serial console first
2. Try different DTB file
3. Some boards need HDMI plugged in before power-on

**No network**
1. Check cable and link lights
2. Try: `sudo systemctl restart NetworkManager`
3. Check: `ip addr` and `ip route`
4. For WiFi, check if firmware is loaded: `dmesg | grep firmware`

### GitHub Actions Issues

**Build times out**
- Increase timeout in workflow (default: 6 hours)
- Use artifact caching more aggressively

**Out of disk space**
- Free disk space step is included in workflow
- Consider reducing image size in config

**Artifacts too large**
- Images are compressed with pixz
- Only .xz files are uploaded as artifacts

## Performance Tips

### Speed Up Builds

**Use ccache for kernel builds:**
```bash
sudo apt-get install ccache
export PATH="/usr/lib/ccache:$PATH"
./scripts/build-kernel.sh rock-3a
```

**Use local mirror for debootstrap:**
```bash
# Edit config/boards/myboard.conf
DEBIAN_MIRROR="http://your-local-mirror/debian"
```

**Parallel builds:**
The scripts use `-j$(nproc)` by default. You can limit this:
```bash
export MAKEFLAGS="-j4"
```

### Reduce Image Size

Edit `config/boards/myboard.conf`:
```bash
IMAGE_SIZE=2048  # Smaller total size
BOOT_SIZE=128    # Smaller boot partition
```

Remove unnecessary packages from rootfs build script.

## Contributing

Contributions welcome! Please:

1. Test your changes on real hardware
2. Update documentation
3. Follow existing code style
4. Add new boards with proper configs

## License

This build system is provided as-is. Individual components (U-Boot, Linux, Debian) have their own licenses.

## Resources

- [Rockchip Wiki](http://opensource.rock-chips.com/wiki_Main_Page)
- [Linux Rockchip Mailing List](http://lists.infradead.org/mailman/listinfo/linux-rockchip)
- [Armbian Documentation](https://docs.armbian.com/)
- [U-Boot Documentation](https://u-boot.readthedocs.io/)
- [Kernel Documentation](https://www.kernel.org/doc/html/latest/)

## Support

- Open an issue on GitHub
- Check existing issues for solutions
- Consult board-specific forums and wikis
