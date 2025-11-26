#!/bin/bash
set -e

# Debian/Ubuntu Rootfs Build Script for RK3568
# Based on Firefly guide but updated for Ubuntu 24.04 LTS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Auto-use Docker if not already in container
if [ ! -f /.dockerenv ] && [ -z "$CONTAINER" ]; then
    if command -v docker &>/dev/null; then
        # Ensure QEMU binfmt is registered on host (required for ARM64 chroot)
        if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
            echo "==> Setting up QEMU binfmt_misc for ARM64 emulation..."
            # Register QEMU for ARM64 using Docker (no host qemu-user-static needed)
            if ! docker run --rm --privileged multiarch/qemu-user-static --reset -p yes >/dev/null 2>&1; then
                echo "⚠ Failed to register QEMU binfmt via Docker"
                echo "  Trying direct registration (requires qemu-user-static on host)..."
                if command -v qemu-aarch64-static &>/dev/null; then
                    sudo update-binfmts --enable qemu-aarch64 2>/dev/null || {
                        echo "✗ QEMU binfmt registration failed"
                        echo "  Install with: sudo apt install qemu-user-static binfmt-support"
                        exit 1
                    }
                else
                    echo "✗ qemu-user-static not installed on host"
                    echo "  Install with: sudo apt install qemu-user-static binfmt-support"
                    exit 1
                fi
            fi
            echo "✓ QEMU binfmt registered for ARM64 emulation"
        fi

        # Build Docker image if needed
        DOCKER_IMAGE="rk3568-debian-builder"
        if ! docker image inspect "${DOCKER_IMAGE}:latest" &>/dev/null 2>&1; then
            echo "==> Building Docker image (one-time setup, with apt caching)..."
            DOCKER_BUILDKIT=1 docker build -t "${DOCKER_IMAGE}:latest" -f "${PROJECT_ROOT}/Dockerfile" "${PROJECT_ROOT}"
        fi

        # Re-exec this script in Docker (needs --privileged for chroot/mount)
        # Must run as root for mount/chroot operations
        echo "==> Running rootfs build in Docker container (privileged for chroot)..."
        docker run --rm -it \
            --privileged \
            -v "${PROJECT_ROOT}:/work" \
            -e CONTAINER=1 \
            -w /work \
            "${DOCKER_IMAGE}:latest" \
            "/work/scripts/$(basename "$0")" "$@"

        # Fix ownership of created files
        USER_ID="${SUDO_UID:-$(id -u)}"
        GROUP_ID="${SUDO_GID:-$(id -g)}"
        sudo chown -R "${USER_ID}:${GROUP_ID}" "${PROJECT_ROOT}/rootfs" 2>/dev/null || true
        exit $?
    else
        echo "⚠ Docker not found, running on host (requires sudo + build dependencies)"
    fi
fi

# Configuration
UBUNTU_VERSION="24.04.3"
UBUNTU_RELEASE="noble"
UBUNTU_BASE_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_RELEASE}/release"
UBUNTU_BASE="ubuntu-base-${UBUNTU_VERSION}-base-arm64.tar.gz"

ROOTFS_DIR="${PROJECT_ROOT}/rootfs"
ROOTFS_WORK="${ROOTFS_DIR}/work"
ROOTFS_IMAGE="${ROOTFS_DIR}/debian-rootfs.img"
ROOTFS_SIZE="4G"  # Adjust as needed

BOARD="${1:-rk3568_sz3568}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

# Use sudo only when not in Docker (Docker runs with sufficient privileges)
maybe_sudo() {
    if [ -f /.dockerenv ] || [ -n "$CONTAINER" ]; then
        "$@"
    else
        command sudo "$@"
    fi
}

# Redirect output in quiet mode
quiet_run() {
    if [ "$QUIET_MODE" = "true" ]; then
        "$@" > /dev/null 2>&1
    else
        "$@"
    fi
}

check_deps() {
    # Skip dependency check if running in Docker (dependencies are in Dockerfile)
    if [ -f /.dockerenv ] || [ -n "$CONTAINER" ]; then
        log "Running in Docker container (dependencies pre-installed)"
        return 0
    fi

    log "Checking dependencies..."

    local deps=(qemu-user-static debootstrap wget)
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing dependencies: ${missing[*]}\nInstall with: sudo apt install ${missing[*]}"
    fi
}

download_ubuntu_base() {
    log "Downloading Ubuntu Base ${UBUNTU_VERSION}..."

    mkdir -p "${ROOTFS_DIR}"
    cd "${ROOTFS_DIR}"

    if [ ! -f "${UBUNTU_BASE}" ]; then
        wget "${UBUNTU_BASE_URL}/${UBUNTU_BASE}" || error "Failed to download Ubuntu Base"
    else
        log "Ubuntu Base already downloaded"
    fi
}

