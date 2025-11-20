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
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  build      Incremental build (fast, uses cached artifacts)"
    echo "  clean      Full rebuild - removes output and rebuilds everything"
    echo ""
    echo "Examples:"
    echo "  $0 build   # Quick rebuild after code changes"
    echo "  $0 clean   # Fresh build (required after config changes)"
    echo ""
    exit 0
}

if [ -z "$1" ]; then
    show_help
elif [ "$1" = "build" ]; then
    BUILD_MODE="incremental"
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

if [ "$BUILD_MODE" = "clean" ]; then
    echo "Mode: CLEAN REBUILD (removes output directory)"
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
            BR2_EXTERNAL=../external/custom make rk3568_custom_defconfig
            echo \"✓ Configuration loaded\"
            echo \"\"

            echo \"==> Building (this takes 15-60 minutes)...\"
            BR2_EXTERNAL=../external/custom make -j\$(nproc)
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
    BR2_EXTERNAL=../external/custom make rk3568_custom_defconfig
    echo "✓ Configuration loaded"
    echo ""

    echo "==> Building (this takes 15-60 minutes)..."
    BR2_EXTERNAL=../external/custom make -j$(nproc)
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
