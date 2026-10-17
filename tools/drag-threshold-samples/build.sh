#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:?Usage: build.sh OUTPUT_DIRECTORY}"
APP="$OUT/Tile Launcher Drag Threshold.app"
test ! -e "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc "$ROOT/tools/drag-threshold-samples/DragSamples.swift" -o "$APP/Contents/MacOS/DragSamples" \
  -swift-version 5 -target arm64-apple-macos26.0 -O -module-cache-path "$ROOT/.build/ModuleCache"
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps(dict(
 CFBundleIdentifier='dev.cola16.TileLauncher.DragThreshold',CFBundleName='Tile Launcher Drag Samples',
 CFBundleDisplayName='Tile Launcher Drag Samples',CFBundleExecutable='DragSamples',
 CFBundlePackageType='APPL',CFBundleShortVersionString='0.4.1',CFBundleVersion='6',
 LSMinimumSystemVersion='26.0',NSPrincipalClass='NSApplication',NSHighResolutionCapable=True)))
PY
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"
