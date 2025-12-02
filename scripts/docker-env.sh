#!/bin/bash
# Docker environment helper for Debian builds
# This script is sourced by build scripts to handle Docker execution

DOCKER_IMAGE="rk3568-debian-builder"
DOCKER_TAG="latest"

# Check if we're already inside the container
in_container() {
    [ -f /.dockerenv ] || [ -n "$CONTAINER" ]
}

# Build the Docker image if it doesn't exist
ensure_docker_image() {
    if ! docker image inspect "${DOCKER_IMAGE}:${DOCKER_TAG}" &>/dev/null; then
        echo "==> Building Docker image (one-time setup, ~2 minutes)..."
        docker build -t "${DOCKER_IMAGE}:${DOCKER_TAG}" -f "${PROJECT_ROOT}/Dockerfile" "${PROJECT_ROOT}"
    fi
}

# Re-execute current script inside Docker container
docker_exec() {
    local script_path="$1"
    shift
    local args="$@"

    ensure_docker_image

    echo "==> Running in Docker container..."
    echo "    Script: $(basename $script_path)"
    echo "    Args: $args"
    echo ""

    # Run the script inside container with same arguments
    # Mount project root as /work
    # Preserve user permissions by mapping UIDs
    docker run --rm -it \
        -v "${PROJECT_ROOT}:/work" \
        -e CONTAINER=1 \
        -e HOME=/work \
        -w /work \
        -u "$(id -u):$(id -g)" \
        "${DOCKER_IMAGE}:${DOCKER_TAG}" \
        "/work/${script_path#${PROJECT_ROOT}/}" $args
}

# Export functions for use by scripts
export -f in_container
export -f ensure_docker_image
export -f docker_exec
