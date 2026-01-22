#!/bin/bash
# Standalone image assembly script
# Assembles kernel, rootfs, and optionally U-Boot into bootable image

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Configuration
IMAGE_SIZE="6144"  # 6GB total
BOOT_SIZE="256"    # 256MB boot partition
KERNEL_VERSION="${KERNEL_VERSION:-6.12}"

# Runtime state
LOOP_DEV=""
WORK_DIR=""
IMAGE_FILE=""
IMAGE_NAME=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <board> <command>

Assemble bootable Debian image for RK3568 boards.

Commands:
  build       Assemble the image
  clean       Remove image work files
  info        Show configuration and artifact status

Options:
  --with-uboot    Include U-Boot in image
  -h, --help      Show this help

Boards:
$(list_boards | sed 's/^/  /')

Examples:
  sudo $(basename "$0") sz3568-v1.2 build
  sudo $(basename "$0") --with-uboot sz3568-v1.2 build
  $(basename "$0") sz3568-v1.2 info

Output:
  output/rk3568-debian-YYYYMMDDHHMM.img      Raw image (6GB)
  output/rk3568-debian-YYYYMMDDHHMM.img.xz   Compressed (~400MB)
EOF
}

# ============================================================================
# Dependencies
# ============================================================================

check_deps() {
    local deps=(parted losetup mkfs.ext4 e2fsck xz mkimage)
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}

Install with:
  Ubuntu/Debian: sudo apt install parted e2fsprogs xz-utils u-boot-tools
  Arch Linux:    sudo pacman -S parted e2fsprogs xz uboot-tools"
    fi
}

# ============================================================================
# Image Creation
# ============================================================================

create_image_file() {
    info "Creating ${IMAGE_SIZE}MB disk image..."

    IMAGE_NAME="rk3568-debian-$(date +%Y%m%d%H%M)"
    IMAGE_FILE="${OUTPUT_DIR}/${IMAGE_NAME}.img"
    WORK_DIR="${OUTPUT_DIR}/image-work"

    mkdir -p "${WORK_DIR}"

    # Create sparse file
    dd if=/dev/zero of="${IMAGE_FILE}" bs=1M count=0 seek="${IMAGE_SIZE}" status=none

    log "Created ${IMAGE_FILE}"
}

partition_image() {
    local boot_start boot_end rootfs_start

    if [[ "$WITH_UBOOT" == "true" ]]; then
        # With U-Boot: Reserve space for bootloader at sector 64
        boot_start=32768  # 16MB in sectors
        info "Partition layout (with U-Boot):"
        info "  Reserved:  0 - 16MB (bootloader)"
        info "  Boot:      16MB - $((16 + BOOT_SIZE))MB"
    else
        # Without U-Boot: Standard GPT start
        boot_start=2048   # 1MB in sectors
        info "Partition layout:"
        info "  Boot:      1MB - $((1 + BOOT_SIZE))MB"
    fi

    boot_end=$((boot_start + BOOT_SIZE * 2048))
    rootfs_start=$((boot_end + 1))

    info "  Rootfs:    after boot - ${IMAGE_SIZE}MB"

    # Create GPT partition table
    parted -s "${IMAGE_FILE}" mklabel gpt
    parted -s "${IMAGE_FILE}" mkpart primary ext4 ${boot_start}s ${boot_end}s
    parted -s "${IMAGE_FILE}" mkpart primary ext4 ${rootfs_start}s 100%
    parted -s "${IMAGE_FILE}" set 1 legacy_boot on
    parted -s "${IMAGE_FILE}" set 1 boot on

    log "Partitions created"
}

flash_bootloader() {
    [[ "$WITH_UBOOT" == "true" ]] || return 0

    local uboot_bin="${OUTPUT_DIR}/uboot/u-boot-rockchip.bin"

    [[ -f "$uboot_bin" ]] || error "U-Boot binary not found: $uboot_bin
Run: ./scripts/build/uboot.sh $BOARD_NAME build"

    warn "Flashing U-Boot to image..."
    dd if="$uboot_bin" of="${IMAGE_FILE}" seek=64 conv=notrunc,fsync status=none

    log "U-Boot flashed at sector 64"
}

