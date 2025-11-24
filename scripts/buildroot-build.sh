#!/bin/bash
set -e

# RK356X Buildroot Build Script
# One-command build for embedded Linux images

BUILDROOT_VERSION="2024.08.1"
BUILDROOT_URL="https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Parse arguments
show_help() {
    echo "Usage: $0 [board] <command>"
    echo ""
    echo "Boards:"
    echo "  rk3568_custom    DC-A568-V06 board (default)"
    echo "  rk3568_sz3568    SZ3568-V1.2 board"
    echo ""
    echo "Commands:"
    echo "  build          Incremental build (fast, uses cached artifacts)"
    echo "  linux-rebuild  Rebuild kernel and device tree only"
    echo "  clean          Full rebuild - removes output and rebuilds everything"
    echo ""
    echo "Examples:"
    echo "  $0 build                      # Build DC-A568 (default)"
    echo "  $0 rk3568_sz3568 build        # Build SZ3568"
    echo "  $0 rk3568_sz3568 linux-rebuild  # Rebuild SZ3568 kernel"
    echo "  $0 rk3568_custom clean        # Clean build DC-A568"
    echo ""
    exit 0
}

# Default board
BOARD_DEFCONFIG="rk3568_custom"

# Check if first argument is a board name
if [[ "$1" =~ ^rk3568_ ]]; then
    BOARD_DEFCONFIG="$1"
    shift
fi

if [ -z "$1" ]; then
    show_help
elif [ "$1" = "build" ]; then
    BUILD_MODE="incremental"
elif [ "$1" = "linux-rebuild" ]; then
    BUILD_MODE="linux-rebuild"
elif [ "$1" = "clean" ] || [ "$1" = "rebuild" ]; then
    BUILD_MODE="clean"
