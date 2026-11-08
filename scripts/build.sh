#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep caches inside the workspace; do not change the machine's xcode-select.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
SWIFT_BUILD_OPTIONS=(--configuration release --disable-sandbox
    --cache-path .build/cache --config-path .build/config --security-path .build/security)
case "${TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS:-0}" in
    0) ;;
    1) SWIFT_BUILD_OPTIONS+=(-Xswiftc -DTILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS) ;;
    *) printf '%s\n' 'TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS must be 0 or 1.' >&2; exit 2 ;;
esac
case "${TILE_LAUNCHER_PROFILE_DIAGNOSTICS:-0}" in
    0) ;;
    1) SWIFT_BUILD_OPTIONS+=(-Xswiftc -DTILE_LAUNCHER_PROFILE_DIAGNOSTICS) ;;
    *) printf '%s\n' 'TILE_LAUNCHER_PROFILE_DIAGNOSTICS must be 0 or 1.' >&2; exit 2 ;;
esac
swift build "${SWIFT_BUILD_OPTIONS[@]}" -debug-info-format none
BINARY_DIR="$(swift build "${SWIFT_BUILD_OPTIONS[@]}" --show-bin-path)"
OUTPUT_DIR="${TILE_LAUNCHER_OUTPUT_DIR:-$HOME/Library/Developer/TileLauncher/build}"
BUNDLE="$OUTPUT_DIR/Tile Launcher.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY_DIR/TileLauncher" "$BUNDLE/Contents/MacOS/TileLauncher"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
python3 - "$BUNDLE/Contents/Info.plist" <<'PY'
import json, plistlib, re, sys
from pathlib import Path
config = json.loads(Path('release/config.json').read_text())
assert re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', config['version']), 'Invalid version'
assert re.fullmatch(r'[1-9]\d*', config['build']), 'Invalid build number'
path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info.update(CFBundleShortVersionString=config['version'], CFBundleVersion=config['build'])
path.write_bytes(plistlib.dumps(info))
PY
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
python3 scripts/extract-intents.py "$BUNDLE"
# Identical compiled builds compare equal; source changes are distinguishable even
# before the next public version bump. Compute before ad-hoc signing modifies Mach-O.
BUILD_ID="$(shasum -a 256 "$BINARY_DIR/TileLauncher" | cut -d ' ' -f 1)"
/usr/libexec/PlistBuddy -c "Add :TileLauncherBuildID string $BUILD_ID" "$BUNDLE/Contents/Info.plist"
# Finder metadata on copied local build products is not part of the app signature.
xattr -cr "$BUNDLE"
codesign --force --sign - "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
printf '%s\n' "$BUNDLE"