extract_rootfs() {
    log "Extracting rootfs..."

    rm -rf "${ROOTFS_WORK}"
    mkdir -p "${ROOTFS_WORK}"

    if [ "$QUIET_MODE" = "true" ]; then
        echo -e "${YELLOW}▸${NC} Extracting Ubuntu base rootfs"
        maybe_sudo tar -xzf "${ROOTFS_DIR}/${UBUNTU_BASE}" -C "${ROOTFS_WORK}" 2>&1 | grep -v "tar:"
    else
        maybe_sudo tar -xzf "${ROOTFS_DIR}/${UBUNTU_BASE}" -C "${ROOTFS_WORK}"
    fi
}

setup_qemu() {
    log "Setting up QEMU emulation..."

    maybe_sudo cp /usr/bin/qemu-aarch64-static "${ROOTFS_WORK}/usr/bin/"

    # DNS resolution
    maybe_sudo cp /etc/resolv.conf "${ROOTFS_WORK}/etc/resolv.conf"
}

customize_rootfs() {
    log "Customizing rootfs with chroot..."

    # Create customization script
    cat << 'EOF' | maybe_sudo tee "${ROOTFS_WORK}/tmp/customize.sh" > /dev/null
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Update package lists
apt-get update

# Install essential packages
apt-get install -y \
    systemd systemd-sysv \
    network-manager \
    openssh-server \
    sudo \
    ca-certificates \
    locales \
    tzdata

# Install network firmware and tools
apt-get install -y \
    linux-firmware \
    firmware-realtek \
    wireless-tools \
    wpasupplicant \
    iw \
    rfkill

# Generate locales
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Install XFCE desktop
apt-get install -y \
    xfce4 \
    xfce4-terminal \
    lightdm \
    xinit \
    x11-xserver-utils

# Install graphics and multimedia
apt-get install -y \
    libdrm2 \
    mesa-utils \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav

# Install browser (WebKitGTK-based)
apt-get install -y \
    epiphany-browser

# Mali GPU support will be installed via .deb package in post-install step
echo "Mali GPU package will be installed separately"

# Install utilities
apt-get install -y \
    vim \
    git \
    wget \
    curl \
    htop \
    net-tools \
    ethtool \
    i2c-tools \
    usbutils \
    pciutils

# Create user
useradd -m -s /bin/bash -G sudo,video,audio,dialout rock
echo "rock:rock" | chpasswd
echo "root:root" | chpasswd

# Enable services
systemctl enable NetworkManager
systemctl enable lightdm
systemctl enable ssh

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "Rootfs customization complete"
EOF

    maybe_sudo chmod +x "${ROOTFS_WORK}/tmp/customize.sh"

    # Mount proc, sys, dev for chroot
    maybe_sudo mount -t proc /proc "${ROOTFS_WORK}/proc"
    maybe_sudo mount -t sysfs /sys "${ROOTFS_WORK}/sys"
    maybe_sudo mount --bind /dev "${ROOTFS_WORK}/dev"
    maybe_sudo mount --bind /dev/pts "${ROOTFS_WORK}/dev/pts"

    # Run customization
    if [ "$QUIET_MODE" = "true" ]; then
        echo -e "${YELLOW}▸${NC} Installing packages in chroot (systemd, NetworkManager, XFCE, etc)"
        maybe_sudo chroot "${ROOTFS_WORK}" /bin/bash /tmp/customize.sh > /dev/null 2>&1 || {
            maybe_sudo umount -lf "${ROOTFS_WORK}/proc" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/sys" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/dev/pts" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/dev" || true
            error "Customization failed"
        }
    else
        maybe_sudo chroot "${ROOTFS_WORK}" /bin/bash /tmp/customize.sh || {
            maybe_sudo umount -lf "${ROOTFS_WORK}/proc" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/sys" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/dev/pts" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/dev" || true
            error "Customization failed"
        }
    fi

    # Cleanup mounts
    maybe_sudo umount -lf "${ROOTFS_WORK}/proc" || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/sys" || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/dev/pts" || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/dev" || true
}

