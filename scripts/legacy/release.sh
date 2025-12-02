#!/bin/bash
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get current version
CURRENT_VERSION=$(cat VERSION)
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
    exit 1
    ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
echo -e "${YELLOW}New version: ${NEW_VERSION}${NC}"

# Ask for confirmation
read -p "Create release v${NEW_VERSION}? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Release cancelled${NC}"
    exit 1
fi

# Update VERSION file
echo "$NEW_VERSION" > VERSION
echo -e "${GREEN}✓ Updated VERSION file${NC}"

# Commit version bump
git add VERSION
git commit -m "Bump version to ${NEW_VERSION}"
echo -e "${GREEN}✓ Committed version bump${NC}"

# Create and push tag
git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}"
echo -e "${GREEN}✓ Created tag v${NEW_VERSION}${NC}"

# Push changes and tags
git push && git push --tags
echo -e "${GREEN}✓ Pushed changes and tags${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Release v${NEW_VERSION} created!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "GitHub Actions will now build and create the release."
echo "Visit: https://github.com/aaronsb/rk356x/actions"
