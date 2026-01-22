#!/bin/bash
# Standalone rootfs build script
# Builds Debian rootfs for RK3568 boards

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Configuration
DEBIAN_RELEASE="bookworm"
DEBIAN_MIRROR="http://deb.debian.org/debian"
ROOTFS_DIR="${PROJECT_ROOT}/rootfs"
ROOTFS_WORK="${ROOTFS_DIR}/work"
ROOTFS_IMAGE="${ROOTFS_DIR}/debian-rootfs.img"
DEBOOTSTRAP_CACHE="${ROOTFS_DIR}/debootstrap-${DEBIAN_RELEASE}-arm64.tar.gz"
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
  minimal   Basic system with systemd-networkd, IWD, Sway (Wayland)
  full      Full desktop with NetworkManager, extra apps

Examples:
  $(basename "$0") sz3568-v1.2 build
  $(basename "$0") --profile full sz3568-v1.2 build
  $(basename "$0") sz3568-v1.2 info
EOF
}

# ============================================================================
# Docker handling
# ============================================================================

setup_qemu_binfmt() {
    [[ -f /.dockerenv ]] || [[ -n "$CONTAINER" ]] && return 0

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

    mkdir -p "${PROJECT_ROOT}/.cache/rootfs-apt-cache"
    mkdir -p "${PROJECT_ROOT}/.cache/rootfs-apt-lists"

    info "Running rootfs build in Docker (privileged for chroot)..."
    local docker_flags="-i"
    [[ -t 0 ]] && docker_flags="-it"

    docker run --rm ${docker_flags} \
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

    local user_id="${SUDO_UID:-$(id -u)}"
    local group_id="${SUDO_GID:-$(id -g)}"
    sudo chown -R "${user_id}:${group_id}" "${PROJECT_ROOT}/rootfs" 2>/dev/null || true

    exit $?
}

# ============================================================================
# Helper functions
# ============================================================================

maybe_sudo() {
    if [[ -f /.dockerenv ]] || [[ -n "$CONTAINER" ]]; then
        "$@"
    else
        command sudo "$@"
    fi
}

# ============================================================================
# Debootstrap
# ============================================================================

create_debian_rootfs() {
    info "Creating Debian ${DEBIAN_RELEASE} base system..."

    rm -rf "${ROOTFS_WORK}"
    mkdir -p "${ROOTFS_DIR}"

    if [[ -f "${DEBOOTSTRAP_CACHE}" ]]; then
        log "Using cached debootstrap tarball"
        mkdir -p "${ROOTFS_WORK}"
        maybe_sudo tar -xzf "${DEBOOTSTRAP_CACHE}" -C "${ROOTFS_WORK}"
        return 0
    fi

    info "No cache found, running debootstrap..."
    maybe_sudo debootstrap --arch=arm64 --foreign "${DEBIAN_RELEASE}" "${ROOTFS_WORK}" "${DEBIAN_MIRROR}" \
        || error "First stage debootstrap failed"

    log "Completed first stage debootstrap"
}

setup_qemu_chroot() {
    info "Setting up QEMU emulation..."

    maybe_sudo cp /usr/bin/qemu-aarch64-static "${ROOTFS_WORK}/usr/bin/"

    # DNS resolution in chroot
    if [[ ! -f /etc/resolv.conf ]]; then
        echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" | maybe_sudo tee /tmp/resolv.conf.chroot > /dev/null
        RESOLV_CONF_SRC="/tmp/resolv.conf.chroot"
    else
        RESOLV_CONF_SRC="/etc/resolv.conf"
    fi
    maybe_sudo touch "${ROOTFS_WORK}/etc/resolv.conf"
    maybe_sudo mount --bind "${RESOLV_CONF_SRC}" "${ROOTFS_WORK}/etc/resolv.conf"

    # Skip second stage if restored from cache
    if [[ ! -d "${ROOTFS_WORK}/debootstrap" ]]; then
        log "Skipping second stage (restored from cache)"
        return 0
    fi

    info "Running second stage debootstrap..."
    maybe_sudo chroot "${ROOTFS_WORK}" /debootstrap/debootstrap --second-stage \
        || error "Second stage debootstrap failed"

    log "Caching debootstrap result..."
    maybe_sudo tar -czf "${DEBOOTSTRAP_CACHE}" -C "${ROOTFS_WORK}" .
}

