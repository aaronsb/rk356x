# Debian Build Environment for RK3568
# Provides all dependencies for kernel and rootfs builds

FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
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
    ca-certificates \
    # Cleanup
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /work

# Default command
CMD ["/bin/bash"]
