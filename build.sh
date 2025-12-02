#!/bin/bash
set -e

# Debian Build System Orchestrator for RK3568
# Interactive build workflow with artifact detection

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Icons
ICON_CHECK="✓"
ICON_WARN="⚠"
ICON_INFO="ℹ"
ICON_BUILD="🔨"
ICON_SKIP="⏭"

log() { echo -e "${GREEN}${ICON_CHECK}${NC} $*"; }
warn() { echo -e "${YELLOW}${ICON_WARN}${NC} $*"; }
info() { echo -e "${CYAN}${ICON_INFO}${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }
header() { echo -e "\n${BOLD}${BLUE}━━━ $* ━━━${NC}\n"; }

usage() {
    echo -e "${BOLD}Debian Build System for RK3568${NC}"
    echo
    echo -e "${BOLD}USAGE:${NC}"
    echo "    $0 [OPTIONS] [BOARD]"
    echo
    echo -e "${BOLD}BOARDS:${NC}"
    echo "    rk3568_sz3568     SZ3568-V1.2 (RGMII with MAXIO PHY) [default]"
    echo "    rk3568_custom     DC-A568-V06 (RMII ethernet)"
    echo
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    --auto                Auto mode: build only what's missing, flash to SD card"
    echo "    --clean               Delete all build artifacts before starting"
    echo "    --clean-logs          Delete only build logs (keep artifacts)"
    echo "    --quiet               Quiet mode: hide verbose build output, show spinner"
    echo "    --non-interactive     Skip all prompts, rebuild everything"
    echo "    --kernel-only         Build kernel only"
    echo "    --rootfs-only         Build rootfs only"
    echo "    --image-only          Assemble image only (skip builds)"
    echo "    --with-uboot          Include U-Boot in image (⚠️  DANGEROUS)"
    echo "    --device /dev/sdX     SD card device (for --auto mode)"
    echo "    --help, -h            Show this help"
    echo
    echo -e "${BOLD}INTERACTIVE MODE (default):${NC}"
    echo "    Walks through each build stage:"
    echo "    1. Kernel build     (→ output/kernel-debs/*.deb)"
    echo "    2. Rootfs build     (→ rootfs/debian-rootfs.img)"
    echo "    3. Image assembly   (→ output/rk3568-debian-*.img)"
    echo
    echo "    For each stage:"
    echo "    - Shows existing artifacts (if any)"
    echo "    - Asks whether to skip or rebuild"
    echo "    - Handles dependencies automatically"
    echo
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    # Auto mode: build what's needed, flash to SD card"
    echo "    $0 --auto --device /dev/sdX rk3568_sz3568"
    echo "    (Will prompt for sudo password once)"
    echo
    echo "    # Interactive build (recommended for first time)"
    echo "    $0 rk3568_sz3568"
    echo
    echo "    # Clean rebuild (delete all artifacts first)"
    echo "    $0 --clean rk3568_sz3568"
    echo
    echo "    # Clean only logs (keep artifacts)"
    echo "    $0 --clean-logs"
    echo
    echo "    # Clean logs before building"
    echo "    $0 --clean-logs rk3568_sz3568"
    echo
    echo "    # Quiet mode (less verbose output)"
    echo "    $0 --quiet --auto --device /dev/sdX rk3568_sz3568"
    echo
    echo "    # Non-interactive full rebuild"
    echo "    $0 --non-interactive rk3568_sz3568"
    echo
    echo "    # Build kernel only"
    echo "    $0 --kernel-only rk3568_sz3568"
    echo
    echo "    # Assemble image from existing artifacts"
    echo "    $0 --image-only rk3568_sz3568"
    echo
    echo -e "${BOLD}REQUIREMENTS:${NC}"
    echo "    - Docker (recommended) OR build dependencies installed"
    echo "    - sudo access (script will prompt for password when needed)"
    echo
    echo -e "${BOLD}BUILD TIME:${NC}"
    echo "    First build:  ~30-45 minutes"
    echo "    Rebuilds:     ~5-15 minutes (depending on what changed)"
    echo
}

# Parse arguments
BOARD=""
AUTO_MODE=false
CLEAN_MODE=false
CLEAN_LOGS_MODE=false
QUIET_MODE=false
export QUIET_MODE
NON_INTERACTIVE=false
KERNEL_ONLY=false
ROOTFS_ONLY=false
IMAGE_ONLY=false
WITH_UBOOT=false
SD_DEVICE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            AUTO_MODE=true
            NON_INTERACTIVE=true
            shift
            ;;
        --clean)
            CLEAN_MODE=true
            shift
            ;;
        --clean-logs)
            CLEAN_LOGS_MODE=true
            shift
            ;;
        --quiet)
            QUIET_MODE=true
            shift
            ;;
        --device)
            SD_DEVICE="$2"
            shift 2
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --kernel-only)
            KERNEL_ONLY=true
            shift
            ;;
        --rootfs-only)
            ROOTFS_ONLY=true
            shift
            ;;
        --image-only)
            IMAGE_ONLY=true
            shift
            ;;
        --with-uboot)
            WITH_UBOOT=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        rk3568_*)
            BOARD="$1"
            shift
            ;;
        *)
            error "Unknown option: $1\nRun '$0 --help' for usage"
            ;;
    esac