# ============================================================================
# Customization
# ============================================================================

customize_rootfs() {
    info "Customizing rootfs..."

    # Create customization script
    cat << 'CUSTOMIZE_EOF' | maybe_sudo tee "${ROOTFS_WORK}/tmp/customize.sh" > /dev/null
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PYTHONDONTWRITEBYTECODE=1
export DEB_PYTHON_INSTALL_LAYOUT=deb_system

# Configure repos
cat > /etc/apt/sources.list << 'SOURCES'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
SOURCES

apt-get update

# Disable py3compile during QEMU chroot (causes segfaults)
dpkg-divert --add --rename --divert /usr/bin/py3compile.real /usr/bin/py3compile
dpkg-divert --add --rename --divert /usr/bin/py3clean.real /usr/bin/py3clean
cat > /usr/bin/py3compile << 'STUB'
#!/bin/sh
exit 0
STUB
chmod +x /usr/bin/py3compile
ln -sf /usr/bin/py3compile /usr/bin/py3clean

# Profile-based apt options
PROFILE="${PROFILE:-minimal}"
if [ "$PROFILE" = "minimal" ]; then
    APT_OPTS="--no-install-recommends"
else
    APT_OPTS=""
fi

# Essential packages
apt-get install -y $APT_OPTS \
    systemd systemd-sysv systemd-timesyncd dbus \
    openssh-server sudo ca-certificates locales tzdata

# Network
if [ "$PROFILE" = "full" ]; then
    apt-get install -y $APT_OPTS network-manager
else
    apt-get install -y $APT_OPTS \
        systemd-resolved iproute2 iputils-ping dnsutils ndisc6
fi

# WiFi/Bluetooth
if [ "$PROFILE" = "full" ]; then
    apt-get install -y $APT_OPTS linux-firmware wireless-tools wpasupplicant iw rfkill
else
    apt-get install -y $APT_OPTS \
        firmware-realtek wireless-tools iwd iw rfkill bluez bluez-tools
fi

# Locales
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
cat > /etc/default/locale << 'LOCALE'
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
LOCALE

# Wayland desktop (Sway)
apt-get install -y $APT_OPTS sway seatd swayidle foot xwayland thunar dbus

if [ "$PROFILE" = "full" ]; then
    apt-get install -y $APT_OPTS waybar wofi wl-clipboard grim slurp
fi

# Graphics
apt-get install -y $APT_OPTS \
    libdrm2 libdrm-tests mesa-utils libgles2 libegl1 libgbm1 weston glmark2-es2-drm

if [ "$PROFILE" = "full" ]; then
    apt-get install -y $APT_OPTS \
        gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav
fi

# Browsers
apt-get install -y $APT_OPTS chromium firefox-esr

# Utilities
if [ "$PROFILE" = "full" ]; then
    apt-get install -y $APT_OPTS \
        vim git wget curl htop net-tools ethtool i2c-tools usbutils pciutils rsync parted
else
    apt-get install -y $APT_OPTS \
        nano wget htop ethtool rsync parted u-boot-tools i2c-tools
fi

# Users
useradd -m -s /bin/bash -G sudo,video,audio,dialout,render rock
echo "rock:rock" | chpasswd
echo "root:root" | chpasswd

# Hostname
echo "sz3568" > /etc/hostname
cat > /etc/hosts << 'HOSTS'
127.0.0.1	localhost
127.0.1.1	sz3568
::1		localhost ip6-localhost ip6-loopback
HOSTS

# Desktop user for Sway
useradd -m -s /bin/bash -G render,video,audio,input,sudo user
echo 'user:user' | chpasswd
echo 'user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/user
chmod 440 /etc/sudoers.d/user

# Auto-login on tty1
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'GETTY'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin user --noclear %I $TERM
GETTY

# Sway autostart
mkdir -p /home/user
cat > /home/user/.profile << 'PROFILE'
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = "1" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    exec sway
fi
PROFILE
chown -R user:user /home/user

# Services
if [ "$PROFILE" = "full" ]; then
    systemctl enable NetworkManager
else
    systemctl enable systemd-networkd systemd-resolved
    mkdir -p /etc/systemd/network
    cat > /etc/systemd/network/20-wired.network << 'NET'
[Match]
Name=eth* en*

[Network]
DHCP=yes
DNSSEC=no

[DHCPv4]
UseDNS=yes
NET
fi

systemctl enable ssh systemd-timesyncd seatd

# NTP
mkdir -p /etc/systemd/timesyncd.conf.d
cat > /etc/systemd/timesyncd.conf.d/rockchip.conf << 'NTP'
[Time]
NTP=0.pool.ntp.org 1.pool.ntp.org
FallbackNTP=time.cloudflare.com time.google.com
NTP

# First-boot Python bytecode compilation
cat > /etc/systemd/system/py3compile-first-boot.service << 'FIRSTBOOT'
[Unit]
Description=Compile Python bytecode on first boot
After=multi-user.target
ConditionPathExists=!/var/lib/py3compile-first-boot.done

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 -m compileall -q /usr
ExecStartPost=/bin/touch /var/lib/py3compile-first-boot.done
ExecStartPost=/bin/systemctl disable py3compile-first-boot.service

[Install]
WantedBy=multi-user.target
FIRSTBOOT
systemctl enable py3compile-first-boot.service

# Restore py3compile
dpkg-divert --remove /usr/bin/py3compile
dpkg-divert --remove /usr/bin/py3clean

echo "Customization complete"
CUSTOMIZE_EOF

    maybe_sudo chmod +x "${ROOTFS_WORK}/tmp/customize.sh"

    # Mount filesystems for chroot
    maybe_sudo mount -t proc /proc "${ROOTFS_WORK}/proc"
    maybe_sudo mount -t sysfs /sys "${ROOTFS_WORK}/sys"
    maybe_sudo mount --bind /dev "${ROOTFS_WORK}/dev"
    maybe_sudo mount --bind /dev/pts "${ROOTFS_WORK}/dev/pts"

    # Mount apt cache
    if [[ -n "$APT_CACHE_DIR" ]] && [[ -d "$APT_CACHE_DIR" ]]; then
        maybe_sudo mkdir -p "${ROOTFS_WORK}/var/cache/apt"
        maybe_sudo mount --bind "$APT_CACHE_DIR" "${ROOTFS_WORK}/var/cache/apt"
    fi
    if [[ -n "$APT_LISTS_DIR" ]] && [[ -d "$APT_LISTS_DIR" ]]; then
        maybe_sudo mkdir -p "${ROOTFS_WORK}/var/lib/apt/lists"
        maybe_sudo mount --bind "$APT_LISTS_DIR" "${ROOTFS_WORK}/var/lib/apt/lists"
    fi

    # Run customization
    maybe_sudo chroot "${ROOTFS_WORK}" /bin/bash -c "PROFILE=${PROFILE} /tmp/customize.sh" || {
        cleanup_chroot_mounts
        error "Customization failed"
    }

    cleanup_chroot_mounts
}

