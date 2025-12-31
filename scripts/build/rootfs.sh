#!/bin/bash
# Standalone rootfs build script
# Builds Debian rootfs for RK3568 boards

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Configuration
DEBIAN_RELEASE="bookworm"
ROOTFS_DIR="${PROJECT_ROOT}/rootfs"
ROOTFS_WORK="${ROOTFS_DIR}/work"
ROOTFS_IMAGE="${ROOTFS_DIR}/debian-rootfs.img"
ROOTFS_SIZE="4G"
PROFILE="${PROFILE:-minimal}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <board> <command>

Build Debian ${DEBIAN_RELEASE} rootfs for RK3568 boards.

Commands:
  build       Build rootfs image
  clean       Clean rootfs artifacts
  info        Show build configuration

Options:
  --profile PROFILE   Build profile: minimal, full (default: minimal)
  -h, --help          Show this help

Boards:
$(list_boards | sed 's/^/  /')

Profiles:
  minimal   Basic system with systemd-networkd, IWD, XFCE (startx)
  full      Full desktop with NetworkManager, LightDM auto-login

Examples:
  $(basename "$0") sz3568-v1.2 build
  $(basename "$0") --profile full sz3568-v1.2 build
  $(basename "$0") sz3568-v1.2 info
EOF
}

# ============================================================================
# Docker handling (rootfs needs privileged for chroot/mount)
# ============================================================================

setup_qemu_binfmt() {
    # Skip if already in container
    [[ -f /.dockerenv ]] || [[ -n "$CONTAINER" ]] && return 0

    # Check if QEMU binfmt is registered
    if [[ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
        info "Setting up QEMU binfmt_misc for ARM64 emulation..."
        if ! docker run --rm --privileged multiarch/qemu-user-static --reset -p yes >/dev/null 2>&1; then
            error "Failed to register QEMU binfmt. Install qemu-user-static on host."
        fi
        log "QEMU binfmt registered for ARM64"
    fi
}

run_in_docker_if_needed() {
    [[ -f /.dockerenv ]] || [[ -n "$CONTAINER" ]] && return 0

    command -v docker &>/dev/null || {
        warn "Docker not found, running on host (requires sudo)"
        return 0
    }

    setup_qemu_binfmt

    local docker_image="rk3568-debian-builder"

    if ! docker image inspect "${docker_image}:latest" &>/dev/null 2>&1; then
        info "Building Docker image (one-time setup)..."
        DOCKER_BUILDKIT=1 docker build -t "${docker_image}:latest" \
            -f "${PROJECT_ROOT}/Dockerfile" "${PROJECT_ROOT}"
    fi

    # Create apt cache directories
    mkdir -p "${PROJECT_ROOT}/.cache/rootfs-apt-cache"
    mkdir -p "${PROJECT_ROOT}/.cache/rootfs-apt-lists"

    info "Running rootfs build in Docker (privileged for chroot)..."
    docker run --rm -it \
        --privileged \
        --network=host \
        -v "${PROJECT_ROOT}:/work" \
        -v "${PROJECT_ROOT}/.cache/rootfs-apt-cache:/apt-cache" \
        -v "${PROJECT_ROOT}/.cache/rootfs-apt-lists:/apt-lists" \
        -e CONTAINER=1 \
        -e PROFILE="${PROFILE}" \
        -e APT_CACHE_DIR=/apt-cache \
        -e APT_LISTS_DIR=/apt-lists \
        -w /work \
        "${docker_image}:latest" \
        "/work/scripts/build/rootfs.sh" "$@"

    # Fix ownership
    local user_id="${SUDO_UID:-$(id -u)}"
    local group_id="${SUDO_GID:-$(id -g)}"
    sudo chown -R "${user_id}:${group_id}" "${PROJECT_ROOT}/rootfs" 2>/dev/null || true

    exit $?
}

# ============================================================================
# Commands
# ============================================================================

cmd_build() {
    header "Building Rootfs for ${BOARD_NAME}"
    info "Profile: ${PROFILE}"
    info "Debian: ${DEBIAN_RELEASE}"

    run_in_docker_if_needed "$BOARD_NAME" build

    # Delegate to the existing rootfs builder
    # Pass PROFILE and board name
    PROFILE="${PROFILE}" "${PROJECT_ROOT}/scripts/build-debian-rootfs.sh" "${BOARD_NAME}"

    log "Rootfs build complete!"
}

cmd_clean() {
    header "Cleaning Rootfs Artifacts"

    if [[ -d "${ROOTFS_WORK}" ]]; then
        info "Removing ${ROOTFS_WORK}..."
        sudo rm -rf "${ROOTFS_WORK}"
    fi

    if [[ -f "${ROOTFS_IMAGE}" ]]; then
        info "Removing ${ROOTFS_IMAGE}..."
        rm -f "${ROOTFS_IMAGE}"
    fi

    # Note: preserving debootstrap cache
    if [[ -d "${ROOTFS_DIR}" ]]; then
        local cache_size
        cache_size=$(du -sh "${ROOTFS_DIR}"/debootstrap-*.tar.gz 2>/dev/null | cut -f1 || echo "0")
        info "Preserved debootstrap cache: ${cache_size}"
    fi

    log "Clean complete"
}

cmd_info() {
    header "Rootfs Build Configuration"

    show_board_info

    echo ""
    info "Rootfs Configuration:"
    kv "Debian" "${DEBIAN_RELEASE}"
    kv "Profile" "${PROFILE}"
    kv "Size" "${ROOTFS_SIZE}"
    kv "Work dir" "${ROOTFS_WORK}"
    kv "Image" "${ROOTFS_IMAGE}"

    echo ""
    info "Artifact Status:"
    check_rootfs_artifact
}

# ============================================================================
# Main
# ============================================================================

main() {
    local board=""
    local command=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --profile)
                PROFILE="$2"
                shift 2
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
        build) cmd_build ;;
        clean) cmd_clean ;;
        info)  cmd_info ;;
        *)     error "Unknown command: $command" ;;
    esac
}

main "$@"
