#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/module-cache"
operation="${1:-build}"
shift || true
arguments=(--disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --scratch-path .build --manifest-cache local -Xswiftc -module-cache-path -Xswiftc "$SWIFTPM_MODULECACHE_OVERRIDE")
exec swift "$operation" "${arguments[@]}" "$@"
