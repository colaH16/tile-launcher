#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
RESULT="${1:?Usage: run.sh OUTPUT_JSON}"
BENCH_WORK="$(mktemp -d /tmp/tile-drag-geometry.XXXXXX)"
trap 'rm -rf "$BENCH_WORK"' EXIT
# Explicitly import the SDK geometry overlay for this standalone compilation.
# The production function bodies are copied without changes.
printf 'import CoreGraphics\n' > "$BENCH_WORK/OverlayDragGeometry.swift"
cat "$ROOT/Sources/DeckCore/OverlayDragGeometry.swift" >> "$BENCH_WORK/OverlayDragGeometry.swift"
xcrun swiftc -swift-version 5 -O -whole-module-optimization -target arm64-apple-macos26.0 \
  "$BENCH_WORK/OverlayDragGeometry.swift" "$ROOT/tools/drag-samples/benchmark/main.swift" \
  -o "$BENCH_WORK/benchmark" -module-cache-path "$ROOT/.build/ModuleCache"
"$BENCH_WORK/benchmark" "$RESULT"