cleanup_chroot_mounts() {
    maybe_sudo umount -lf "${ROOTFS_WORK}/var/cache/apt" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/var/lib/apt/lists" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/proc" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/sys" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/dev/pts" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/dev" 2>/dev/null || true
}

# ============================================================================
# Post-customization
# ============================================================================

install_setup_emmc() {
    info "Installing eMMC provisioning script..."

    maybe_sudo tee "${ROOTFS_WORK}/usr/local/bin/setup-emmc" > /dev/null << 'EMMC_SCRIPT'
#!/bin/bash
set -e

echo "========================================"
echo "eMMC Provisioning Tool"
echo "========================================"

ROOT_DEV=$(findmnt -n -o SOURCE /)
case "$ROOT_DEV" in
    *mmcblk0p*) SD_DEV="/dev/mmcblk0"; EMMC_DEV="/dev/mmcblk1" ;;
    *mmcblk1p*) SD_DEV="/dev/mmcblk1"; EMMC_DEV="/dev/mmcblk0" ;;
    *) echo "Cannot determine devices"; exit 1 ;;
esac

echo "SD card: ${SD_DEV}"
echo "eMMC:    ${EMMC_DEV}"
echo ""
echo "WARNING: This will ERASE ${EMMC_DEV}"
read -p "Continue? (y/N) " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 1

