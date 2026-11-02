#!/usr/bin/env bash
# Renders fateglass-icon-mac.svg into FateGlass.icns, the app icon of FateGlass.app.
# Needs rsvg-convert (brew install librsvg). Rerun after changing the SVG and commit the .icns.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG="$HERE/fateglass-icon-mac.svg"
ICONSET="$(mktemp -d)/FateGlass.iconset"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
	rsvg-convert -w "$size" -h "$size" "$SVG" -o "$ICONSET/icon_${size}x${size}.png"
	rsvg-convert -w $((size * 2)) -h $((size * 2)) "$SVG" -o "$ICONSET/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$ICONSET" -o "$HERE/FateGlass.icns"
rm -rf "$(dirname "$ICONSET")"
echo "Created $HERE/FateGlass.icns"
