#!/usr/bin/env python3
"""R180: offscreen native historical/current captures, isolated from the app.

Usage: python3 scripts/render-height-comparison.py /tmp/tile-r180
Requires the project Xcode toolchain. Does not install, sign, or run the app UI.
"""
from pathlib import Path
import os, subprocess, sys, tarfile, io

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(sys.argv[1]).resolve()
OUT.mkdir(parents=True, exist_ok=True)
TEMPLATE = (ROOT / 'scripts/fixtures/height-comparison.swift').read_text()
LEGACY = 'f124946b07cec3b67ed301f6bbf48ae3871f7a3f'
CURRENT = '62bd1779c3f180fd76946461af51e1172b7797e6'

def change(path, before, after):
    text = path.read_text()
    if before not in text:
        raise RuntimeError(f'Expected source fragment missing: {path}: {before[:80]}')
    path.write_text(text.replace(before, after))

for mode, ref in [('legacy', LEGACY), ('current', CURRENT)]:
    if len(sys.argv) > 2 and sys.argv[2] != mode:
        continue
    stage = OUT / mode
    if stage.exists():
        raise RuntimeError(f'Use a fresh output directory: {stage}')
    stage.mkdir()
    archive = subprocess.check_output(['git', 'archive', ref], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(stage)
    src = stage / 'Sources/TileLauncher'
    swift = TEMPLATE
    if mode == 'legacy':
        swift = swift.replace('/*CASES*/', '[("a-base", CGFloat(1)), ("b-old-140", CGFloat(1.4))]')
        swift = swift.replace('/*FIT_CURRENT*/', '').replace('/*CHROME*/', '')
        swift = swift.replace('/*RADIUS*/', 'DeckSurfaceView.cornerRadius * layout.scale')
    else:
        # Isolated comparison ceiling only. Shipping source remains at 1.3.
        change(stage / 'Sources/DeckCore/Layout.swift', 'preferredScale: CGFloat = 1.3', 'preferredScale: CGFloat = 1.4')
        # Freeze the existing 1.3x grid gaps as well as the outer/header/footer
        # spacing. Text/icon sizes still use actual 1.4x point sizes.
        for file in ['TileArrangement.swift', 'DeckContentLayout.swift']:
            path = stage / 'Sources/DeckCore' / file
            change(path, 'gap = 8 * scale', 'gap = 8 * min(scale, 1.3)')
            change(path, '* 8) / CGFloat(', '* (8 * min(scale, 1.3) / scale)) / CGFloat(')
        change(stage / 'Sources/DeckCore/TileArrangement.swift',
               'menuWidth = unit * 4 + 24 * scale', 'menuWidth = unit * 4 + 3 * gap')
        swift = swift.replace('/*CASES*/', '[("c-now-130", CGFloat(1.3)), ("d-tile-140", CGFloat(1.4))]')
        swift = swift.replace('/*FIT_CURRENT*/', '''layout = layout.fittingContent(registeredCount: 39, workRows: fixture.content.snapshot.workRows())
            layout = PanelLayout(frame: CGRect(origin: .zero, size: CGSize(width: layout.frame.width,
                height: layout.frame.height - ChromeProposalPreview.largerTitle.heightReduction)),
                compact: layout.compact, supported: layout.supported, scale: layout.scale)''')
        swift = swift.replace('/*CHROME*/', 'previewChrome: .largerTitle,')
        swift = swift.replace('/*RADIUS*/', 'DeckSurfaceView.cornerRadius')
    (src / 'ScaleHeightExport.swift').write_text(swift)
    change(src / 'main.swift', 'try PreviewExport.render(to:', 'try ScaleHeightExport.render(to:')
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Develop/Xcode-beta.app/Contents/Developer')
    log = OUT / f'{mode}.log'
    with log.open('w') as handle:
        subprocess.run(['./scripts/preview.sh', str(OUT / 'renders')], cwd=stage, env=env,
                       stdout=handle, stderr=subprocess.STDOUT, check=True)
    print(mode, 'rendered', flush=True)

# Composite equal-width crops at the original point scale, with aligned tops.
renders = OUT / 'renders'
if all((renders / f'{name}-full.png').exists() for name in ['a-base', 'b-old-140', 'c-now-130', 'd-tile-140']):
    compiler_env = dict(os.environ, DEVELOPER_DIR='/Applications/Develop/Xcode-beta.app/Contents/Developer')
    subprocess.run(['xcrun', 'swiftc', str(ROOT / 'scripts/fixtures/height-comparison-sheet.swift'),
                    '-o', str(OUT / 'compose')], env=compiler_env, check=True)
    subprocess.run([str(OUT / 'compose'), str(renders)], env=compiler_env, check=True)
    print('Three comparison images ready:', renders, flush=True)
