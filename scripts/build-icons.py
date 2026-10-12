#!/usr/bin/env python3
"""Package the generated source as the standard macOS icon representations."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
source = root / "Resources/Brand/AppIcon-source.png"
with tempfile.TemporaryDirectory(prefix="tile-launcher-icons-") as temp:
    iconset = Path(temp) / "AppIcon.iconset"
    iconset.mkdir()
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = "@2x" if scale == 2 else ""
            output = iconset / f"icon_{size}x{size}{suffix}.png"
            subprocess.run(["sips", "-z", str(size * scale), str(size * scale),
                            str(source), "--out", str(output)],
                           check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o",
                    str(root / "Resources/AppIcon.icns")], check=True)
