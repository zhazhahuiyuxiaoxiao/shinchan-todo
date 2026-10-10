#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
iconset_dir="$project_dir/.build/AppIcon.iconset"
mkdir -p "$iconset_dir"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$project_dir/Packaging/AppIcon.png" \
    --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  /usr/bin/sips -z "$retina_size" "$retina_size" "$project_dir/Packaging/AppIcon.png" \
    --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil --convert icns "$iconset_dir" --output "$project_dir/.build/AppIcon.icns"
