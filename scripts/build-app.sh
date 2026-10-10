#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
bash scripts/swift.sh build -c release --product ShinchanTodo
binary_dir="$(bash scripts/swift.sh build -c release --show-bin-path)"
app_dir="$project_dir/dist/小新待办.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp Packaging/Info.plist "$app_dir/Contents/Info.plist"
cp "$binary_dir/ShinchanTodo" "$app_dir/Contents/MacOS/ShinchanTodo"
# SwiftPM 资源 bundle 没有 .app 所需的嵌套包元数据，展开到标准 Resources 目录。
if [[ -d "$app_dir/Contents/MacOS/ShinchanTodo_ShinchanTodo.bundle" ]]; then
  rm -rf "$app_dir/Contents/MacOS/ShinchanTodo_ShinchanTodo.bundle"
fi
cp "$binary_dir/ShinchanTodo_ShinchanTodo.bundle/Shinchan.png" "$app_dir/Contents/Resources/Shinchan.png"
cp "$binary_dir/ShinchanTodo_ShinchanTodo.bundle/AssetSources.md" "$app_dir/Contents/Resources/AssetSources.md"
bash scripts/build-icon.sh
cp .build/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.zhazhahui.shinchan-todo "$app_dir"
codesign --verify --deep --strict "$app_dir"
plutil -lint "$app_dir/Contents/Info.plist"
printf '%s\n' "$app_dir"
