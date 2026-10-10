#!/bin/zsh
set -euo pipefail
mkdir -p build/AppIcon.iconset
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" Resources/ForkBrand/AppIcon.png \
        --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -s format png -z "$retina" "$retina" Resources/ForkBrand/AppIcon.png \
        --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
cp Resources/ForkBrand/MenuBarIcon.png Resources/ForkBrand/MenuBarIcon@2x.png \
   Resources/ForkBrand/BrandMark.png build/
rm -f build/Assets.car
