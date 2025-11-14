#!/bin/bash
set -e

# RK356X Rootfs Build Script
# Creates Debian-based root filesystem

BOARD="${1:-rock-3a}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${ROOT_DIR}/build"
OUTPUT_DIR="${ROOT_DIR}/output/rootfs"
CONFIG_DIR="${ROOT_DIR}/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Load board configuration
if [ -f "${CONFIG_DIR}/boards/${BOARD}.conf" ]; then
    log_info "Loading configuration for ${BOARD}"
    source "${CONFIG_DIR}/boards/${BOARD}.conf"
else
    log_warn "No configuration found for board: ${BOARD}, using defaults"
fi

# Set defaults
DEBIAN_RELEASE="${DEBIAN_RELEASE:-bookworm}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
ROOTFS_SIZE="${ROOTFS_SIZE:-2048}"  # Size in MB
HOSTNAME="${HOSTNAME:-${BOARD}}"
DEFAULT_USER="${DEFAULT_USER:-debian}"
DEFAULT_PASSWORD="${DEFAULT_PASSWORD:-debian}"

ROOTFS_DIR="${BUILD_DIR}/rootfs-${BOARD}"

mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

# Clean previous rootfs
if [ -d "${ROOTFS_DIR}" ]; then
    log_warn "Removing previous rootfs at ${ROOTFS_DIR}"
    # Unmount any mounted filesystems
    for mount in $(mount | grep "${ROOTFS_DIR}" | cut -d' ' -f3 | sort -r); do
        log_info "Unmounting $mount"
        umount -l "$mount" || true
    done
    rm -rf "${ROOTFS_DIR}"
fi

mkdir -p "${ROOTFS_DIR}"

# Install qemu-user-static for cross-arch chroot
log_info "Setting up binfmt for ARM64"
update-binfmts --enable qemu-aarch64

# Stage 1: Create base Debian rootfs with debootstrap
log_info "Creating base Debian ${DEBIAN_RELEASE} rootfs (this may take a while...)"
debootstrap --arch=arm64 --foreign \
    --include=systemd,systemd-sysv,dbus,udev,kmod,apt-utils \
    "${DEBIAN_RELEASE}" \
    "${ROOTFS_DIR}" \
    "${DEBIAN_MIRROR}"

# Copy qemu-aarch64-static for second stage
cp /usr/bin/qemu-aarch64-static "${ROOTFS_DIR}/usr/bin/"

# Stage 2: Complete debootstrap inside chroot
log_info "Running second stage debootstrap"
chroot "${ROOTFS_DIR}" /debootstrap/debootstrap --second-stage

# Configure apt sources
log_info "Configuring apt sources"
cat > "${ROOTFS_DIR}/etc/apt/sources.list" << EOF
deb ${DEBIAN_MIRROR} ${DEBIAN_RELEASE} main contrib non-free non-free-firmware
deb ${DEBIAN_MIRROR} ${DEBIAN_RELEASE}-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${DEBIAN_RELEASE}-security main contrib non-free non-free-firmware
EOF

# Mount pseudo filesystems for chroot
log_info "Mounting pseudo filesystems"
mount -t proc proc "${ROOTFS_DIR}/proc"
mount -t sysfs sysfs "${ROOTFS_DIR}/sys"
mount -o bind /dev "${ROOTFS_DIR}/dev"
mount -o bind /dev/pts "${ROOTFS_DIR}/dev/pts"

# Create cleanup function
cleanup() {
    log_info "Cleaning up mounts"
    umount -l "${ROOTFS_DIR}/proc" || true
    umount -l "${ROOTFS_DIR}/sys" || true
    umount -l "${ROOTFS_DIR}/dev/pts" || true
    umount -l "${ROOTFS_DIR}/dev" || true
}
trap cleanup EXIT

# Configure system inside chroot
log_info "Configuring system"
chroot "${ROOTFS_DIR}" /bin/bash << 'CHROOT_EOF'
set -e

# Update package list
apt-get update

# Install essential packages
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    locales \
    console-setup \
    keyboard-configuration \
    tzdata \
    ca-certificates \
    openssh-server \
    sudo \
    network-manager \
    iproute2 \
    iputils-ping \
    net-tools \
    wireless-tools \
    wpasupplicant \
    curl \
    wget \
    vim \
    nano \
    less \
    man-db \
    htop \
    rsync \
    psmisc \
    file \
    gnupg

# Configure locales
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

# Enable systemd services
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable ssh

CHROOT_EOF

# Set hostname
log_info "Setting hostname to ${HOSTNAME}"
echo "${HOSTNAME}" > "${ROOTFS_DIR}/etc/hostname"

cat > "${ROOTFS_DIR}/etc/hosts" << EOF
127.0.0.1   localhost
127.0.1.1   ${HOSTNAME}

::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

# Create default user
log_info "Creating default user: ${DEFAULT_USER}"
chroot "${ROOTFS_DIR}" /bin/bash << CHROOT_EOF
set -e

# Create user
useradd -m -s /bin/bash -G sudo,adm,systemd-journal,audio,video,plugdev,netdev ${DEFAULT_USER}
echo "${DEFAULT_USER}:${DEFAULT_PASSWORD}" | chpasswd

