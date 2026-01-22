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
BUILD_MANIFEST="${BUILD_MANIFEST:-${OUTPUT_DIR}/.build-manifest}"

# ============================================================================
# Checksum/Manifest Functions
# ============================================================================

# Generate checksum for a file, return just the hash
file_checksum() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    sha256sum "$file" | cut -d' ' -f1
}

# Write component checksum to output directory
# Usage: write_component_checksum <component> <file>
write_component_checksum() {
    local component="$1"
    local file="$2"
    local checksum_file="${OUTPUT_DIR}/.${component}-checksum"

    [[ -f "$file" ]] || return 1
    mkdir -p "${OUTPUT_DIR}"

    local checksum
    checksum=$(file_checksum "$file")
    echo "${checksum}  $(basename "$file")" > "$checksum_file"
    echo "$checksum"
}

# Read component checksum from output directory
# Returns checksum or empty string if not found
read_component_checksum() {
    local component="$1"
    local checksum_file="${OUTPUT_DIR}/.${component}-checksum"

    [[ -f "$checksum_file" ]] || return 1
    cut -d' ' -f1 "$checksum_file"
}

# Write build manifest after image assembly
# Records checksums of all components that went into the image
write_build_manifest() {
    local image_file="$1"
    local kernel_checksum rootfs_checksum image_checksum

    kernel_checksum=$(read_component_checksum "kernel" 2>/dev/null || echo "")
    rootfs_checksum=$(read_component_checksum "rootfs" 2>/dev/null || echo "")
    image_checksum=$(file_checksum "$image_file" 2>/dev/null || echo "")

    cat > "${BUILD_MANIFEST}" << EOF
# Build manifest - records component checksums used in assembled image
# Generated: $(date -Iseconds)
BUILD_ID=$(uuidgen 2>/dev/null || date +%s)
BOARD=${BOARD_NAME:-unknown}
IMAGE=$(basename "$image_file")
IMAGE_SHA256=${image_checksum}
KERNEL_SHA256=${kernel_checksum}
ROOTFS_SHA256=${rootfs_checksum}
EOF

    # Also create a .manifest file alongside the image
    cp "${BUILD_MANIFEST}" "${image_file}.manifest"
}

# Read a value from the build manifest
read_manifest_value() {
    local key="$1"
    [[ -f "${BUILD_MANIFEST}" ]] || return 1
    grep "^${key}=" "${BUILD_MANIFEST}" | cut -d'=' -f2
}

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

# Check if final image is stale (dependencies have changed)
# Returns 0 (true) if image needs rebuild, 1 (false) if up-to-date
# Uses checksums from build manifest for reliable comparison
check_image_needs_rebuild() {
    local final_image

    final_image=$(ls -1t "${OUTPUT_DIR}"/rk3568-debian-*.img 2>/dev/null | grep -v '\.xz$' | head -1)

    # No image exists - needs build
    [[ -z "$final_image" ]] || [[ ! -f "$final_image" ]] && return 0

    # No manifest - needs rebuild (legacy image or manifest deleted)
    [[ -f "${BUILD_MANIFEST}" ]] || return 0

    # Compare current component checksums to what's in the manifest
    local manifest_kernel manifest_rootfs current_kernel current_rootfs

    manifest_kernel=$(read_manifest_value "KERNEL_SHA256")
    manifest_rootfs=$(read_manifest_value "ROOTFS_SHA256")
    current_kernel=$(read_component_checksum "kernel" 2>/dev/null || echo "")
    current_rootfs=$(read_component_checksum "rootfs" 2>/dev/null || echo "")

    # If kernel checksum changed, rebuild
    if [[ -n "$current_kernel" ]] && [[ "$current_kernel" != "$manifest_kernel" ]]; then
        return 0
    fi

    # If rootfs checksum changed, rebuild
    if [[ -n "$current_rootfs" ]] && [[ "$current_rootfs" != "$manifest_rootfs" ]]; then
        return 0
    fi

    # Checksums match - image is up-to-date
    return 1
}
