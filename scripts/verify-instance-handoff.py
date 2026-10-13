#!/usr/bin/env python3
"""Exercise production instance code in unique, windowless fixture app bundles.

No production app, settings, accessibility permission, status item or input monitor
is used. Requires macOS Launch Services and Xcode; never automates the user's UI.
"""
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

repo = Path(__file__).resolve().parents[1]
root = Path(tempfile.mkdtemp(prefix="tile-handoff-"))
identifier = "dev.cola16.TileLauncher.handoff-test." + str(uuid.uuid4())
owner_dir = Path.home() / "Library/Application Support" / identifier
pids = set()


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}):\n{result.stdout}\n{result.stderr}")
    return result


def owner():
    try:
        value = json.loads((owner_dir / "instance-owner.json").read_text())
        pids.add(value["process"]["pid"])
        return value
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def wait_for(predicate, description):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        value = owner()
        if value and (root / f'ready-{value["process"]["pid"]}').exists() and predicate(value):
            return value
        time.sleep(0.05)
    raise AssertionError(description)


def bundle(name, fingerprint, version="1.0"):
    dest = root / (name + ".app")
    executable = dest / "Contents/MacOS/Probe"
    executable.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / "Probe", executable)
    with (dest / "Contents/Info.plist").open("wb") as f:
        plistlib.dump(dict(CFBundleIdentifier=identifier, CFBundleName="Tile Handoff Test",
                          CFBundleExecutable="Probe", CFBundlePackageType="APPL", LSUIElement=True,
                          CFBundleShortVersionString=version, CFBundleVersion="1",
                          TileLauncherBuildID=fingerprint, ProbeDirectory=str(root)), f)
    run("/usr/bin/codesign", "--force", "--sign", "-", str(dest))
    return dest


def launch(path, new=True):
    run("/usr/bin/open", "-g", "-j", *(["-n"] if new else []), str(path))


try:
    core = repo / "Sources/DeckCore"
    run("xcrun", "swiftc", "-emit-library", "-static", "-emit-module", "-module-name", "DeckCore",
        str(core / "InstanceIdentity.swift"), str(core / "InstanceLock.swift"),
        "-emit-module-path", str(root / "DeckCore.swiftmodule"), "-o", str(root / "libDeckCore.a"))
    shutil.copy2(repo / "scripts/fixtures/instance-main.swift", root / "main.swift")
    run("xcrun", "swiftc", "-I", str(root), "-L", str(root), "-lDeckCore",
        str(repo / "Sources/TileLauncher/InstanceCoordinator.swift"),
        str(repo / "Sources/TileLauncher/BuildReplacement.swift"),
        str(root / "main.swift"), "-o", str(root / "Probe"))
    first_bundle = bundle("First", "a")
    second_bundle = bundle("Second", "b", "2.0")
    launch(first_bundle)
    first = wait_for(lambda x: x["build"]["fingerprint"] == "a", "initial launch")
    launch(first_bundle)
    # Same-build candidate exits, leaving the existing owner's process untouched.
    time.sleep(1)
    assert owner() == first and alive(first["process"]["pid"])
    print("PASS same build keeps existing process", flush=True)
    launch(second_bundle)
    second = wait_for(lambda x: x["build"]["fingerprint"] == "b", "upgrade")
    assert not alive(first["process"]["pid"])
    print("PASS newer build replaces and waits for old process exit", flush=True)
    launch(first_bundle)
    older = wait_for(lambda x: x["build"]["fingerprint"] == "a", "downgrade")
    assert not alive(second["process"]["pid"])
    print("PASS older version launched last also replaces", flush=True)
    # Replace the bundle in place while the old process retains its startup build.
    bundle("First", "c")
    assert owner() == older
    launch(first_bundle, new=False)
    replaced = wait_for(lambda x: x["build"]["fingerprint"] == "c", "Finder-style reopen after in-place rebuild")
    assert not alive(older["process"]["pid"])
    print("PASS ordinary reopen replaces changed build at same path/version", flush=True)
    print("All isolated instance handoff checks passed.", flush=True)
finally:
    # Only PIDs proven by this UUID's owner records are eligible for cleanup.
    for pid in pids:
        try:
            command = run("/bin/ps", "-p", str(pid), "-o", "command=").stdout.strip()
            if str(root) in command:
                os.kill(pid, signal.SIGTERM)
        except (ProcessLookupError, RuntimeError):
            pass
    # Test artifacts are useful after a failure; harmless UUID data stays in /tmp.
    if owner_dir.exists():
        shutil.rmtree(owner_dir)
    print("Fixture files:", root, flush=True)
