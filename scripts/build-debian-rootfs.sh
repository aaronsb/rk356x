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

        # Create apt cache directories on host for persistence across builds
        mkdir -p "${PROJECT_ROOT}/.cache/rootfs-apt-cache"
        mkdir -p "${PROJECT_ROOT}/.cache/rootfs-apt-lists"

        docker run --rm -it \
            --privileged \
            -v "${PROJECT_ROOT}:/work" \
            -v "${PROJECT_ROOT}/.cache/rootfs-apt-cache:/apt-cache" \
            -v "${PROJECT_ROOT}/.cache/rootfs-apt-lists:/apt-lists" \
            -e CONTAINER=1 \
            -e APT_CACHE_DIR=/apt-cache \
            -e APT_LISTS_DIR=/apt-lists \
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
PROFILE="${PROFILE:-minimal}"  # "minimal" or "full"

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
    cat << EOF | maybe_sudo tee "${ROOTFS_WORK}/tmp/customize.sh" > /dev/null
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PROFILE="${PROFILE}"

# Disable Python byte-compilation to avoid QEMU segfaults during package installation
export PYTHONDONTWRITEBYTECODE=1
export DEB_PYTHON_INSTALL_LAYOUT=deb_system

# Update package lists
apt-get update

# Use dpkg-divert to permanently redirect py3compile to our stub
# This prevents any package from installing the real py3compile
# Bytecode will be generated on first import when running on real ARM hardware
dpkg-divert --add --rename --divert /usr/bin/py3compile.real /usr/bin/py3compile
dpkg-divert --add --rename --divert /usr/bin/py3clean.real /usr/bin/py3clean

# Create stub py3compile that does nothing
cat > /usr/bin/py3compile << 'PYCOMPILE_STUB'
#!/bin/sh
# Stub to prevent Python segfaults in QEMU during package installation
# Bytecode will be generated on first import on real hardware
exit 0
PYCOMPILE_STUB
chmod +x /usr/bin/py3compile

# py3clean can just be a symlink to py3compile
ln -sf /usr/bin/py3compile /usr/bin/py3clean

# Install essential packages
apt-get install -y \
    systemd systemd-sysv \
    openssh-server \
    sudo \
    ca-certificates \
    locales \
    tzdata

# Network management
if [ "$PROFILE" = "full" ]; then
    # Full profile: NetworkManager with GUI applet
    apt-get install -y network-manager
else
    # Minimal profile: systemd-networkd (no GNOME dependencies)
    apt-get install -y \
        systemd-resolved \
        iproute2 \
        dhcpcd5
fi

# Install network firmware and tools
# Note: Realtek firmware is included in linux-firmware on Ubuntu
if [ "$PROFILE" = "full" ]; then
    # Full profile: all firmware
    apt-get install -y \
        linux-firmware \
        wireless-tools \
        wpasupplicant \
        iw \
        rfkill
else
    # Minimal profile: only essential WiFi tools (firmware from kernel modules)
    apt-get install -y \
        wpasupplicant \
        iw
fi

# Generate locales
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Install XFCE desktop
if [ "$PROFILE" = "full" ]; then
    # Full profile: complete XFCE with all plugins and display manager
    apt-get install -y \
        xfce4 \
        xfce4-terminal \
        lightdm \
        xinit \
        x11-xserver-utils
else
    # Minimal profile: core XFCE only (no extra plugins, games, etc)
    apt-get install -y \
        xfce4-session \
        xfwm4 \
        xfdesktop4 \
        xfce4-panel \
        xfce4-settings \
        xfce4-terminal \
        xserver-xorg-core \
        xserver-xorg-input-libinput \
        xserver-xorg-video-fbdev \
        xinit \
        dbus-x11
fi

# Install graphics and multimedia
apt-get install -y \
    libdrm2 \
    mesa-utils \
    libgles2 \
    libegl1

if [ "$PROFILE" = "full" ]; then
    # Full profile: add GStreamer for media playback
    apt-get install -y \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-ugly \
        gstreamer1.0-libav
fi

# Install browser (WebKitGTK-based)
apt-get install -y \
    epiphany-browser

# Mali GPU support will be installed via .deb package in post-install step
echo "Mali GPU package will be installed separately"

# Install utilities
if [ "$PROFILE" = "full" ]; then
    # Full profile: development and debugging tools
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
else
    # Minimal profile: essential tools only
    apt-get install -y \
        nano \
        wget \
        htop \
        ethtool
fi

# Create user
useradd -m -s /bin/bash -G sudo,video,audio,dialout rock
echo "rock:rock" | chpasswd
echo "root:root" | chpasswd

# Enable services
if [ "$PROFILE" = "full" ]; then
    systemctl enable NetworkManager
    systemctl enable lightdm
else
    systemctl enable systemd-networkd
    systemctl enable systemd-resolved

    # Configure ethernet for DHCP (systemd-networkd)
    mkdir -p /etc/systemd/network
    cat > /etc/systemd/network/20-wired.network << 'NETCONF'
[Match]
Name=eth* en*

[Network]
DHCP=yes
DNSSEC=no

[DHCPv4]
UseDNS=yes
NETCONF
fi
systemctl enable ssh

# Create first-boot Python bytecode compilation service
cat > /etc/systemd/system/py3compile-first-boot.service << 'FIRSTBOOT_SERVICE'
[Unit]
Description=Compile Python bytecode on first boot
After=multi-user.target
ConditionPathExists=!/var/lib/py3compile-first-boot.done

