#!/bin/bash
# Standalone SD card flashing script
# Flashes bootable image to SD card

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <board> <command>

Flash bootable image to SD card.

Commands:
  flash       Flash image to SD card
  list        List available SD cards
  info        Show latest image and device info

Options:
  --device /dev/sdX   Target device (auto-detected if single card)
  --with-uboot        Also flash U-Boot to bootloader area
  --yes               Skip confirmation prompt
  -h, --help          Show this help

Boards:
$(list_boards | sed 's/^/  /')

Examples:
  sudo $(basename "$0") sz3568-v1.2 list
  sudo $(basename "$0") sz3568-v1.2 flash
  sudo $(basename "$0") --device /dev/sdb sz3568-v1.2 flash
  sudo $(basename "$0") --with-uboot --device /dev/sdb sz3568-v1.2 flash

WARNING: Flashing will ERASE ALL DATA on the target device!
EOF
}

# ============================================================================
# SD Card Functions
# ============================================================================

detect_sd_cards() {
    # List removable block devices (likely SD cards)
    lsblk -d -n -o NAME,SIZE,TYPE,TRAN,HOTPLUG,MODEL 2>/dev/null | \
        awk '$3=="disk" && ($4=="usb" || $5=="1")' | \
        awk '{print "/dev/"$1}'
}

verify_sd_device() {
    local device="$1"

    [[ -n "$device" ]] || return 1
    [[ -b "$device" ]] || error "Device $device is not a block device"

    local dev_name=$(basename "$device")
    local removable=$(cat /sys/block/${dev_name}/removable 2>/dev/null || echo "0")

    if [[ "$removable" != "1" ]]; then
        warn "Device $device does not appear to be removable!"
        warn "This could be your system disk!"

        if [[ "$YES_MODE" != "true" ]]; then
            echo ""
            read -p "Continue anyway? (DANGEROUS) [y/N]: " -r
            [[ $REPLY =~ ^[Yy]$ ]] || exit 1
        fi
    fi

    local size=$(lsblk -d -n -o SIZE "$device" 2>/dev/null)
    local model=$(lsblk -d -n -o MODEL "$device" 2>/dev/null)

    # Check for no medium (0B size means card reader present but no card)
    if [[ "$size" == "0B" ]] || [[ -z "$size" ]]; then
        error "No medium found in $device. Insert an SD card and try again."
    fi

    info "Device: $device"
    info "Size:   $size"
    info "Model:  $model"
}

find_latest_image() {
    ls -1t "${OUTPUT_DIR}"/rk3568-debian-*.img 2>/dev/null | grep -v '\.xz$' | head -1
}

flash_image() {
    local image="$1"
    local device="$2"

    [[ -f "$image" ]] || error "Image file not found: $image"

    # Unmount any mounted partitions
    info "Unmounting any mounted partitions on $device..."
    sudo umount ${device}* 2>/dev/null || true

    # Confirmation
    if [[ "$YES_MODE" != "true" ]]; then
        warn "About to write to $device - ALL DATA WILL BE LOST!"
        echo ""
        read -p "Type 'YES' to confirm: " confirm
        [[ "$confirm" == "YES" ]] || error "Flash cancelled"
    fi

    # Flash
    info "Flashing $(basename "$image") to $device..."
    info "This will take several minutes..."

    if [[ -f "${image}.xz" ]]; then
        info "Using compressed image: $(basename "${image}.xz")"
        sudo xz -dc "${image}.xz" | sudo dd of="$device" bs=4M status=progress conv=fsync
    else
        sudo dd if="$image" of="$device" bs=4M status=progress conv=fsync
    fi

    # Flash U-Boot if requested
    if [[ "$WITH_UBOOT" == "true" ]]; then
        local uboot_bin="${OUTPUT_DIR}/uboot/u-boot-rockchip.bin"
        if [[ -f "$uboot_bin" ]]; then
            echo ""
            info "Flashing U-Boot to $device..."
            sudo dd if="$uboot_bin" of="$device" seek=64 bs=512 conv=fsync status=none
            log "U-Boot flashed to sector 64"
        else
            warn "U-Boot binary not found: $uboot_bin"
            warn "Skipping U-Boot flash"
        fi
    fi

    sudo sync
    log "Flash complete! $device is ready to boot."
}