install_mali_gpu() {
    log "Installing Mali GPU drivers..."

    # Mali G52 package URL (from Kylinos archive - compatible with RK3568)
    local mali_pkg="libmali-bifrost-g52-g13p0-x11-wayland-gbm_1.9-1rk6_arm64.deb"
    local mali_url="http://archive.kylinos.cn/kylin/KYLIN-ALL/pool/main/libm/libmali/${mali_pkg}"

    # Download Mali package
    mkdir -p "${ROOTFS_DIR}/mali-pkg"
    if [ ! -f "${ROOTFS_DIR}/mali-pkg/${mali_pkg}" ]; then
        log "Downloading Mali GPU package..."
        wget -P "${ROOTFS_DIR}/mali-pkg" "${mali_url}" || {
            warn "Failed to download Mali package from Kylinos"
            warn "You can manually download and install later"
            return
        }
    fi

    # Install to rootfs via chroot
    log "Installing Mali GPU package to rootfs..."
    maybe_sudo cp "${ROOTFS_DIR}/mali-pkg/${mali_pkg}" "${ROOTFS_WORK}/tmp/"
    maybe_sudo cp /usr/bin/qemu-aarch64-static "${ROOTFS_WORK}/usr/bin/" || true

    if [ "$QUIET_MODE" = "true" ]; then
        echo -e "${YELLOW}▸${NC} Installing Mali Bifrost G52 driver"
        maybe_sudo chroot "${ROOTFS_WORK}" /bin/bash > /dev/null 2>&1 << 'CHROOT_EOF'
set -e
cd /tmp
dpkg -i *.deb || apt-get install -f -y
rm -f /tmp/*.deb
CHROOT_EOF
    else
        maybe_sudo chroot "${ROOTFS_WORK}" /bin/bash << 'CHROOT_EOF'
set -e
cd /tmp
echo "Installing Mali GPU driver..."
dpkg -i *.deb || apt-get install -f -y
rm -f /tmp/*.deb
echo "Mali GPU driver installed"
CHROOT_EOF
    fi

    log "✓ Mali GPU installed: libmali-bifrost-g52-g13p0"
}

create_image() {
    log "Creating rootfs image..."

    # Calculate actual size needed
    local rootfs_size=$(sudo du -sb "${ROOTFS_WORK}" | awk '{print $1}')
    local image_size=$((rootfs_size * 12 / 10))  # 120% of actual size

    log "Rootfs size: $((rootfs_size / 1024 / 1024))MB, Image size: $((image_size / 1024 / 1024))MB"

    # Create sparse image
    dd if=/dev/zero of="${ROOTFS_IMAGE}" bs=1 count=0 seek=${image_size} 2>/dev/null

    # Create ext4 filesystem
    if [ "$QUIET_MODE" = "true" ]; then
        echo -e "${YELLOW}▸${NC} Creating ext4 filesystem"
        maybe_sudo mkfs.ext4 -L "rootfs" "${ROOTFS_IMAGE}" > /dev/null 2>&1
    else
        maybe_sudo mkfs.ext4 -L "rootfs" "${ROOTFS_IMAGE}"
    fi

    # Mount and copy
    local mount_point="${ROOTFS_DIR}/mnt"
    mkdir -p "${mount_point}"
    maybe_sudo mount "${ROOTFS_IMAGE}" "${mount_point}"

    [ "$QUIET_MODE" = "true" ] && echo -e "${YELLOW}▸${NC} Copying rootfs to image"
    maybe_sudo cp -a "${ROOTFS_WORK}"/* "${mount_point}/"

    maybe_sudo umount "${mount_point}"

    # Optimize
    if [ "$QUIET_MODE" = "true" ]; then
        echo -e "${YELLOW}▸${NC} Optimizing filesystem"
        maybe_sudo e2fsck -fy "${ROOTFS_IMAGE}" > /dev/null 2>&1 || true
        maybe_sudo resize2fs -M "${ROOTFS_IMAGE}" > /dev/null 2>&1
    else
        maybe_sudo e2fsck -fy "${ROOTFS_IMAGE}" || true
        maybe_sudo resize2fs -M "${ROOTFS_IMAGE}"
    fi

    log "Rootfs image created: ${ROOTFS_IMAGE}"
}

cleanup() {
    log "Cleaning up..."

    # Ensure everything is unmounted
    maybe_sudo umount -lf "${ROOTFS_WORK}/proc" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/sys" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/dev/pts" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/dev" 2>/dev/null || true

    if [ "${KEEP_WORK:-0}" != "1" ]; then
        maybe_sudo rm -rf "${ROOTFS_WORK}"
        log "Work directory removed (set KEEP_WORK=1 to preserve)"
    fi
}

main() {
    log "Building Debian rootfs for RK3568"

    check_deps
    download_ubuntu_base
    extract_rootfs
    setup_qemu
    customize_rootfs
    install_mali_gpu
    create_image
    cleanup

    log "✓ Build complete!"
    log "Rootfs image: ${ROOTFS_IMAGE}"
    log ""
    log "Next steps:"
    log "1. Build kernel with: ./scripts/build-kernel.sh"
    log "2. Flash to SD card with: ./scripts/flash-image.sh"
}

trap cleanup EXIT
main "$@"