elif [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
else
    echo "Unknown command: $1"
    echo ""
    show_help
fi

echo "========================================"
echo "RK356X Buildroot Builder"
echo "========================================"
echo ""
echo "Board: ${BOARD_DEFCONFIG}"

if [ "$BUILD_MODE" = "clean" ]; then
    echo "Mode: CLEAN REBUILD (removes output directory)"
elif [ "$BUILD_MODE" = "linux-rebuild" ]; then
    echo "Mode: Linux kernel rebuild"
else
    echo "Mode: Incremental build"
fi
echo ""

# Check if Docker is available
if command -v docker &> /dev/null; then
    USE_DOCKER=true
    echo "✓ Docker detected - using containerized build"
else
    USE_DOCKER=false
    echo "✗ Docker not found - using native build"
    echo "  (Install Docker for consistent, reproducible builds)"
fi

echo ""

# Initialize submodules
echo "==> Initializing submodules (vendor blobs)..."
if ! git submodule update --init --recursive; then
    echo "ERROR: Failed to initialize submodules"
    echo "Make sure you cloned with: git clone --recursive"
    exit 1
fi

# Download Buildroot if needed
if [ ! -d "buildroot" ]; then
    echo "==> Downloading Buildroot ${BUILDROOT_VERSION}..."
    if [ ! -f "buildroot-${BUILDROOT_VERSION}.tar.gz" ]; then
        wget -q --show-progress "${BUILDROOT_URL}"
    fi

    echo "==> Extracting Buildroot..."
    tar xzf "buildroot-${BUILDROOT_VERSION}.tar.gz"
    mv "buildroot-${BUILDROOT_VERSION}" buildroot
    echo "✓ Buildroot ready"
else
    echo "✓ Buildroot already present"
fi

# Clean if requested
if [ "$BUILD_MODE" = "clean" ]; then
    echo ""
    echo "==> Cleaning previous build..."
    rm -rf "${PROJECT_ROOT}/buildroot/output"
    echo "✓ Output directory removed"
fi

# Auto-detect DTS changes in incremental mode
if [ "$BUILD_MODE" = "incremental" ] && [ -d "${PROJECT_ROOT}/buildroot/output" ]; then
    echo ""
    echo "==> Checking for device tree changes..."

    # Find all DTS files in external directory
    DTS_FILES=$(find "${PROJECT_ROOT}/external" -name "*.dts" -o -name "*.dtsi" 2>/dev/null || true)

    # Check if any DTS file is newer than the last kernel build
    KERNEL_MARKER="${PROJECT_ROOT}/buildroot/output/build/linux-develop-6.1/.stamp_built"
    NEED_LINUX_REBUILD=false

    if [ -f "$KERNEL_MARKER" ]; then
        while IFS= read -r dts_file; do
            if [ -n "$dts_file" ] && [ "$dts_file" -nt "$KERNEL_MARKER" ]; then
                echo "  • DTS change detected: $(basename $dts_file)"
                NEED_LINUX_REBUILD=true
            fi
        done <<< "$DTS_FILES"

        if [ "$NEED_LINUX_REBUILD" = true ]; then
            echo "✓ DTS changes detected - will rebuild kernel"
            BUILD_MODE="linux-rebuild"
        else
            echo "✓ No DTS changes detected"
        fi
    fi
fi

echo ""

# Build
if [ "$USE_DOCKER" = true ]; then
    echo "==> Building in Docker container..."
    echo "    Container: ubuntu:22.04"
    echo "    Cores: $(nproc)"
    echo "    Working dir: ${PROJECT_ROOT}"
    echo ""

    docker run --rm \
        -v "${PROJECT_ROOT}:/work" \
        -w /work/buildroot \
        -e HOST_UID=$(id -u) \
        -e HOST_GID=$(id -g) \
        ubuntu:22.04 bash -c '
        set -e
        echo "==> Installing build dependencies..."
        apt-get update > /dev/null 2>&1
        apt-get install -y \
            build-essential \
            libssl-dev \
            libncurses-dev \
            bc \
            rsync \
            file \
            wget \
            cpio \
            unzip \
            python3 \
            python3-pyelftools \
            git \
            sudo \
            > /dev/null 2>&1
        echo "✓ Dependencies installed"
        echo ""

        # Create build user with host UID/GID so files are owned correctly
        echo "==> Setting up build user..."
        groupadd -g $HOST_GID builduser 2>/dev/null || true
        useradd -u $HOST_UID -g $HOST_GID -m -s /bin/bash builduser 2>/dev/null || true
        chown -R builduser:builduser /work 2>/dev/null || true
        echo "✓ Build user ready (UID=$HOST_UID, GID=$HOST_GID)"
        echo ""

        # Run build as the build user
        su builduser -c "
            cd /work/buildroot
            echo \"==> Loading configuration...\"
            BR2_EXTERNAL=../external/custom make '"${BOARD_DEFCONFIG}"'_defconfig
            echo \"✓ Configuration loaded\"
            echo \"\"

            if [ \"'"$BUILD_MODE"'\" = \"linux-rebuild\" ]; then
                echo \"==> Rebuilding kernel and device tree...\"
                BR2_EXTERNAL=../external/custom make linux-rebuild -j\$(nproc)
            else
                echo \"==> Building (this takes 15-60 minutes)...\"
                BR2_EXTERNAL=../external/custom make -j\$(nproc)
            fi
        "
    '
else
    echo "==> Building natively..."
    echo "    Cores: $(nproc)"
    echo ""

    # Check for required tools
    echo "==> Checking dependencies..."
    MISSING_DEPS=()
    for cmd in gcc make wget tar git python3; do
        if ! command -v "$cmd" &> /dev/null; then
            MISSING_DEPS+=("$cmd")
        fi
    done

    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
        echo "ERROR: Missing dependencies: ${MISSING_DEPS[*]}"
        echo ""
        echo "Install with:"
        echo "  sudo apt-get install -y build-essential libssl-dev libncurses-dev \\"
        echo "    bc rsync file wget cpio unzip python3 python3-pyelftools git"
        exit 1
    fi
    echo "✓ All dependencies present"
    echo ""

    echo "==> Loading configuration..."
    cd buildroot
    BR2_EXTERNAL=../external/custom make ${BOARD_DEFCONFIG}_defconfig
    echo "✓ Configuration loaded"
    echo ""

    if [ "$BUILD_MODE" = "linux-rebuild" ]; then
        echo "==> Rebuilding kernel and device tree..."
        BR2_EXTERNAL=../external/custom make linux-rebuild -j$(nproc)
    else
        echo "==> Building (this takes 15-60 minutes)..."
        BR2_EXTERNAL=../external/custom make -j$(nproc)
    fi
    cd ..
fi

echo ""
echo "========================================"
echo "✓ Build Complete!"
echo "========================================"
echo ""
echo "Output artifacts:"
ls -lh buildroot/output/images/
echo ""
echo "Next steps:"
echo "  - Flash images to SD card or eMMC"
echo "  - See docs/dev/BUILD.md for flashing instructions"
echo ""
