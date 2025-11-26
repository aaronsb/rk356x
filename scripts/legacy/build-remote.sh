#!/bin/bash
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================"
echo "Remote GitHub Actions Build"
echo "========================================${NC}"
echo ""

# Parse arguments
BOARD="${1:-rk3568_custom}"
BUILD_TYPE="${2:-full-build}"

echo -e "${BLUE}Configuration:${NC}"
echo "  Board: ${BOARD}"
echo "  Build type: ${BUILD_TYPE}"
echo ""

# Ask for confirmation
read -p "Trigger remote build on GitHub Actions? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Cancelled${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}==> Triggering GitHub Actions workflow...${NC}"

# Trigger the workflow
RUN_URL=$(gh workflow run "Build RK356X Image" \
  --field board="${BOARD}" \
  --field build_type="${BUILD_TYPE}" \
  --json url \
  -q .url 2>&1 | tail -1 || echo "")

if [ -z "$RUN_URL" ]; then
    echo -e "${YELLOW}Workflow triggered (URL not available yet)${NC}"
    echo ""
    echo "Wait a few seconds, then check:"
    echo "  gh run list --limit 5"
else
    echo -e "${GREEN}✓ Workflow triggered${NC}"
fi

echo ""
echo -e "${BLUE}Waiting for run to start...${NC}"
sleep 3

# Get the latest run
LATEST_RUN=$(gh run list --limit 1 --json databaseId,status,conclusion,url -q '.[0]')
RUN_ID=$(echo "$LATEST_RUN" | jq -r '.databaseId')
RUN_STATUS=$(echo "$LATEST_RUN" | jq -r '.status')
RUN_URL=$(echo "$LATEST_RUN" | jq -r '.url')

echo ""
echo -e "${GREEN}Run started:${NC}"
echo "  ID: ${RUN_ID}"
echo "  Status: ${RUN_STATUS}"
echo "  URL: ${RUN_URL}"
echo ""

# Offer to watch the build
echo -e "${YELLOW}Build will take ~60 minutes${NC}"
echo ""
read -p "Watch build progress in real-time? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}Watching build (Ctrl+C to stop watching)...${NC}"
    echo ""
    gh run watch "$RUN_ID" --exit-status

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Build complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "View artifacts:"
    echo "  gh run view ${RUN_ID}"
    echo ""
    echo "Download artifacts:"
    echo "  gh run download ${RUN_ID}"
else
    echo ""
    echo -e "${BLUE}Build running in background${NC}"
    echo ""
    echo "Monitor progress:"
    echo "  gh run watch ${RUN_ID}"
    echo ""
    echo "View status:"
    echo "  gh run view ${RUN_ID}"
    echo ""
    echo "Check all runs:"
    echo "  gh run list"
fi

echo ""