BOOT_PART="${SD_DEV}p1"
BOOT_MNT=$(mktemp -d)
mount "$BOOT_PART" "$BOOT_MNT"
DTB_NAME=$(ls "$BOOT_MNT"/rk*.dtb 2>/dev/null | head -1 | xargs basename)

echo "Partitioning eMMC..."
parted -s "${EMMC_DEV}" mklabel gpt
parted -s "${EMMC_DEV}" mkpart primary ext4 2048s 526336s
parted -s "${EMMC_DEV}" mkpart primary ext4 526337s 100%
parted -s "${EMMC_DEV}" set 1 boot on
sleep 2; partprobe "${EMMC_DEV}" 2>/dev/null || true

echo "Formatting..."
mkfs.ext4 -F -L "BOOT" "${EMMC_DEV}p1" > /dev/null
mkfs.ext4 -F -L "rootfs" "${EMMC_DEV}p2" > /dev/null

EMMC_BOOT=$(mktemp -d); EMMC_ROOT=$(mktemp -d)
mount "${EMMC_DEV}p1" "$EMMC_BOOT"
mount "${EMMC_DEV}p2" "$EMMC_ROOT"

echo "Copying boot files..."
cp "$BOOT_MNT"/Image "$EMMC_BOOT/"
cp "$BOOT_MNT"/*.dtb "$EMMC_BOOT/" 2>/dev/null || true

mkdir -p "$EMMC_BOOT/extlinux"
cat > "$EMMC_BOOT/extlinux/extlinux.conf" << EOF
default debian
timeout 3
label debian
    kernel /Image
    fdt /${DTB_NAME}
    append console=ttyS2,1500000 root=${EMMC_DEV}p2 rootwait rw
EOF

echo "Copying rootfs (this takes several minutes)..."
rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/boot/*"} / "$EMMC_ROOT/" > /dev/null
mkdir -p "$EMMC_ROOT"/{dev,proc,sys,tmp,run,mnt,boot}

umount "$EMMC_BOOT" "$EMMC_ROOT" "$BOOT_MNT"
rmdir "$EMMC_BOOT" "$EMMC_ROOT" "$BOOT_MNT"
sync

echo ""
echo "✓ eMMC provisioning complete!"
echo "1. Shutdown: sudo poweroff"
echo "2. Remove SD card"
echo "3. Power on - board boots from eMMC"
EMMC_SCRIPT

    maybe_sudo chmod +x "${ROOTFS_WORK}/usr/local/bin/setup-emmc"
}

apply_rootfs_overlay() {
    local overlay_dir="${PROJECT_ROOT}/config/rootfs-overlay"
    local board_overlay_dir="${PROJECT_ROOT}/external/custom/board/rk3568/rootfs-overlay"

    if [[ -d "$overlay_dir" ]]; then
        info "Applying common rootfs overlay..."
        maybe_sudo cp -a --no-preserve=ownership "${overlay_dir}"/* "${ROOTFS_WORK}/" || true
    fi

    if [[ -d "$board_overlay_dir" ]]; then
        info "Applying board-specific rootfs overlay..."
        maybe_sudo cp -a --no-preserve=ownership "${board_overlay_dir}"/* "${ROOTFS_WORK}/" || true
        maybe_sudo chmod +x "${ROOTFS_WORK}/usr/local/bin/set-mac-from-serial" 2>/dev/null || true

        # Enable set-mac service
        maybe_sudo chroot "${ROOTFS_WORK}" systemctl enable set-mac.service 2>/dev/null || true
    fi
}

install_mesa_panfrost() {
    info "Installing Mesa with Panfrost..."

    maybe_sudo cp /usr/bin/qemu-aarch64-static "${ROOTFS_WORK}/usr/bin/" 2>/dev/null || true

    maybe_sudo chroot "${ROOTFS_WORK}" /bin/bash << 'MESA_EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    mesa-vulkan-drivers libegl-mesa0 libgl1-mesa-dri \
    libgles2-mesa libglx-mesa0 mesa-va-drivers mesa-utils
MESA_EOF

    log "Mesa with Panfrost installed"
}

# ============================================================================
# Image creation
# ============================================================================

create_rootfs_image() {
    info "Creating rootfs image..."

    local rootfs_size
    rootfs_size=$(maybe_sudo du -sb "${ROOTFS_WORK}" | awk '{print $1}')
    local image_size=$((rootfs_size * 12 / 10))  # 120% of actual

    info "Rootfs: $((rootfs_size / 1024 / 1024))MB, Image: $((image_size / 1024 / 1024))MB"

    dd if=/dev/zero of="${ROOTFS_IMAGE}" bs=1 count=0 seek=${image_size} 2>/dev/null
    maybe_sudo mkfs.ext4 -F -L "rootfs" "${ROOTFS_IMAGE}" >/dev/null

    local mount_point="${ROOTFS_DIR}/mnt"
    mkdir -p "${mount_point}"

    # Ensure loop devices exist
    for i in $(seq 0 7); do
        [[ -e /dev/loop$i ]] || maybe_sudo mknod /dev/loop$i b 7 $i 2>/dev/null || true
    done

    local loop_dev
    loop_dev=$(maybe_sudo losetup --find --show "${ROOTFS_IMAGE}") \
        || error "Failed to setup loop device"

    maybe_sudo mount "${loop_dev}" "${mount_point}"
    maybe_sudo cp -a "${ROOTFS_WORK}"/* "${mount_point}/"
    maybe_sudo umount "${mount_point}"
    maybe_sudo losetup -d "${loop_dev}" 2>/dev/null || true

    # Optimize
    maybe_sudo e2fsck -fy "${ROOTFS_IMAGE}" >/dev/null 2>&1 || true
    maybe_sudo resize2fs -M "${ROOTFS_IMAGE}" >/dev/null 2>&1

    log "Rootfs image created: ${ROOTFS_IMAGE}"
}

cleanup_rootfs() {
    info "Cleaning up..."

    maybe_sudo umount -lf "${ROOTFS_WORK}/var/cache/apt" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/var/lib/apt/lists" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/etc/resolv.conf" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/dev/pts" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/dev" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/sys" 2>/dev/null || true
    maybe_sudo umount -lf "${ROOTFS_WORK}/proc" 2>/dev/null || true

    if [[ "${KEEP_WORK:-0}" != "1" ]]; then
        maybe_sudo rm -rf "${ROOTFS_WORK}"
    fi

    [[ -f /tmp/resolv.conf.chroot ]] && rm -f /tmp/resolv.conf.chroot || true
}

# ============================================================================
# Commands
# ============================================================================

cmd_build() {
    header "Building Rootfs for ${BOARD_NAME}"
    info "Profile: ${PROFILE}"
    info "Debian: ${DEBIAN_RELEASE}"

    run_in_docker_if_needed "$BOARD_NAME" build

    trap cleanup_rootfs EXIT

    create_debian_rootfs
    setup_qemu_chroot
    customize_rootfs
    install_setup_emmc
    apply_rootfs_overlay
    install_mesa_panfrost
    create_rootfs_image
    cleanup_rootfs

    trap - EXIT

    log "Rootfs build complete!"
    kv "Image" "${ROOTFS_IMAGE}"
    kv "Profile" "${PROFILE}"
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
    kv "Work dir" "${ROOTFS_WORK}"
    kv "Image" "${ROOTFS_IMAGE}"
    kv "Cache" "${DEBOOTSTRAP_CACHE}"

    echo ""
    info "Artifact Status:"
    check_rootfs_artifact || true
}

# ============================================================================
# Main
# ============================================================================

main() {
    local board=""
    local command=""

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
