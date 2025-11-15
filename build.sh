#!/bin/bash
set -e

# RK356X Buildroot Build Script
# One-command build for embedded Linux images

BUILDROOT_VERSION="2024.08.1"
BUILDROOT_URL="https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "RK356X Buildroot Builder"
echo "========================================"
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
            > /dev/null 2>&1
        echo "✓ Dependencies installed"
        echo ""

        echo "==> Loading configuration..."
        BR2_EXTERNAL=../external/jvl make rk3568_jvl_defconfig
        echo "✓ Configuration loaded"
        echo ""

        echo "==> Building (this takes 15-60 minutes)..."
        FORCE_UNSAFE_CONFIGURE=1 BR2_EXTERNAL=../external/jvl make -j$(nproc)
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
    BR2_EXTERNAL=../external/jvl make rk3568_jvl_defconfig
    echo "✓ Configuration loaded"
    echo ""

    echo "==> Building (this takes 15-60 minutes)..."
    BR2_EXTERNAL=../external/jvl make -j$(nproc)
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