# Set root password
echo "root:${DEFAULT_PASSWORD}" | chpasswd

CHROOT_EOF

# Configure fstab
log_info "Configuring fstab"
cat > "${ROOTFS_DIR}/etc/fstab" << 'EOF'
# <file system> <mount point> <type> <options> <dump> <pass>
/dev/mmcblk0p2  /               ext4    defaults,noatime    0   1
/dev/mmcblk0p1  /boot           ext4    defaults,noatime    0   2
tmpfs           /tmp            tmpfs   defaults,nosuid     0   0
EOF

# Configure network
log_info "Configuring network"
cat > "${ROOTFS_DIR}/etc/systemd/network/20-wired.network" << 'EOF'
[Match]
Name=eth* en*

[Network]
DHCP=yes
EOF

cat > "${ROOTFS_DIR}/etc/systemd/network/25-wireless.network" << 'EOF'
[Match]
Name=wlan*

[Network]
DHCP=yes
EOF

# Configure serial console
log_info "Configuring serial console"
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/serial-getty@ttyS2.service.d"
cat > "${ROOTFS_DIR}/etc/systemd/system/serial-getty@ttyS2.service.d/override.conf" << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud 1500000,115200,38400,9600 %I $TERM
EOF

# Enable serial console
chroot "${ROOTFS_DIR}" systemctl enable serial-getty@ttyS2.service

# Copy custom scripts if they exist
if [ -d "${CONFIG_DIR}/rootfs-overlay/${BOARD}" ]; then
    log_info "Copying custom overlay files"
    cp -a "${CONFIG_DIR}/rootfs-overlay/${BOARD}/." "${ROOTFS_DIR}/"
fi

if [ -d "${CONFIG_DIR}/rootfs-overlay/common" ]; then
    log_info "Copying common overlay files"
    cp -a "${CONFIG_DIR}/rootfs-overlay/common/." "${ROOTFS_DIR}/"
fi

# Run custom setup script if it exists
if [ -f "${CONFIG_DIR}/scripts/${BOARD}-setup.sh" ]; then
    log_info "Running board-specific setup script"
    cp "${CONFIG_DIR}/scripts/${BOARD}-setup.sh" "${ROOTFS_DIR}/tmp/setup.sh"
    chmod +x "${ROOTFS_DIR}/tmp/setup.sh"
    chroot "${ROOTFS_DIR}" /tmp/setup.sh
    rm "${ROOTFS_DIR}/tmp/setup.sh"
fi

# Clean up
log_info "Cleaning up"
chroot "${ROOTFS_DIR}" /bin/bash << 'CHROOT_EOF'
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm -rf /var/tmp/*
history -c
CHROOT_EOF

# Remove qemu-aarch64-static
rm -f "${ROOTFS_DIR}/usr/bin/qemu-aarch64-static"

# Unmount filesystems (cleanup function will handle this)
cleanup
trap - EXIT

# Create tarball
log_info "Creating rootfs tarball"
ROOTFS_TARBALL="${OUTPUT_DIR}/rootfs-${BOARD}-${DEBIAN_RELEASE}.tar.gz"
tar -czf "${ROOTFS_TARBALL}" -C "${ROOTFS_DIR}" .

# Create version file
cat > "${OUTPUT_DIR}/VERSION" << EOF
Board: ${BOARD}
Debian Release: ${DEBIAN_RELEASE}
Build Date: $(date)
Default User: ${DEFAULT_USER}
Default Password: ${DEFAULT_PASSWORD}
Hostname: ${HOSTNAME}
EOF

# Create README
cat > "${OUTPUT_DIR}/README.md" << EOF
# Rootfs for ${BOARD}

Built: $(date)
Debian Release: ${DEBIAN_RELEASE}

## Default Credentials

**User:** ${DEFAULT_USER}
**Password:** ${DEFAULT_PASSWORD}

**Root password:** ${DEFAULT_PASSWORD}

## Files

- \`rootfs-${BOARD}-${DEBIAN_RELEASE}.tar.gz\` - Complete root filesystem
- \`VERSION\` - Build information

## Installation

### Extract to partition:
\`\`\`bash
# Format partition
sudo mkfs.ext4 /dev/mmcblk0p2

# Mount
sudo mount /dev/mmcblk0p2 /mnt

# Extract
sudo tar -xzf rootfs-${BOARD}-${DEBIAN_RELEASE}.tar.gz -C /mnt

# Unmount
sudo umount /mnt
\`\`\`

## First Boot

After first boot:
1. Change default passwords: \`passwd\` and \`sudo passwd root\`
2. Configure network if needed: \`nmtui\` or edit \`/etc/systemd/network/\`
3. Update system: \`sudo apt update && sudo apt upgrade\`

## Included Packages

- OpenSSH server (enabled)
- NetworkManager (enabled)
- sudo
- Basic utilities (vim, nano, htop, etc.)

## Console Access

Serial console available on ttyS2 at 1500000 baud (RK356X default)
EOF

log_info "Rootfs build complete!"
log_info "Output: ${ROOTFS_TARBALL}"
log_info "Size: $(du -h ${ROOTFS_TARBALL} | cut -f1)"
