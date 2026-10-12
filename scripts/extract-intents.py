#!/usr/bin/env python3
"""Package the compiler's App Intents values; no private Focus preferences are read."""
from pathlib import Path
import platform
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
bundle = Path(sys.argv[1])

def output(*args):
    return subprocess.check_output(args, text=True).strip()

values = sorted(root.glob('.build/out/Intermediates.noindex/TileLauncher.build/Release/TileLauncher-p.build/**/*.swiftconstvalues'))
if not values:
    values = sorted(root.glob('.build/*/release/TileLauncher.build/*.swiftconstvalues'))
if not values:
    raise SystemExit('App Intents constant values are missing. Build with the full supported Xcode toolchain.')
work = root / '.build' / 'intent-packaging'
work.mkdir(parents=True, exist_ok=True)
sources = work / 'sources.list'
constants = work / 'constants.list'
sources.write_text('\n'.join(str(p) for p in sorted(root.glob('Sources/TileLauncher/*.swift'))) + '\n')
constants.write_text('\n'.join(map(str, values)) + '\n')
toolchain = Path(output('xcrun', '--find', 'swiftc')).parent.parent.parent
xcode = output('xcodebuild', '-version').split('Build version ')[-1].strip()
subprocess.run([
    'xcrun', 'appintentsmetadataprocessor',
    '--output', str(bundle / 'Contents/Resources'),
    '--toolchain-dir', str(toolchain), '--module-name', 'TileLauncher',
    '--sdk-root', output('xcrun', '--sdk', 'macosx', '--show-sdk-path'),
    '--xcode-version', xcode, '--platform-family', 'macOS',
    '--deployment-target', '26.0', '--target-triple', f'{platform.machine()}-apple-macos26.0',
    '--source-file-list', str(sources), '--swift-const-vals-list', str(constants),
], check=True)
metadata = bundle / 'Contents/Resources/Metadata.appintents/extract.actionsdata'
if not metadata.is_file() or 'LauncherFocusIntent' not in metadata.read_text():
    raise SystemExit('Focus filter metadata was not generated.')
