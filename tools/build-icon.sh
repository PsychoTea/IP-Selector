#!/bin/bash
# Package the generated artwork at the standard macOS icon sizes.
set -euo pipefail
cd "$(dirname "$0")/.."
icon_source="Artwork/AppIcon-v1.png"
icon_set="build/AppIcon.iconset"
mkdir -p "$icon_set"
for icon_points in 16 32 128 256 512; do
    sips -z "$icon_points" "$icon_points" "$icon_source" --out "$icon_set/icon_${icon_points}x${icon_points}.png" >/dev/null
    icon_pixels=$((icon_points * 2))
    sips -z "$icon_pixels" "$icon_pixels" "$icon_source" --out "$icon_set/icon_${icon_points}x${icon_points}@2x.png" >/dev/null
done
iconutil -c icns "$icon_set" -o App/AppIcon.icns