setup_loop_device() {
    info "Setting up loop device..."

    LOOP_DEV=$(losetup -f)
    losetup -P "${LOOP_DEV}" "${IMAGE_FILE}"

    # Wait for partition devices
    sleep 2

    BOOT_PART="${LOOP_DEV}p1"
    ROOT_PART="${LOOP_DEV}p2"

    if [[ ! -b "${BOOT_PART}" ]] || [[ ! -b "${ROOT_PART}" ]]; then
        error "Partition devices not created. Try: sudo partprobe ${LOOP_DEV}"
    fi

    log "Loop device: ${LOOP_DEV}"
}

format_partitions() {
    info "Formatting partitions..."

    mkfs.ext4 -F -L "BOOT" "${BOOT_PART}" >/dev/null
    mkfs.ext4 -F -L "ROOTFS" "${ROOT_PART}" >/dev/null

    log "Partitions formatted"
}

install_boot_files() {
    info "Installing boot files..."

    local kernel_dir="${PROJECT_ROOT}/kernel-${KERNEL_VERSION}"
    local dtb_name="${BOARD_DTB%.dtb}"  # Remove .dtb if present

    # Mount boot partition
    mkdir -p "${WORK_DIR}/boot"
    mount "${BOOT_PART}" "${WORK_DIR}/boot"

    # Copy kernel
    cp "${kernel_dir}/arch/arm64/boot/Image" "${WORK_DIR}/boot/"
    log "Kernel installed"

    # Copy DTB
    mkdir -p "${WORK_DIR}/boot/dtbs/rockchip"
    cp "${kernel_dir}/arch/arm64/boot/dts/rockchip/${dtb_name}.dtb" \
        "${WORK_DIR}/boot/dtbs/rockchip/"
    cp "${kernel_dir}/arch/arm64/boot/dts/rockchip/${dtb_name}.dtb" \
        "${WORK_DIR}/boot/"
    log "Device tree installed: ${dtb_name}.dtb"

    # Get root partition PARTUUID
    local root_partuuid
    root_partuuid=$(blkid -s PARTUUID -o value "${ROOT_PART}")

    # Create boot script
    cat > "${WORK_DIR}/boot/boot.cmd" << EOF
# U-Boot boot script for Debian RK3568
echo "=== Debian RK3568 Boot Script ==="

# Clear existing bootargs
setenv bootargs

# Set bootargs with root PARTUUID
setenv bootargs "root=PARTUUID=${root_partuuid} rootwait rw console=ttyS2,1500000 earlycon=uart8250,mmio32,0xfe660000 clk_ignore_unused video=HDMI-A-1:1920x1080@60e"

# Load kernel and DTB
load \${devtype} \${devnum}:\${distro_bootpart} \${kernel_addr_r} /Image
load \${devtype} \${devnum}:\${distro_bootpart} \${fdt_addr_r} /dtbs/rockchip/${dtb_name}.dtb

# Boot
booti \${kernel_addr_r} - \${fdt_addr_r}
EOF

    mkimage -C none -A arm -T script -d "${WORK_DIR}/boot/boot.cmd" \
        "${WORK_DIR}/boot/boot.scr.uimg" >/dev/null

    log "Boot script created"

    sync
    umount "${WORK_DIR}/boot"
}

