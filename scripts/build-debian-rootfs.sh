#!/bin/bash
set -e

# Debian/Ubuntu Rootfs Build Script for RK3568
# Based on Firefly guide but updated for Ubuntu 24.04 LTS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Auto-use Docker if not already in container
if [ ! -f /.dockerenv ] && [ -z "$CONTAINER" ]; then
    if command -v docker &>/dev/null; then
        # Build Docker image if needed
        DOCKER_IMAGE="rk3568-debian-builder"
        if ! docker image inspect "${DOCKER_IMAGE}:latest" &>/dev/null 2>&1; then
            echo "==> Building Docker image (one-time setup)..."
            docker build -t "${DOCKER_IMAGE}:latest" -f "${PROJECT_ROOT}/Dockerfile" "${PROJECT_ROOT}"
        fi

        # Re-exec this script in Docker (needs --privileged for chroot/mount)
        echo "==> Running rootfs build in Docker container (privileged for chroot)..."
        exec docker run --rm -it \
            --privileged \
            -v "${PROJECT_ROOT}:/work" \
            -e CONTAINER=1 \
            -w /work \
            "${DOCKER_IMAGE}:latest" \
            "/work/scripts/$(basename "$0")" "$@"
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

check_deps() {
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

    sudo tar -xzf "${ROOTFS_DIR}/${UBUNTU_BASE}" -C "${ROOTFS_WORK}"
}

setup_qemu() {
    log "Setting up QEMU emulation..."

    sudo cp /usr/bin/qemu-aarch64-static "${ROOTFS_WORK}/usr/bin/"

    # DNS resolution
    sudo cp /etc/resolv.conf "${ROOTFS_WORK}/etc/resolv.conf"
}

customize_rootfs() {
    log "Customizing rootfs with chroot..."

    # Create customization script
    cat << 'EOF' | sudo tee "${ROOTFS_WORK}/tmp/customize.sh" > /dev/null
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

    sudo chmod +x "${ROOTFS_WORK}/tmp/customize.sh"

    # Mount proc, sys, dev for chroot
    sudo mount -t proc /proc "${ROOTFS_WORK}/proc"
    sudo mount -t sysfs /sys "${ROOTFS_WORK}/sys"
    sudo mount --bind /dev "${ROOTFS_WORK}/dev"
    sudo mount --bind /dev/pts "${ROOTFS_WORK}/dev/pts"

    # Run customization
    sudo chroot "${ROOTFS_WORK}" /tmp/customize.sh || {
        sudo umount -lf "${ROOTFS_WORK}/proc" || true
        sudo umount -lf "${ROOTFS_WORK}/sys" || true
        sudo umount -lf "${ROOTFS_WORK}/dev/pts" || true
        sudo umount -lf "${ROOTFS_WORK}/dev" || true
        error "Customization failed"
    }

    # Cleanup mounts
    sudo umount -lf "${ROOTFS_WORK}/proc" || true
    sudo umount -lf "${ROOTFS_WORK}/sys" || true
    sudo umount -lf "${ROOTFS_WORK}/dev/pts" || true
    sudo umount -lf "${ROOTFS_WORK}/dev" || true
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
    sudo cp "${ROOTFS_DIR}/mali-pkg/${mali_pkg}" "${ROOTFS_WORK}/tmp/"
    sudo cp /usr/bin/qemu-aarch64-static "${ROOTFS_WORK}/usr/bin/" || true

    sudo chroot "${ROOTFS_WORK}" /bin/bash << 'CHROOT_EOF'
set -e
cd /tmp
echo "Installing Mali GPU driver..."
dpkg -i *.deb || apt-get install -f -y
rm -f /tmp/*.deb
echo "Mali GPU driver installed"
CHROOT_EOF

    log "✓ Mali GPU installed: libmali-bifrost-g52-g13p0"
}

create_image() {
    log "Creating rootfs image..."

    # Calculate actual size needed
    local rootfs_size=$(sudo du -sb "${ROOTFS_WORK}" | awk '{print $1}')
    local image_size=$((rootfs_size * 12 / 10))  # 120% of actual size

    log "Rootfs size: $((rootfs_size / 1024 / 1024))MB, Image size: $((image_size / 1024 / 1024))MB"

    # Create sparse image
    dd if=/dev/zero of="${ROOTFS_IMAGE}" bs=1 count=0 seek=${image_size}

    # Create ext4 filesystem
    sudo mkfs.ext4 -L "rootfs" "${ROOTFS_IMAGE}"

    # Mount and copy
    local mount_point="${ROOTFS_DIR}/mnt"
    mkdir -p "${mount_point}"
    sudo mount "${ROOTFS_IMAGE}" "${mount_point}"

    sudo cp -a "${ROOTFS_WORK}"/* "${mount_point}/"

    sudo umount "${mount_point}"

    # Optimize
    sudo e2fsck -fy "${ROOTFS_IMAGE}" || true
    sudo resize2fs -M "${ROOTFS_IMAGE}"

    log "Rootfs image created: ${ROOTFS_IMAGE}"
}

cleanup() {
    log "Cleaning up..."

    # Ensure everything is unmounted
    sudo umount -lf "${ROOTFS_WORK}/proc" 2>/dev/null || true
    sudo umount -lf "${ROOTFS_WORK}/sys" 2>/dev/null || true
    sudo umount -lf "${ROOTFS_WORK}/dev/pts" 2>/dev/null || true
    sudo umount -lf "${ROOTFS_WORK}/dev" 2>/dev/null || true

    if [ "${KEEP_WORK:-0}" != "1" ]; then
        sudo rm -rf "${ROOTFS_WORK}"
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
