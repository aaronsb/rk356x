#!/bin/bash
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${GREEN}========================================"
echo "Local Build + GitHub Release"
echo "========================================${NC}"
echo ""

# Get current version
CURRENT_VERSION=$(cat "$PROJECT_ROOT/VERSION")
echo -e "${GREEN}Current version: ${CURRENT_VERSION}${NC}"

# Parse version
IFS='.' read -r -a VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR="${VERSION_PARTS[0]}"
MINOR="${VERSION_PARTS[1]}"
PATCH="${VERSION_PARTS[2]}"

# Determine version bump type
BUMP_TYPE="${1:-patch}"

case "$BUMP_TYPE" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
  *)
    echo -e "${RED}Error: Invalid bump type. Use 'major', 'minor', or 'patch'${NC}"
    echo "Usage: $0 [major|minor|patch]"
    exit 1
    ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
echo -e "${YELLOW}New version: ${NEW_VERSION}${NC}"
echo ""

# Ask for confirmation
read -p "Build locally and create GitHub release v${NEW_VERSION}? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Cancelled${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}==> Step 1/4: Building image locally...${NC}"
cd "$PROJECT_ROOT"
./build.sh

# Check if build succeeded
if [ ! -f "buildroot/output/images/Image" ]; then
    echo -e "${RED}Error: Build failed - Image not found${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}==> Step 2/4: Updating version...${NC}"
echo "$NEW_VERSION" > VERSION
git add VERSION
git commit -m "Bump version to ${NEW_VERSION}"
git push
echo -e "${GREEN}✓ Version updated${NC}"

echo ""
echo -e "${GREEN}==> Step 3/4: Creating git tag...${NC}"
git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}"
git push --tags
echo -e "${GREEN}✓ Tag created${NC}"

echo ""
echo -e "${GREEN}==> Step 4/4: Creating GitHub release with local artifacts...${NC}"

gh release create "v${NEW_VERSION}" \
  --title "v${NEW_VERSION} - RK3568 Buildroot Release" \
  --notes "$(cat <<EOF
## RK356X Buildroot Template - v${NEW_VERSION}

### 📦 What's Included

- **Buildroot** 2024.08.1
- **Linux Kernel** 6.6.62 LTS
- **U-Boot** 2024.07 with Rockchip vendor blobs
- **Init System** systemd
- **Root Filesystem** 512MB ext4

### 🎯 Target Board

- **SoC:** RK3568 (Cortex-A55 quad-core)
- **Config:** Generic EVB
- **Device Tree:** rk3568-evb1-v10.dtb

### 📥 Artifacts

| File | Description |
|------|-------------|
| \`Image\` | Linux kernel binary (~40MB) |
| \`rk3568-evb1-v10.dtb\` | Device tree blob |
| \`rootfs.ext4\` | Root filesystem (512MB) |
| \`rootfs.tar.gz\` | Compressed rootfs (~31MB) |
| \`u-boot.bin\` | U-Boot bootloader |
| \`u-boot-spl.bin\` | U-Boot SPL |

### 🔨 Build Info

- **Build Date:** $(date +%Y-%m-%d)
- **Build Environment:** Local Docker build

See [README.md](https://github.com/aaronsb/rk356x) for usage instructions.

### 🔐 Default Credentials

- **Username:** root
- **Password:** root

⚠️ **Change immediately after first boot!**
EOF
)" \
  buildroot/output/images/Image \
  buildroot/output/images/rk3568-evb1-v10.dtb \
  buildroot/output/images/rootfs.ext4 \
  buildroot/output/images/rootfs.tar.gz \
  buildroot/output/images/u-boot.bin \
  buildroot/output/images/u-boot-spl.bin

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Release v${NEW_VERSION} created!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Release URL: https://github.com/aaronsb/rk356x/releases/tag/v${NEW_VERSION}"
echo ""