install_rootfs() {
    info "Installing rootfs (this takes a minute)..."

    local rootfs_img="${PROJECT_ROOT}/rootfs/debian-rootfs.img"
    local kernel_dir="${PROJECT_ROOT}/kernel-${KERNEL_VERSION}"

    # Mount root partition
    mkdir -p "${WORK_DIR}/root"
    mount "${ROOT_PART}" "${WORK_DIR}/root"

    # Mount rootfs source image
    mkdir -p "${WORK_DIR}/rootfs-src"
    local rootfs_loop
    rootfs_loop=$(losetup -f)
    losetup "${rootfs_loop}" "${rootfs_img}"
    mount "${rootfs_loop}" "${WORK_DIR}/rootfs-src"

    # Copy rootfs contents
    cp -a "${WORK_DIR}/rootfs-src"/* "${WORK_DIR}/root/"

    # Create boot mount point
    mkdir -p "${WORK_DIR}/root/boot"

    # Create fstab
    cat > "${WORK_DIR}/root/etc/fstab" << 'EOF'
# <file system> <mount point> <type> <options> <dump> <pass>
LABEL=ROOTFS    /               ext4    defaults,noatime    0   1
LABEL=BOOT      /boot           ext4    defaults,noatime    0   2
tmpfs           /tmp            tmpfs   defaults,nosuid     0   0
EOF

    # Create release info
    local kernel_release
    kernel_release=$(cat "${kernel_dir}/include/config/kernel.release" 2>/dev/null || echo "${KERNEL_VERSION}-rockchip")

    cat > "${WORK_DIR}/root/etc/rk3568-release" << EOF
BOARD=${BOARD_NAME}
BOARD_DESC=${BOARD_DESCRIPTION:-$BOARD_NAME}
DTB=${BOARD_DTB}
BUILD_DATE=$(date)
KERNEL_VERSION=${kernel_release}
IMAGE_VERSION=${IMAGE_NAME}
EOF

    # Install kernel modules from .deb
    local kernel_deb
    kernel_deb=$(ls -1t "${OUTPUT_DIR}/kernel-debs"/linux-image-*.deb 2>/dev/null | grep -v '\-dbg' | head -1)

    if [[ -n "$kernel_deb" ]] && [[ -f "$kernel_deb" ]]; then
        info "Installing kernel modules from $(basename "$kernel_deb")..."
        local tmp_extract
        tmp_extract=$(mktemp -d)

        ar -x "$kernel_deb" --output="$tmp_extract"

        if [[ -f "$tmp_extract/data.tar.zst" ]]; then
            zstd -d "$tmp_extract/data.tar.zst" -c | tar -xf - -C "$tmp_extract" ./lib/modules 2>/dev/null || true
        elif [[ -f "$tmp_extract/data.tar.xz" ]]; then
            tar -xJf "$tmp_extract/data.tar.xz" -C "$tmp_extract" ./lib/modules 2>/dev/null || true
        fi

        if [[ -d "$tmp_extract/lib/modules" ]]; then
            mkdir -p "${WORK_DIR}/root/lib/modules"
            cp -a "$tmp_extract/lib/modules"/* "${WORK_DIR}/root/lib/modules/"
            log "Kernel modules installed"
        else
            warn "Could not extract modules from deb"
        fi

        rm -rf "$tmp_extract"
    else
        warn "No kernel .deb found - modules not installed"
    fi

    # Cleanup
    sync
    umount "${WORK_DIR}/rootfs-src"
    losetup -d "${rootfs_loop}"
    umount "${WORK_DIR}/root"

    log "Rootfs installed"
}

cleanup_loop_device() {
    sync
    sleep 1

    umount "${WORK_DIR}/boot" 2>/dev/null || true
    umount "${WORK_DIR}/root" 2>/dev/null || true
    umount "${WORK_DIR}/rootfs-src" 2>/dev/null || true

    [[ -n "$LOOP_DEV" ]] && losetup -d "${LOOP_DEV}" 2>/dev/null || true

    rm -rf "${WORK_DIR}"
}

compress_image() {
    info "Compressing image (this takes a few minutes)..."

    xz -T0 -9 -k "${IMAGE_FILE}"

    log "Compressed to ${IMAGE_NAME}.img.xz"
}

calculate_checksums() {
    info "Creating checksums..."

    cd "${OUTPUT_DIR}"
    sha256sum "${IMAGE_NAME}.img" > "${IMAGE_NAME}.img.sha256"
    sha256sum "${IMAGE_NAME}.img.xz" > "${IMAGE_NAME}.img.xz.sha256"
    cd "${PROJECT_ROOT}"

    log "Checksums created"
}

show_build_summary() {
    local raw_size compressed_size

    raw_size=$(du -h "${IMAGE_FILE}" | cut -f1)
    compressed_size=$(du -h "${IMAGE_FILE}.xz" | cut -f1)

    echo ""
    log "════════════════════════════════════════════════════════════"
    log "  Image Assembly Complete!"
    log "════════════════════════════════════════════════════════════"
    echo ""
    kv "Board" "${BOARD_DESCRIPTION:-$BOARD_NAME}"
    kv "DTB" "${BOARD_DTB}"
    kv "Image" "${IMAGE_FILE}"
    kv "Size" "${raw_size} (${compressed_size} compressed)"
    echo ""
    info "To flash:"
    echo "  sudo ./scripts/device/flash-sd.sh ${BOARD_NAME} flash"
    echo ""
    info "Default credentials: root/root"
    log "════════════════════════════════════════════════════════════"
}

# ============================================================================
# Commands
# ============================================================================

cmd_build() {
    header "Assembling Image for ${BOARD_NAME}"

    # Check root
    if [[ $EUID -ne 0 ]]; then
        error "Image assembly requires root. Run with: sudo $(basename "$0") $BOARD_NAME build"
    fi

    # Check dependencies
    check_deps

    # Check required artifacts
    local kernel_output rootfs_output kernel_status rootfs_status
    kernel_output=$(check_kernel_artifacts 2>/dev/null) || true
    rootfs_output=$(check_rootfs_artifact 2>/dev/null) || true
    kernel_status=$(echo "$kernel_output" | head -1)
    rootfs_status=$(echo "$rootfs_output" | head -1)

    [[ "$kernel_status" == "FOUND" ]] || error "Kernel not found. Run: ./scripts/build/kernel.sh $BOARD_NAME build"
    [[ "$rootfs_status" == "FOUND" ]] || error "Rootfs not found. Run: ./scripts/build/rootfs.sh $BOARD_NAME build"

    if [[ "$WITH_UBOOT" == "true" ]]; then
        local uboot_output uboot_status
        uboot_output=$(check_uboot_artifacts 2>/dev/null) || true
        uboot_status=$(echo "$uboot_output" | head -1)
        [[ "$uboot_status" == "FOUND" ]] || error "U-Boot not found. Run: ./scripts/build/uboot.sh $BOARD_NAME build"
        info "U-Boot will be included"
    fi

    # Build the image
    create_image_file
    partition_image
    flash_bootloader
    setup_loop_device

    trap cleanup_loop_device EXIT

    format_partitions
    install_boot_files
    install_rootfs

    cleanup_loop_device
    trap - EXIT

    compress_image
    calculate_checksums

    show_build_summary
}

cmd_clean() {
    header "Cleaning Image Artifacts"

    local work_dir="${PROJECT_ROOT}/output/image-work"
    if [[ -d "$work_dir" ]]; then
        info "Removing ${work_dir}..."
        sudo rm -rf "$work_dir"
    fi

    # List images but don't auto-delete
    local images
    images=$(ls -1 "${OUTPUT_DIR}"/rk3568-debian-*.img* 2>/dev/null | wc -l)
    if [[ $images -gt 0 ]]; then
        info "Found $images image file(s) in output/"
        ls -lh "${OUTPUT_DIR}"/rk3568-debian-*.img* 2>/dev/null | head -5
        warn "Images not deleted automatically. Remove manually if needed."
    fi

    log "Clean complete"
}

cmd_info() {
    header "Image Assembly Configuration"

    show_board_info

    echo ""
    info "Image Configuration:"
    kv "Size" "${IMAGE_SIZE}MB (${BOOT_SIZE}MB boot + rootfs)"
    kv "Kernel" "${KERNEL_VERSION}"
    kv "U-Boot" "$([ "$WITH_UBOOT" == "true" ] && echo "INCLUDED" || echo "Not included")"

    echo ""
    info "Required Artifacts:"
    local ko ro uo
    ko=$(check_kernel_artifacts 2>/dev/null) || true
    ro=$(check_rootfs_artifact 2>/dev/null) || true
    uo=$(check_uboot_artifacts 2>/dev/null) || true
    echo "  Kernel: $(echo "$ko" | head -1)"
    echo "  Rootfs: $(echo "$ro" | head -1)"
    echo "  U-Boot: $(echo "$uo" | head -1)"

    echo ""
    info "Output Images:"
    check_image_artifacts 2>/dev/null || true
}

# ============================================================================
# Main
# ============================================================================

main() {
    local board=""
    local command=""
    WITH_UBOOT=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --with-uboot)
                WITH_UBOOT=true
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

    if [[ -z "$board" ]] || [[ -z "$command" ]]; then
        usage
        exit 1
    fi

    load_board "$board" || exit 1

    case "$command" in
        build) cmd_build ;;
        clean) cmd_clean ;;
        info)  cmd_info ;;
        *)     error "Unknown command: $command" ;;
    esac
}

main "$@"