[Service]
Type=oneshot
ExecStartPre=/bin/echo "First boot: Compiling Python bytecode (this may take a few minutes)..."
ExecStart=/usr/bin/python3 -m compileall -q /usr
ExecStartPost=/bin/touch /var/lib/py3compile-first-boot.done
ExecStartPost=/bin/systemctl disable py3compile-first-boot.service
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
FIRSTBOOT_SERVICE

systemctl enable py3compile-first-boot.service

# Remove py3compile diversion so real hardware uses normal py3compile
dpkg-divert --remove /usr/bin/py3compile
dpkg-divert --remove /usr/bin/py3clean

# Note: apt cache is NOT cleaned here - it's bind-mounted for reuse across builds

echo "Rootfs customization complete"
EOF

    maybe_sudo chmod +x "${ROOTFS_WORK}/tmp/customize.sh"

    # Mount proc, sys, dev for chroot
    maybe_sudo mount -t proc /proc "${ROOTFS_WORK}/proc"
    maybe_sudo mount -t sysfs /sys "${ROOTFS_WORK}/sys"
    maybe_sudo mount --bind /dev "${ROOTFS_WORK}/dev"
    maybe_sudo mount --bind /dev/pts "${ROOTFS_WORK}/dev/pts"

    # Mount apt cache directories if available (for package caching across builds)
    if [ -n "$APT_CACHE_DIR" ] && [ -d "$APT_CACHE_DIR" ]; then
        maybe_sudo mkdir -p "${ROOTFS_WORK}/var/cache/apt"
        maybe_sudo mount --bind "$APT_CACHE_DIR" "${ROOTFS_WORK}/var/cache/apt"
    fi
    if [ -n "$APT_LISTS_DIR" ] && [ -d "$APT_LISTS_DIR" ]; then
        maybe_sudo mkdir -p "${ROOTFS_WORK}/var/lib/apt/lists"
        maybe_sudo mount --bind "$APT_LISTS_DIR" "${ROOTFS_WORK}/var/lib/apt/lists"
    fi

    # Run customization
    if [ "$QUIET_MODE" = "true" ]; then
        echo -e "${YELLOW}▸${NC} Installing packages in chroot (systemd, NetworkManager, XFCE, etc)"
        maybe_sudo chroot "${ROOTFS_WORK}" /bin/bash /tmp/customize.sh > /dev/null 2>&1 || {
            maybe_sudo umount -lf "${ROOTFS_WORK}/var/cache/apt" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/var/lib/apt/lists" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/proc" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/sys" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/dev/pts" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/dev" || true
            error "Customization failed"
        }
    else
        maybe_sudo chroot "${ROOTFS_WORK}" /bin/bash /tmp/customize.sh || {
            maybe_sudo umount -lf "${ROOTFS_WORK}/var/cache/apt" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/var/lib/apt/lists" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/proc" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/sys" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/dev/pts" || true
            maybe_sudo umount -lf "${ROOTFS_WORK}/dev" || true
            error "Customization failed"
        }
    fi

    # Cleanup mounts
    maybe_sudo umount -lf "${ROOTFS_WORK}/var/cache/apt" || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/var/lib/apt/lists" || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/proc" || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/sys" || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/dev/pts" || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/dev" || true
}

install_mali_gpu() {
    log "Installing Mali GPU drivers..."

    # Mali G52 package URL (from OrangePi RK356x repository)
    local mali_pkg="libmali-bifrost-g52-g13p0-x11-gbm_1.9-1_arm64.deb"
    local mali_url="https://github.com/orangepi-xunlong/rk-rootfs-build/raw/rk356x_packages/common/libmali/${mali_pkg}"

    # Download Mali package
    mkdir -p "${ROOTFS_DIR}/mali-pkg"
    if [ ! -f "${ROOTFS_DIR}/mali-pkg/${mali_pkg}" ]; then
        log "Downloading Mali GPU package..."
        wget -P "${ROOTFS_DIR}/mali-pkg" "${mali_url}" || {
            warn "Failed to download Mali package from OrangePi repository"
            warn "GPU acceleration may not work without this package"
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
    local rootfs_size=$(maybe_sudo du -sb "${ROOTFS_WORK}" | awk '{print $1}')
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
    maybe_sudo umount -lf "${ROOTFS_WORK}/var/cache/apt" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/var/lib/apt/lists" 2>/dev/null || true
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
    log "Profile: ${PROFILE}"
    log ""

    check_deps
    download_ubuntu_base
    extract_rootfs
    setup_qemu
    customize_rootfs
    install_mali_gpu
    create_image
    cleanup

    log ""
    log "✓ Build complete!"
    log "Profile: ${PROFILE}"
    log "Rootfs image: ${ROOTFS_IMAGE}"
    log ""
    if [ "$PROFILE" = "minimal" ]; then
        log "Minimal profile notes:"
        log "  - No display manager (lightdm): Login and run 'startx' to start XFCE"
        log "  - No GStreamer plugins: Install if you need video playback"
        log "  - To build full profile: PROFILE=full ./scripts/build-debian-rootfs.sh"
        log ""
    fi
    log "Next steps:"
    log "1. Build kernel with: ./scripts/build-kernel.sh"
    log "2. Flash to SD card with: ./scripts/flash-image.sh"
}

trap cleanup EXIT
main "$@"
