# Board Configurations

This directory contains per-board configurations for different RK356x hardware.

## Directory Structure

```
boards/
└── <board-name>/
    ├── board.conf       # Board variables (DTB, console, partitions)
    ├── uboot.config     # U-Boot config fragment
    ├── dtb/             # Device trees for this board
    └── README.md        # Board documentation
```

## Usage

### Build SD Card for Provisioning

```bash
./scripts/build-sd-image.sh <board-name> /dev/sdX
```

### Provision a Board

1. Insert SD card into board
2. Boot from SD card
3. Login as root (password: root)
4. Run: `setup-emmc`
5. Remove SD card and reboot

## Adding a New Board

1. Create directory: `boards/<board-name>/`
2. Create `board.conf` with board variables
3. Add U-Boot config fragment if needed
4. Add device tree if custom
5. Document in README.md

## Available Boards

- **dc-a568-v06** - Dingchang DC-A568-V06 RK3568
