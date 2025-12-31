#!/bin/bash
# Artifact detection functions
# Source this file, don't execute it directly

# Guard against multiple sourcing
[[ -n "${_LIB_ARTIFACTS_LOADED:-}" ]] && return 0
_LIB_ARTIFACTS_LOADED=1

# These functions expect PROJECT_ROOT to be set (via common.sh or board.sh)
# and optionally DTB_NAME for kernel artifact checks

# Default paths (can be overridden)
KERNEL_VERSION="${KERNEL_VERSION:-6.12}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/output}"
KERNEL_DEBS_DIR="${KERNEL_DEBS_DIR:-${OUTPUT_DIR}/kernel-debs}"
ROOTFS_IMAGE="${ROOTFS_IMAGE:-${PROJECT_ROOT}/rootfs/debian-rootfs.img}"

# Check for kernel build artifacts
# Returns: FOUND, FOUND_RAW, or NOT_FOUND (first line)
# Additional lines contain artifact details
check_kernel_artifacts() {
    local image_deb headers_deb kernel_dir raw_image raw_dtb

    image_deb=$(ls -1t "${KERNEL_DEBS_DIR}"/linux-image-*.deb 2>/dev/null | head -1)
    headers_deb=$(ls -1t "${KERNEL_DEBS_DIR}"/linux-headers-*.deb 2>/dev/null | head -1)
    kernel_dir="${PROJECT_ROOT}/kernel-${KERNEL_VERSION}"
    raw_image="${kernel_dir}/arch/arm64/boot/Image"
    raw_dtb="${kernel_dir}/arch/arm64/boot/dts/rockchip/${DTB_NAME:-unknown}.dtb"

    # Check for .deb packages (preferred - ready to install)
    if [[ -n "$image_deb" ]] && [[ -f "$image_deb" ]]; then
        local size date version
        size=$(du -h "$image_deb" | cut -f1)
        date=$(stat -c %y "$image_deb" | cut -d' ' -f1,2 | cut -d'.' -f1)
        version=$(basename "$image_deb" | sed 's/linux-image-\(.*\)_.*\.deb/\1/')

        echo "FOUND"
        echo "  Image:   $(basename "$image_deb")"
        echo "  Size:    $size"
        echo "  Date:    $date"
        echo "  Version: $version"

        if [[ -n "$headers_deb" ]] && [[ -f "$headers_deb" ]]; then
            local hdr_size
            hdr_size=$(du -h "$headers_deb" | cut -f1)
            echo "  Headers: $(basename "$headers_deb") ($hdr_size)"
        fi
        return 0

    # Check for raw kernel build (compiled but not packaged)
    elif [[ -f "$raw_image" ]] && [[ -f "$raw_dtb" ]]; then
        local size date
        size=$(du -h "$raw_image" | cut -f1)
        date=$(stat -c %y "$raw_image" | cut -d' ' -f1,2 | cut -d'.' -f1)

        echo "FOUND_RAW"
        echo "  Image:   kernel-${KERNEL_VERSION}/arch/arm64/boot/Image"
        echo "  Size:    $size"
        echo "  Date:    $date"
        echo "  DTB:     ${DTB_NAME}.dtb"
        echo "  Status:  Compiled but not packaged (re-run kernel build to create .debs)"
        return 0
    else
        echo "NOT_FOUND"
        return 1
    fi
}

# Check for rootfs artifact
check_rootfs_artifact() {
    if [[ -f "${ROOTFS_IMAGE}" ]]; then
        local size date fs_info
        size=$(du -h "${ROOTFS_IMAGE}" | cut -f1)
        date=$(stat -c %y "${ROOTFS_IMAGE}" | cut -d' ' -f1,2 | cut -d'.' -f1)
        fs_info=$(file "${ROOTFS_IMAGE}" 2>/dev/null || echo "ext4 filesystem")

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

# Check for final image artifacts
check_image_artifacts() {
    local final_image
    final_image=$(ls -1t "${OUTPUT_DIR}"/rk3568-debian-*.img 2>/dev/null | grep -v '\.xz$' | head -1)

    if [[ -n "$final_image" ]] && [[ -f "$final_image" ]]; then
        local size date
        size=$(du -h "$final_image" | cut -f1)
        date=$(stat -c %y "$final_image" | cut -d' ' -f1,2 | cut -d'.' -f1)

        echo "FOUND"
        echo "  Image: $(basename "$final_image")"
        echo "  Size:  $size"
        echo "  Date:  $date"

        # Check for compressed version
        if [[ -f "${final_image}.xz" ]]; then
            local xz_size
            xz_size=$(du -h "${final_image}.xz" | cut -f1)
            echo "  Compressed: $(basename "${final_image}.xz") ($xz_size)"
        fi

        # Check for checksum
        if [[ -f "${final_image}.sha256" ]]; then
            echo "  Checksum: Available"
        fi
        return 0
    else
        echo "NOT_FOUND"
        return 1
    fi
}

# Check for U-Boot artifacts
check_uboot_artifacts() {
    local uboot_bin="${OUTPUT_DIR}/uboot/u-boot-rockchip.bin"

    if [[ -f "$uboot_bin" ]]; then
        local size date
        size=$(du -h "$uboot_bin" | cut -f1)
        date=$(stat -c %y "$uboot_bin" | cut -d' ' -f1,2 | cut -d'.' -f1)

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