done

# Default board
BOARD="${BOARD:-rk3568_sz3568}"

# Validate board
case "${BOARD}" in
    rk3568_sz3568)
        DTB_NAME="rk3568-sz3568"
        BOARD_DESC="SZ3568-V1.2 (RGMII with MAXIO PHY)"
        ;;
    rk3568_custom)
        DTB_NAME="rk3568-dc-a568"
        BOARD_DESC="DC-A568-V06 (RMII ethernet)"
        ;;
    *)
        error "Unknown board: ${BOARD}\nSupported: rk3568_sz3568, rk3568_custom"
        ;;
esac

# Paths
KERNEL_DEBS_DIR="${PROJECT_ROOT}/output/kernel-debs"
ROOTFS_IMAGE="${PROJECT_ROOT}/rootfs/debian-rootfs.img"
OUTPUT_DIR="${PROJECT_ROOT}/output"

# ============================================================================
# Artifact Detection Functions
# ============================================================================

check_kernel_artifacts() {
    local image_deb=$(ls -1t "${KERNEL_DEBS_DIR}"/linux-image-*.deb 2>/dev/null | head -1)
    local headers_deb=$(ls -1t "${KERNEL_DEBS_DIR}"/linux-headers-*.deb 2>/dev/null | head -1)

    if [ -n "$image_deb" ] && [ -f "$image_deb" ]; then
        local size=$(du -h "$image_deb" | cut -f1)
        local date=$(stat -c %y "$image_deb" | cut -d' ' -f1,2 | cut -d'.' -f1)
        local version=$(basename "$image_deb" | sed 's/linux-image-\(.*\)_.*\.deb/\1/')

        echo "FOUND"
        echo "  Image:   $(basename "$image_deb")"
        echo "  Size:    $size"
        echo "  Date:    $date"
        echo "  Version: $version"

        if [ -n "$headers_deb" ] && [ -f "$headers_deb" ]; then
            local hdr_size=$(du -h "$headers_deb" | cut -f1)
            echo "  Headers: $(basename "$headers_deb") ($hdr_size)"
        fi
        return 0
    else
        echo "NOT_FOUND"
        return 1
    fi
}

check_rootfs_artifact() {
    if [ -f "${ROOTFS_IMAGE}" ]; then
        local size=$(du -h "${ROOTFS_IMAGE}" | cut -f1)
        local date=$(stat -c %y "${ROOTFS_IMAGE}" | cut -d' ' -f1,2 | cut -d'.' -f1)

        # Try to get rootfs info
        local fs_info=$(file "${ROOTFS_IMAGE}" 2>/dev/null || echo "ext4 filesystem")

        echo "FOUND"
        echo "  File: $(basename "${ROOTFS_IMAGE}")"
        echo "  Size: $size"
        echo "  Date: $date"
        echo "  Type: $fs_info"
        return 0
    else
        echo "NOT_FOUND"
        return 1
    fi
}

