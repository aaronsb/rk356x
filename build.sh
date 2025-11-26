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
QUIET_MODE=false
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

    # Sync
    sudo sync

    log "Flash complete! $device is ready to boot."
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
            docker rmi rk3568-debian-builder:latest >/dev/null 2>&1 || true
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
    "${PROJECT_ROOT}/scripts/build-kernel.sh" "${BOARD}"

    log "Kernel build complete!"
}

stage_rootfs() {
    header "Stage 2: Rootfs Build (Ubuntu 24.04 + XFCE)"

    info "Desktop:  XFCE4 + LightDM"
    info "GPU:      libmali-bifrost-g52-g13p0"
    info "Browser:  Epiphany (WebKitGTK)"
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
    "${PROJECT_ROOT}/scripts/build-debian-rootfs.sh"

    log "Rootfs build complete!"
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

    if [ "$WITH_UBOOT" = true ]; then
        sudo "${PROJECT_ROOT}/scripts/assemble-debian-image.sh" --with-uboot "${BOARD}"
    else
        sudo "${PROJECT_ROOT}/scripts/assemble-debian-image.sh" "${BOARD}"
    fi

    log "Image assembly complete!"
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
║     Kernel 6.6 LTS + Ubuntu 24.04 + XFCE Desktop              ║
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
            echo "     ${CYAN}sudo dd if=$(basename "$final_image") of=/dev/sdX bs=4M status=progress${NC}"
            echo
            echo "  2. Or use compressed version with balenaEtcher:"
            if [ -f "${final_image}.xz" ]; then
                echo "     ${CYAN}$(basename "${final_image}.xz")${NC}"
            else
                echo "     ${YELLOW}(Run xz compression if needed)${NC}"
            fi
            echo
            echo "  3. Default credentials:"
            echo "     User: ${CYAN}rock${NC} / Password: ${CYAN}rock${NC}"
            echo "     Root: ${CYAN}root${NC} / Password: ${CYAN}root${NC}"
        fi
    else
        echo "   ${RED}Not found${NC}"
    fi
    echo
}

main() {
    show_banner

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

    stage_image
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
