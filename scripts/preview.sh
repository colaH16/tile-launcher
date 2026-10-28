#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
BINARY_DIR="$(swift build --show-bin-path --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security)"
OUTPUT_DIR="${1:-/tmp/tile-launcher-previews}"
"$BINARY_DIR/TileLauncher" --render-previews "$OUTPUT_DIR"
printf '%s\n' "$OUTPUT_DIR"