# ============================================================================
# Commands
# ============================================================================

cmd_flash() {
    header "Flashing Image to SD Card"

    # Require root
    [[ $EUID -eq 0 ]] || error "Flashing requires root. Run with: sudo $(basename "$0") ..."

    # Find image
    local image
    image=$(find_latest_image)
    [[ -n "$image" ]] || error "No image found in output/. Run: ./scripts/device/assemble.sh $BOARD_NAME build"

    info "Image: $(basename "$image")"
    info "Size:  $(du -h "$image" | cut -f1)"

    # Find device
    if [[ -z "$DEVICE" ]]; then
        local sd_cards
        mapfile -t sd_cards < <(detect_sd_cards)

        if [[ ${#sd_cards[@]} -eq 0 ]]; then
            error "No removable SD cards detected. Use --device /dev/sdX"
        elif [[ ${#sd_cards[@]} -eq 1 ]]; then
            DEVICE="${sd_cards[0]}"
            info "Auto-detected SD card: $DEVICE"
        else
            warn "Multiple SD cards detected:"
            for card in "${sd_cards[@]}"; do
                echo "  - $card ($(lsblk -d -n -o SIZE,MODEL "$card" 2>/dev/null))"
            done
            error "Use --device /dev/sdX to specify"
        fi
    fi

    verify_sd_device "$DEVICE"
    echo ""
    flash_image "$image" "$DEVICE"
}

cmd_list() {
    header "Available SD Cards"

    local sd_cards
    mapfile -t sd_cards < <(detect_sd_cards)

    if [[ ${#sd_cards[@]} -eq 0 ]]; then
        warn "No removable SD cards detected"
        info "Insert an SD card and try again"
    else
        for card in "${sd_cards[@]}"; do
            local size=$(lsblk -d -n -o SIZE "$card" 2>/dev/null)
            local model=$(lsblk -d -n -o MODEL "$card" 2>/dev/null)
            echo "  $card  ${size}  ${model}"
        done
    fi
}

cmd_info() {
    header "Flash Information"

    show_board_info

    echo ""
    info "Latest Image:"
    local image
    image=$(find_latest_image)
    if [[ -n "$image" ]]; then
        kv "File" "$(basename "$image")"
        kv "Size" "$(du -h "$image" | cut -f1)"
        kv "Date" "$(stat -c %y "$image" | cut -d' ' -f1,2 | cut -d'.' -f1)"
        [[ -f "${image}.xz" ]] && kv "Compressed" "$(du -h "${image}.xz" | cut -f1)"
    else
        warn "No image found in output/"
    fi

    echo ""
    info "SD Cards:"
    cmd_list 2>/dev/null | grep -v "━━━" || true
}

# ============================================================================
# Main
# ============================================================================

main() {
    local board=""
    local command=""
    DEVICE=""
    WITH_UBOOT=false
    YES_MODE=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --device)
                DEVICE="$2"
                shift 2
                ;;
            --with-uboot)
                WITH_UBOOT=true
                shift
                ;;
            --yes|-y)
                YES_MODE=true
                shift
                ;;
            -*)
                error "Unknown option: $1"
                ;;
            *)
                if [[ -z "$board" ]]; then
                    board="$1"
                elif [[ -z "$command" ]]; then
                    command="$1"
                else
                    error "Too many arguments"
                fi
                shift
                ;;
        esac
    done

    # Require board and command
    if [[ -z "$board" ]] || [[ -z "$command" ]]; then
        usage
        exit 1
    fi

    # Load board configuration
    load_board "$board" || exit 1

    # Execute command
    case "$command" in
        flash) cmd_flash ;;
        list)  cmd_list ;;
        info)  cmd_info ;;
        *)     error "Unknown command: $command" ;;
    esac
}

main "$@"