check_image_artifacts() {
    local final_image=$(ls -1t "${OUTPUT_DIR}"/rk3568-debian-*.img 2>/dev/null | grep -v '\.xz$' | head -1)

    if [ -n "$final_image" ] && [ -f "$final_image" ]; then
        local size=$(du -h "$final_image" | cut -f1)
        local date=$(stat -c %y "$final_image" | cut -d' ' -f1,2 | cut -d'.' -f1)

        echo "FOUND"
        echo "  Image: $(basename "$final_image")"
        echo "  Size:  $size"
        echo "  Date:  $date"

        # Check for compressed version
        if [ -f "${final_image}.xz" ]; then
            local xz_size=$(du -h "${final_image}.xz" | cut -f1)
            echo "  Compressed: $(basename "${final_image}.xz") ($xz_size)"
        fi

        # Check for checksum
        if [ -f "${final_image}.sha256" ]; then
            echo "  Checksum: Available"
        fi
        return 0
    else
        echo "NOT_FOUND"
        return 1
    fi
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

    if [ -z "$device" ]; then
        return 1
    fi

    if [ ! -b "$device" ]; then
        error "Device $device is not a block device"
    fi

    # Check if it's a removable device
    local dev_name=$(basename "$device")
    local removable=$(cat /sys/block/${dev_name}/removable 2>/dev/null || echo "0")

    if [ "$removable" != "1" ]; then
        warn "⚠️  Device $device does not appear to be removable!"
        warn "   This could be your system disk!"

        if [ "$AUTO_MODE" = true ]; then
            error "Auto mode requires a removable device. Use --device to specify."
        fi

        local answer=$(ask_yes_no "Continue anyway? (DANGEROUS)" "n")
        if [[ ! $answer =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Get device info
    local size=$(lsblk -d -n -o SIZE "$device" 2>/dev/null)
    local model=$(lsblk -d -n -o MODEL "$device" 2>/dev/null)

    info "Device: $device"
    info "Size:   $size"
    info "Model:  $model"

    return 0
}

flash_to_sd() {
    local image_file="$1"
    local device="$2"

    if [ ! -f "$image_file" ]; then
        error "Image file not found: $image_file"
    fi

    if [ -z "$device" ]; then
        # Auto-detect SD cards
        local sd_cards=($(detect_sd_cards))

        if [ ${#sd_cards[@]} -eq 0 ]; then
            error "No removable SD cards detected. Use --device /dev/sdX"
        elif [ ${#sd_cards[@]} -eq 1 ]; then
            device="${sd_cards[0]}"
            info "Auto-detected SD card: $device"
        else
            warn "Multiple SD cards detected:"
            for card in "${sd_cards[@]}"; do
                echo "  - $card ($(lsblk -d -n -o SIZE,MODEL "$card"))"
            done
            error "Multiple devices found. Use --device /dev/sdX to specify"
        fi
    fi

    verify_sd_device "$device"

    # Unmount any mounted partitions
    info "Unmounting any mounted partitions on $device..."
    sudo umount ${device}* 2>/dev/null || true

    # Show warning
    warn "⚠️  About to write to $device - ALL DATA WILL BE LOST!"

    if [ "$AUTO_MODE" = false ]; then
        echo -e "${RED}${BOLD}"
        read -p "Type 'YES' to confirm: " confirm
        echo -e "${NC}"

        if [ "$confirm" != "YES" ]; then
            error "Flash cancelled"
        fi
    fi

    # Flash the image
    info "Flashing $(basename "$image_file") to $device..."
    echo "This will take several minutes..."

    if [ -f "${image_file}.xz" ]; then
        # Use compressed version if available
        info "Using compressed image: $(basename "${image_file}.xz")"
        sudo xz -dc "${image_file}.xz" | sudo dd of="$device" bs=4M status=progress conv=fsync
    else
        sudo dd if="$image_file" of="$device" bs=4M status=progress conv=fsync
    fi

    # Flash U-Boot if built with --with-uboot
    if [ "$WITH_UBOOT" = true ]; then
        echo
        info "Flashing mainline U-Boot to $device..."

        # Check if mainline U-Boot unified image exists
        if [ -f "${OUTPUT_DIR}/uboot/u-boot-rockchip.bin" ]; then

            # Flash unified U-Boot image to bootloader area
            info "Writing u-boot-rockchip.bin (unified: TPL+SPL+ATF+U-Boot)..."
            sudo dd if="${OUTPUT_DIR}/uboot/u-boot-rockchip.bin" of="$device" seek=64 bs=512 conv=fsync status=none

            log "✓ Mainline U-Boot flashed to $device (sector 64)"
        else
            warn "U-Boot binary not found: ${OUTPUT_DIR}/uboot/u-boot-rockchip.bin"
            warn "Skipping U-Boot flash - using existing bootloader on device"
        fi
    fi

    # Sync
    sudo sync

    log "Flash complete! $device is ready to boot."
    if [ "$WITH_UBOOT" = true ]; then
        echo
        info "Custom U-Boot has been flashed - bootcmd will run distro_bootcmd automatically"
    fi
}

# ============================================================================
# Interactive Prompts
# ============================================================================

ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"

    if [ "$NON_INTERACTIVE" = true ]; then
        echo "$default"
        return
    fi

    local yn
    if [ "$default" = "y" ]; then
        read -p "$(echo -e "${prompt} [Y/n]: ")" -r yn
        yn="${yn:-y}"
    else
        read -p "$(echo -e "${prompt} [y/N]: ")" -r yn
        yn="${yn:-n}"
    fi

    echo "$yn"
}

# ============================================================================
# Sudo Session Management
# ============================================================================

setup_sudo() {
    # Check if we'll need sudo for this run
    local needs_sudo=false

    if [ "$IMAGE_ONLY" = true ] || [ "$AUTO_MODE" = true ] || [ -z "$KERNEL_ONLY" ] && [ -z "$ROOTFS_ONLY" ]; then
        needs_sudo=true
    fi

    if [ "$needs_sudo" = false ]; then
        return 0
    fi

    info "Establishing sudo session (password required once)..."

    # Establish sudo session
    if ! sudo -v; then
        error "Failed to establish sudo session"
    fi

    # Keep sudo session alive with proper cleanup
    cleanup_sudo() {
        if [[ -n "$SUDO_REFRESH_PID" ]]; then
            kill $SUDO_REFRESH_PID 2>/dev/null || true
        fi
    }
    trap cleanup_sudo EXIT

    ( while true; do sudo -v; sleep 60; done; ) &
    SUDO_REFRESH_PID=$!

    log "Sudo session established (will stay alive for entire build)"
}

# ============================================================================
# Clean Function
# ============================================================================

clean_logs() {
    header "Cleaning Build Logs"

    local cleaned=false
    local log_count=0

    # Clean build logs
    if ls "${PROJECT_ROOT}/output"/build-*.log &>/dev/null; then
        log_count=$(ls -1 "${PROJECT_ROOT}/output"/build-*.log 2>/dev/null | wc -l)
        info "Removing ${log_count} log file(s)..."
        rm -f "${PROJECT_ROOT}/output"/build-*.log
        cleaned=true
    fi

    if [ "$cleaned" = true ]; then
        log "Removed ${log_count} build log(s)"
    else
        info "No log files found to clean"
    fi

    echo
}

clean_artifacts() {
    header "Cleaning Build Artifacts"

    local cleaned=false

    # Clean kernel artifacts
    if [ -d "${PROJECT_ROOT}/output/kernel-debs" ]; then
        info "Removing kernel .deb packages..."
        rm -rf "${PROJECT_ROOT}/output/kernel-debs"
        cleaned=true
    fi

    # Fix output directory ownership if it exists (might be root-owned)
    if [ -d "${PROJECT_ROOT}/output" ]; then
        if [ "$(stat -c '%U' "${PROJECT_ROOT}/output" 2>/dev/null)" = "root" ]; then
            info "Fixing output directory ownership..."
            sudo chown -R "$(id -u):$(id -g)" "${PROJECT_ROOT}/output"
            cleaned=true
        fi
    fi

    # Clean kernel source
    if [ -d "${PROJECT_ROOT}/kernel-6.6" ]; then
        info "Removing kernel source directory..."
        rm -rf "${PROJECT_ROOT}/kernel-6.6"
        cleaned=true
    fi

    # Clean intermediate build files (might be root-owned)
    if ls "${PROJECT_ROOT}"/linux-*.deb "${PROJECT_ROOT}"/linux-*.changes "${PROJECT_ROOT}"/linux-*.buildinfo &>/dev/null; then
        info "Removing intermediate build files..."
        sudo rm -f "${PROJECT_ROOT}"/linux-*.deb \
                   "${PROJECT_ROOT}"/linux-*.changes \
                   "${PROJECT_ROOT}"/linux-*.buildinfo 2>/dev/null || true
        cleaned=true
    fi

    # Clean rootfs artifacts
    if [ -d "${PROJECT_ROOT}/rootfs/work" ]; then
        info "Removing rootfs work directory..."
        sudo rm -rf "${PROJECT_ROOT}/rootfs/work"
        cleaned=true
    fi

    if [ -f "${PROJECT_ROOT}/rootfs/debian-rootfs.img" ]; then
        info "Removing rootfs image..."
        rm -f "${PROJECT_ROOT}/rootfs/debian-rootfs.img"
        cleaned=true
    fi

    # Fix rootfs directory ownership if it exists (might be root-owned)
    if [ -d "${PROJECT_ROOT}/rootfs" ]; then
        if [ "$(stat -c '%U' "${PROJECT_ROOT}/rootfs" 2>/dev/null)" = "root" ]; then
            info "Fixing rootfs directory ownership..."
            sudo chown -R "$(id -u):$(id -g)" "${PROJECT_ROOT}/rootfs"
            cleaned=true
        fi
    fi

    # Clean U-Boot artifacts
    if [ -d "${PROJECT_ROOT}/output/uboot" ]; then
        info "Removing U-Boot binaries..."
        rm -rf "${PROJECT_ROOT}/output/uboot"
        cleaned=true
    fi

    if [ -d "${PROJECT_ROOT}/u-boot" ]; then
        info "Removing U-Boot source directory..."
        sudo rm -rf "${PROJECT_ROOT}/u-boot"
        cleaned=true
    fi

    # Clean final images
    if ls "${PROJECT_ROOT}/output"/rk3568-debian-*.img* &>/dev/null; then
        info "Removing final images..."
        rm -f "${PROJECT_ROOT}/output"/rk3568-debian-*.img*
        cleaned=true
    fi

    # Clean Docker image (forces rebuild with latest code)
    if command -v docker &>/dev/null; then
        if docker image inspect rk3568-debian-builder:latest &>/dev/null 2>&1; then
            info "Removing Docker build image (will rebuild with latest code)..."
            docker rmi -f rk3568-debian-builder:latest || true
            cleaned=true
        fi
    fi

    if [ "$cleaned" = true ]; then
        log "All build artifacts removed"
    else
        info "No artifacts found to clean"
    fi

    echo
}

# ============================================================================
# Build Stage Functions
# ============================================================================

stage_kernel() {
    header "Stage 1: Kernel Build (6.6 LTS)"

    info "Board:  ${BOARD}"
    info "DTB:    ${DTB_NAME}.dtb"
    info "Output: ${KERNEL_DEBS_DIR}/"
    echo

    local status=$(check_kernel_artifacts)

    if echo "$status" | grep -q "^FOUND$"; then
        echo -e "${GREEN}${ICON_CHECK} Kernel artifacts found:${NC}"
        echo "$status" | grep -v "FOUND" || true
        echo

        # Auto mode: skip if artifacts exist
        if [ "$AUTO_MODE" = true ]; then
            log "Auto mode: using existing kernel artifacts"
            return 0
        fi

        local answer=$(ask_yes_no "Rebuild kernel?" "n")
        if [[ ! $answer =~ ^[Yy]$ ]]; then
            log "Skipping kernel build (using existing artifacts)"
            return 0
        fi
    else
        warn "No kernel artifacts found"
        echo

        # Auto mode: build automatically
        if [ "$AUTO_MODE" = true ]; then
            info "Auto mode: building kernel..."
        elif [ "$NON_INTERACTIVE" = false ]; then
            local answer=$(ask_yes_no "Build kernel now?" "y")
            if [[ ! $answer =~ ^[Yy]$ ]]; then
                error "Kernel is required for image assembly"
            fi
        fi
    fi

    echo -e "${CYAN}${ICON_BUILD} Building kernel...${NC}"

    # Log to phase-specific file
    local phase_log="${BUILD_LOG_PREFIX}-kernel.log"
    info "Kernel log: ${phase_log}"

    if ! "${PROJECT_ROOT}/scripts/build-kernel.sh" "${BOARD}" 2>&1 | tee "${phase_log}"; then
        error "Kernel build failed! Check log: ${phase_log}"
    fi

    log "Kernel build complete!"
}

stage_rootfs() {
    local profile="${PROFILE:-minimal}"
    header "Stage 2: Rootfs Build (Ubuntu 24.04 + XFCE)"

    info "Profile:  ${profile}"
    if [ "$profile" = "full" ]; then
        info "Desktop:  XFCE4 + LightDM"
        info "Network:  NetworkManager"
        info "Browser:  Epiphany (GNOME Web)"
    else
        info "Desktop:  XFCE4 (startx)"
        info "Network:  systemd-networkd"
        info "Browser:  Chromium"
    fi
    info "GPU:      libmali-bifrost-g52-g13p0"
    info "Output:   ${ROOTFS_IMAGE}"
    echo

    local status=$(check_rootfs_artifact)

    if echo "$status" | grep -q "^FOUND$"; then
        echo -e "${GREEN}${ICON_CHECK} Rootfs artifact found:${NC}"
        echo "$status" | grep -v "FOUND" || true
        echo

        # Auto mode: skip if artifacts exist
        if [ "$AUTO_MODE" = true ]; then
            log "Auto mode: using existing rootfs artifact"
            return 0
        fi

        local answer=$(ask_yes_no "Rebuild rootfs?" "n")
        if [[ ! $answer =~ ^[Yy]$ ]]; then
            log "Skipping rootfs build (using existing artifact)"
            return 0
        fi
    else
        warn "No rootfs artifact found"
        echo

        # Auto mode: build automatically
        if [ "$AUTO_MODE" = true ]; then
            info "Auto mode: building rootfs..."
        elif [ "$NON_INTERACTIVE" = false ]; then
            local answer=$(ask_yes_no "Build rootfs now?" "y")
            if [[ ! $answer =~ ^[Yy]$ ]]; then
                error "Rootfs is required for image assembly"
            fi
        fi
    fi

    echo -e "${CYAN}${ICON_BUILD} Building rootfs...${NC}"

    # Log to phase-specific file
    local phase_log="${BUILD_LOG_PREFIX}-rootfs.log"
    info "Rootfs log: ${phase_log}"

    if ! "${PROJECT_ROOT}/scripts/build-debian-rootfs.sh" 2>&1 | tee "${phase_log}"; then
        error "Rootfs build failed! Check log: ${phase_log}"
    fi

    log "Rootfs build complete!"
}

check_uboot_artifacts() {
    if [ -f "${OUTPUT_DIR}/uboot/u-boot-rockchip.bin" ]; then
        local size=$(du -h "${OUTPUT_DIR}/uboot/u-boot-rockchip.bin" | cut -f1)
        local date=$(stat -c %y "${OUTPUT_DIR}/uboot/u-boot-rockchip.bin" | cut -d' ' -f1,2 | cut -d'.' -f1)

        echo "FOUND"
        echo "  U-Boot: u-boot-rockchip.bin ($size)"
        echo "  Date:   $date"
        echo "  Type:   Mainline unified image (TPL+SPL+ATF+U-Boot)"
        return 0
    else
        echo "NOT_FOUND"
        return 1
    fi
}

stage_uboot() {
    header "Stage 2.5: U-Boot Build (Optional)"

    info "Board:  ${BOARD}"
    info "Output: ${OUTPUT_DIR}/uboot/"
    echo

    # Only build U-Boot if --with-uboot flag is set
    if [ "$WITH_UBOOT" = false ]; then
        info "U-Boot build skipped (use --with-uboot to build custom U-Boot)"
        return 0
    fi

    local status=$(check_uboot_artifacts)

    if echo "$status" | grep -q "^FOUND$"; then
        echo -e "${GREEN}${ICON_CHECK} U-Boot artifacts found:${NC}"
        echo "$status" | grep -v "FOUND" || true
        echo

        # Auto mode: skip if artifacts exist
        if [ "$AUTO_MODE" = true ]; then
            log "Auto mode: using existing U-Boot artifacts"
            return 0
        fi

        local answer=$(ask_yes_no "Rebuild U-Boot?" "n")
        if [[ ! $answer =~ ^[Yy]$ ]]; then
            log "Skipping U-Boot build (using existing artifacts)"
            return 0
        fi
    else
        warn "No U-Boot artifacts found"
        echo
        warn "⚠️  CAUTION: Building custom U-Boot!"
        warn "⚠️  Ensure you have maskrom recovery available!"
        echo

        if [ "$NON_INTERACTIVE" = false ]; then
            local answer=$(ask_yes_no "Build custom U-Boot now?" "y")
            if [[ ! $answer =~ ^[Yy]$ ]]; then
                error "U-Boot is required when --with-uboot is specified"
            fi
        fi
    fi

    echo -e "${CYAN}${ICON_BUILD} Building U-Boot...${NC}"

    # Log to phase-specific file
    local phase_log="${BUILD_LOG_PREFIX}-uboot.log"
    info "U-Boot log: ${phase_log}"

    if ! "${PROJECT_ROOT}/scripts/build-uboot.sh" "${BOARD}" 2>&1 | tee "${phase_log}"; then
        error "U-Boot build failed! Check log: ${phase_log}"
    fi

    log "U-Boot build complete!"
}

stage_image() {
    header "Stage 3: Image Assembly"

    info "Board:    ${BOARD}"
    info "DTB:      ${DTB_NAME}.dtb"
    info "U-Boot:   $([ "$WITH_UBOOT" = true ] && echo "INCLUDED ⚠️" || echo "Using existing on board")"
    info "Output:   ${OUTPUT_DIR}/rk3568-debian-*.img"
    echo

    # Check dependencies
    local kernel_status=$(check_kernel_artifacts)
    local rootfs_status=$(check_rootfs_artifact)

    if ! echo "$kernel_status" | grep -q "^FOUND$"; then
        error "Kernel artifacts not found! Run kernel build first."
    fi

    if ! echo "$rootfs_status" | grep -q "^FOUND$"; then
        error "Rootfs artifact not found! Run rootfs build first."
    fi

    local status=$(check_image_artifacts)

    if echo "$status" | grep -q "^FOUND$"; then
        echo -e "${GREEN}${ICON_CHECK} Final image found:${NC}"
        echo "$status" | grep -v "FOUND" || true
        echo

        # Auto mode: skip if artifacts exist
        if [ "$AUTO_MODE" = true ]; then
            log "Auto mode: using existing final image"
            return 0
        fi

        local answer=$(ask_yes_no "Rebuild image?" "n")
        if [[ ! $answer =~ ^[Yy]$ ]]; then
            log "Skipping image assembly (using existing image)"
            return 0
        fi
    else
        warn "No final image found"
        echo

        # Auto mode: build automatically
        if [ "$AUTO_MODE" = true ]; then
            info "Auto mode: assembling image..."
        elif [ "$NON_INTERACTIVE" = false ]; then
            local answer=$(ask_yes_no "Assemble image now?" "y")
            if [[ ! $answer =~ ^[Yy]$ ]]; then
                info "Image assembly skipped"
                return 0
            fi
        fi
    fi

    echo -e "${CYAN}${ICON_BUILD} Assembling image...${NC}"

    # Log to phase-specific file
    local phase_log="${BUILD_LOG_PREFIX}-image.log"
    info "Image assembly log: ${phase_log}"

    if [ "$WITH_UBOOT" = true ]; then
        if ! sudo "${PROJECT_ROOT}/scripts/assemble-debian-image.sh" --with-uboot "${BOARD}" 2>&1 | tee "${phase_log}"; then
            error "Image assembly failed! Check log: ${phase_log}"
        fi
    else
        if ! sudo "${PROJECT_ROOT}/scripts/assemble-debian-image.sh" "${BOARD}" 2>&1 | tee "${phase_log}"; then
            error "Image assembly failed! Check log: ${phase_log}"
        fi
    fi

    log "Image assembly complete!"
}

stage_write_device() {
    # Only offer if device was specified and not in AUTO_MODE
    # (AUTO_MODE has its own flash_to_sd logic)
    if [ -z "$SD_DEVICE" ] || [ "$AUTO_MODE" = true ]; then
        return 0
    fi

    header "Stage 4: Write to Device (Optional)"

    # Find the most recent image
    local latest_img=$(ls -t "${OUTPUT_DIR}"/rk3568-debian-*.img 2>/dev/null | head -1)
    if [ -z "$latest_img" ]; then
        warn "No image file found to write"
        return 1
    fi

    local img_size=$(du -h "$latest_img" | cut -f1)

    echo
    info "Image:  $latest_img"
    info "Size:   $img_size"
    info "Target: ${SD_DEVICE}"
    echo

    # Check if device exists
    if [ ! -b "$SD_DEVICE" ]; then
        error "Device $SD_DEVICE is not a block device"
    fi

    # Show device info
    local dev_size=$(sudo blockdev --getsize64 "$SD_DEVICE" 2>/dev/null | awk '{print int($1/1024/1024/1024)"GB"}')
    local dev_model=$(sudo lsblk -ndo MODEL "$SD_DEVICE" 2>/dev/null || echo "Unknown")

    info "Device info:"
    echo "  Model: $dev_model"
    echo "  Size:  $dev_size"
    echo

    # Safety check - don't write to obviously wrong devices
    case "$SD_DEVICE" in
        /dev/sda|/dev/nvme0n1|/dev/vda)
            warn "⚠️  WARNING: $SD_DEVICE looks like your primary system disk!"
            warn "Are you SURE this is your SD card?"
            ;;
    esac

    # Ask confirmation
    echo -e "${YELLOW}⚠️  WARNING: This will ERASE all data on ${SD_DEVICE}${NC}"
    read -p "Write image to device? [y/N]: " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Skipped device write"
        return 0
    fi

    # Write image
    log "Writing image to ${SD_DEVICE}"
    log "This will take several minutes"

    if sudo dd if="$latest_img" of="$SD_DEVICE" bs=4M status=progress conv=fsync; then
        sync
        sudo eject "$SD_DEVICE" 2>/dev/null || true
        echo
        log "✓ Image written successfully to ${SD_DEVICE}"
        log ""
        log "You can now:"
        log "  1. Remove SD card"
        log "  2. Insert into RK3568 board"
        log "  3. Power on and boot"
        log "  4. Login: rock / rock"
        log "  5. (Optional) Run: sudo setup-emmc"
    else
        error "Failed to write image to ${SD_DEVICE}"
    fi
}

# ============================================================================
# Main Workflow
# ============================================================================

show_banner() {
    echo -e "${BOLD}${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     Debian Build System for Rockchip RK3568                   ║
║     Kernel 6.1 LTS + Debian 12 + XFCE Desktop                 ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    info "Board: ${BOARD_DESC}"
    if [ "$AUTO_MODE" = true ]; then
        info "Mode:  Auto (build missing, flash to SD)"
        if [ -n "$SD_DEVICE" ]; then
            info "Device: $SD_DEVICE"
        else
            info "Device: Auto-detect"
        fi
    else
        info "Mode:  $([ "$NON_INTERACTIVE" = true ] && echo "Non-interactive" || echo "Interactive")"
    fi
    echo
}

show_summary() {
    header "Build Summary"

    echo -e "${BOLD}Artifacts:${NC}"
    echo

    echo -e "${BOLD}1. Kernel (.deb packages)${NC}"
    local kernel_status=$(check_kernel_artifacts)
    if echo "$kernel_status" | grep -q "^FOUND$"; then
        echo "$kernel_status" | grep -v "FOUND" || true
    else
        echo "   ${RED}Not found${NC}"
    fi
    echo

    echo -e "${BOLD}2. Rootfs (filesystem image)${NC}"
    local rootfs_status=$(check_rootfs_artifact)
    if echo "$rootfs_status" | grep -q "^FOUND$"; then
        echo "$rootfs_status" | grep -v "FOUND" || true
    else
        echo "   ${RED}Not found${NC}"
    fi
    echo

    echo -e "${BOLD}3. Final Image (flashable SD/eMMC)${NC}"
    local image_status=$(check_image_artifacts)
    if echo "$image_status" | grep -q "^FOUND$"; then
        echo "$image_status" | grep -v "FOUND" || true
        echo

        local final_image=$(ls -1t "${OUTPUT_DIR}"/rk3568-debian-*.img 2>/dev/null | grep -v '\.xz$' | head -1)
        if [ -n "$final_image" ]; then
            echo -e "${BOLD}Next Steps:${NC}"
            echo "  1. Flash to SD card:"
            echo -e "     ${CYAN}sudo dd if=$(basename "$final_image") of=/dev/sdX bs=4M status=progress${NC}"
            echo
            echo "  2. Or use compressed version with balenaEtcher:"
            if [ -f "${final_image}.xz" ]; then
                echo -e "     ${CYAN}$(basename "${final_image}.xz")${NC}"
            else
                echo -e "     ${YELLOW}(Run xz compression if needed)${NC}"
            fi
            echo
            echo "  3. Default credentials:"
            echo -e "     User: ${CYAN}rock${NC} / Password: ${CYAN}rock${NC}"
            echo -e "     Root: ${CYAN}root${NC} / Password: ${CYAN}root${NC}"
            echo
            echo -e "${BOLD}Manual U-Boot Boot (if board doesn't auto-boot):${NC}"
            echo "  1. Interrupt U-Boot (press any key during countdown)"
            echo "  2. Load kernel and device tree:"
            echo -e "     ${CYAN}ext4load mmc 1:1 0x02080000 /Image${NC}"
            echo -e "     ${CYAN}ext4load mmc 1:1 0x0a100000 /${DTB_NAME}.dtb${NC}"
            echo "  3. Set boot arguments:"
            echo -e "     ${CYAN}setenv bootargs console=ttyS2,1500000 root=/dev/mmcblk1p2 rootwait rw${NC}"
            echo "  4. Boot:"
            echo -e "     ${CYAN}booti 0x02080000 - 0x0a100000${NC}"
            echo
            echo -e "${BOLD}Provision to eMMC (optional):${NC}"
            echo "  1. Boot from SD card"
            echo "  2. Login and run:"
            echo -e "     ${CYAN}sudo setup-emmc${NC}"
            echo "  3. Wait ~5 minutes for copy to complete"
            echo "  4. Shutdown and remove SD card"
            echo "  5. Power on - board will boot from eMMC"
        fi
    else
        echo "   ${RED}Not found${NC}"
    fi
    echo
}

main() {
    # Set up build logging with timestamp for this build session
    BUILD_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    BUILD_LOG_PREFIX="${OUTPUT_DIR}/build-${BUILD_TIMESTAMP}"
    BUILD_LOG_FULL="${BUILD_LOG_PREFIX}-full.log"

    mkdir -p "${OUTPUT_DIR}"

    # Export log prefix for subscripts to use
    export BUILD_LOG_PREFIX

    # Use tee to write to both stdout and combined log file
    exec > >(tee -a "${BUILD_LOG_FULL}")
    exec 2>&1

    show_banner
    info "Build session: ${BUILD_TIMESTAMP}"
    info "Full log: ${BUILD_LOG_FULL}"
    info "Phase logs will be created in: ${OUTPUT_DIR}/build-${BUILD_TIMESTAMP}-*.log"
    echo

    # Handle clean-logs-only mode
    if [ "$CLEAN_LOGS_MODE" = true ] && \
       [ "$CLEAN_MODE" = false ] && \
       [ "$AUTO_MODE" = false ] && \
       [ "$KERNEL_ONLY" = false ] && \
       [ "$ROOTFS_ONLY" = false ] && \
       [ "$IMAGE_ONLY" = false ] && \
       [ "$NON_INTERACTIVE" = false ]; then
        # Just clean logs and exit
        clean_logs
        log "Log cleanup complete!"
        exit 0
    fi

    # Handle clean-only mode (no build flags specified)
    if [ "$CLEAN_MODE" = true ] && \
       [ "$AUTO_MODE" = false ] && \
       [ "$KERNEL_ONLY" = false ] && \
       [ "$ROOTFS_ONLY" = false ] && \
       [ "$IMAGE_ONLY" = false ] && \
       [ "$NON_INTERACTIVE" = false ]; then
        # Just clean and exit
        setup_sudo  # Need sudo for cleaning Docker image and rootfs
        clean_artifacts
        log "Clean complete!"
        exit 0
    fi

    # Set up sudo session keepalive (if needed)
    setup_sudo

    # Clean logs if requested (before building)
    if [ "$CLEAN_LOGS_MODE" = true ]; then
        clean_logs
    fi

    # Clean artifacts if requested (before building)
    if [ "$CLEAN_MODE" = true ]; then
        clean_artifacts
    fi

    # Handle single-stage builds
    if [ "$KERNEL_ONLY" = true ]; then
        stage_kernel
        log "Done!"
        exit 0
    fi

    if [ "$ROOTFS_ONLY" = true ]; then
        stage_rootfs
        log "Done!"
        exit 0
    fi

    if [ "$IMAGE_ONLY" = true ]; then
        stage_image
        show_summary
        log "Done!"
        exit 0
    fi

    # Full workflow
    stage_kernel
    echo

    stage_rootfs
    echo

    stage_uboot
    echo

    stage_image
    echo

    # Offer to write to device if --device specified (not in AUTO_MODE)
    stage_write_device
    echo

    # Auto mode: flash to SD card
    if [ "$AUTO_MODE" = true ]; then
        header "Stage 4: Flash to SD Card"

        local final_image=$(ls -1t "${OUTPUT_DIR}"/rk3568-debian-*.img 2>/dev/null | grep -v '\.xz$' | head -1)

        if [ -z "$final_image" ]; then
            error "No final image found for flashing!"
        fi

        flash_to_sd "$final_image" "$SD_DEVICE"
        echo
    fi

    show_summary

    log "Build complete! 🎉"
}

main "$@"
