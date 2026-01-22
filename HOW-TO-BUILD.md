# How to Build

## Quick Start

```bash
# Clone with submodules (vendor blobs required)
git clone --recursive https://github.com/aaronsb/rk356x.git
cd rk356x

# Interactive build (recommended for first time)
./scripts/build.sh sz3568-v1.2

# Auto mode: build what's missing, flash to SD card
./scripts/build.sh --auto --device /dev/sdX sz3568-v1.2
```

## Available Boards

| Board | Name | Description |
|-------|------|-------------|
| `sz3568-v1.2` | SZ3568 V1.2 | RGMII ethernet with MAXIO PHY |
| `dc-a568-v06` | DC-A568 V06 | RMII ethernet |

Board configurations are defined in `boards/*/board.conf`.

## Standalone Scripts

Each script follows the pattern: `<script> <board> <command>`

### Kernel

```bash
./scripts/build/kernel.sh sz3568-v1.2 build   # Build kernel
./scripts/build/kernel.sh sz3568-v1.2 clean   # Clean artifacts
./scripts/build/kernel.sh sz3568-v1.2 info    # Show status
```

Output: `output/kernel-debs/*.deb`

### Rootfs

```bash
./scripts/build/rootfs.sh sz3568-v1.2 build                    # Minimal profile
./scripts/build/rootfs.sh --profile full sz3568-v1.2 build     # Full profile
./scripts/build/rootfs.sh sz3568-v1.2 clean                    # Clean (keeps cache)
./scripts/build/rootfs.sh sz3568-v1.2 info                     # Show status
```

Output: `rootfs/debian-rootfs.img`

Profiles:
- `minimal` - Sway, systemd-networkd, IWD, Firefox/Chromium
- `full` - Above + NetworkManager, GStreamer, dev tools

### U-Boot (optional)

```bash
./scripts/build/uboot.sh sz3568-v1.2 build    # Build U-Boot
./scripts/build/uboot.sh sz3568-v1.2 clean    # Clean
./scripts/build/uboot.sh sz3568-v1.2 info     # Show status
```

Output: `output/uboot/u-boot-rockchip.bin`

### Image Assembly

```bash
sudo ./scripts/device/assemble.sh sz3568-v1.2 build              # Without U-Boot
sudo ./scripts/device/assemble.sh --with-uboot sz3568-v1.2 build # With U-Boot
./scripts/device/assemble.sh sz3568-v1.2 info                    # Show status
```

Output: `output/rk3568-debian-YYYYMMDDHHMM.img` (+ .xz compressed)

### Flash to SD Card

```bash
sudo ./scripts/device/flash-sd.sh sz3568-v1.2 flash              # Auto-detect device
sudo ./scripts/device/flash-sd.sh --device /dev/sdX sz3568-v1.2 flash
./scripts/device/flash-sd.sh sz3568-v1.2 info                    # Show available images
```

### Flash to eMMC (maskrom mode)

```bash
sudo ./scripts/device/flash-emmc.sh --latest    # Flash most recent image
sudo ./scripts/device/flash-emmc.sh image.img   # Flash specific image
```

## Orchestrator Options

The orchestrator (`scripts/build.sh`) provides convenience options:

```bash
# Build modes
./scripts/build.sh sz3568-v1.2                    # Interactive (asks at each stage)
./scripts/build.sh --auto sz3568-v1.2             # Auto (skip existing artifacts)
./scripts/build.sh --non-interactive sz3568-v1.2  # Rebuild all, no prompts

# Single stage
./scripts/build.sh --kernel-only sz3568-v1.2
./scripts/build.sh --rootfs-only sz3568-v1.2
./scripts/build.sh --uboot-only sz3568-v1.2
./scripts/build.sh --image-only sz3568-v1.2

# With options
./scripts/build.sh --with-uboot sz3568-v1.2       # Include U-Boot in image
./scripts/build.sh --device /dev/sdX sz3568-v1.2  # Specify SD card device
./scripts/build.sh --clean sz3568-v1.2            # Clean all before building

# Combined
./scripts/build.sh --auto --device /dev/sdb sz3568-v1.2
```

## Typical Workflows

### First-time full build

```bash
./scripts/build.sh sz3568-v1.2
```

Follow prompts for each stage.

### Rebuild kernel only, then reassemble

```bash
./scripts/build/kernel.sh sz3568-v1.2 build
sudo ./scripts/device/assemble.sh sz3568-v1.2 build
sudo ./scripts/device/flash-sd.sh sz3568-v1.2 flash
```

### Quick iteration (use existing artifacts)

```bash
./scripts/build.sh --auto --device /dev/sdb sz3568-v1.2
```

### Clean rebuild

```bash
./scripts/build.sh --clean sz3568-v1.2
```

## Default Credentials

- User: `rock` / `rock`
- Root: `root` / `root`
- Desktop user: `user` / `user` (auto-login to Sway)

## Build Artifacts

```
output/
├── kernel-debs/                    # Kernel .deb packages
│   ├── linux-image-*.deb
│   └── linux-headers-*.deb
├── uboot/                          # U-Boot binaries (if built)
│   └── u-boot-rockchip.bin
└── rk3568-debian-*.img             # Final images
    └── rk3568-debian-*.img.xz      # Compressed

rootfs/
├── debian-rootfs.img               # Rootfs image
└── debootstrap-*.tar.gz            # Cached debootstrap (speeds up rebuilds)
```

## Prerequisites

**Docker (recommended):**
```bash
sudo apt install docker.io
sudo usermod -aG docker $USER
# Log out and back in
```

**Native build (if not using Docker):**
```bash
sudo apt install \
    qemu-user-static debootstrap wget \
    git make gcc g++ bison flex libssl-dev libelf-dev bc kmod debhelper \
    gcc-aarch64-linux-gnu
```

## More Information

- [CLAUDE.md](CLAUDE.md) - Technical context and debugging tips
- [docs/adr/](docs/adr/) - Architecture Decision Records
- [docs/](docs/) - Additional documentation
