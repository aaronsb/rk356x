# Debian Build Environment for RK3568
# Provides all dependencies for kernel and rootfs builds
#
# Build with BuildKit for apt caching:
#   DOCKER_BUILDKIT=1 docker build -t rk3568-debian-builder .

FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies with apt cache mounts
# Cache mounts persist between builds but don't bloat the image
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y \
    # Kernel build dependencies
    build-essential \
    git \
    make \
    gcc \
    g++ \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    bc \
    kmod \
    debhelper \
    cpio \
    gcc-aarch64-linux-gnu \
    device-tree-compiler \
    # Rootfs build dependencies
    qemu-user-static \
    debootstrap \
    wget \
    curl \
    # Utilities
    vim \
    less \
    rsync \
    file \
    ca-certificates

# Set working directory
WORKDIR /work

# Default command
CMD ["/bin/bash"]
