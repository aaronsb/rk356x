#!/bin/bash
# WebGL Aquarium Demo using Cog (WPE WebKit)
# Runs smoothly on RK3568 with Panfrost GPU

URL="${1:-https://webglsamples.org/aquarium/aquarium.html}"

echo "Launching WebGL demo: $URL"
echo "Press Ctrl+C to exit"
echo ""

exec cog "$URL"
