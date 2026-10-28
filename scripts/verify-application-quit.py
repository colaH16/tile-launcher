#!/usr/bin/env python3
"""Exercise the production normal-quit helper against an isolated, windowless app."""
import os, pathlib, plistlib, signal, subprocess, tempfile, uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="tile-quit-check-") as folder:
    root = pathlib.Path(folder)
    app = root / "Quit Fixture.app"
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "dev.cola16.TileLauncher.quitfixture." + uuid.uuid4().hex,
        "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL",
        "LSUIElement": True, "CFBundleName": "Quit Fixture",
    }))
    fixture = root / "fixture.swift"
    fixture.write_text(r"""
import AppKit
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let root = Bundle.main.bundleURL.deletingLastPathComponent()
        try? Data("requested".utf8).write(to: root.appendingPathComponent("requested"))
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("cancel").path) ? .terminateCancel : .terminateNow
    }
}
let application = NSApplication.shared
let delegate = Delegate()
application.delegate = delegate
let root = Bundle.main.bundleURL.deletingLastPathComponent()
try? Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: root.appendingPathComponent("fixture-pid"))
application.run()
""")
    harness = root / "main.swift"
    harness.write_text(r"""
import AppKit
func wait(_ ready: () -> Bool) {
    let limit = Date().addingTimeInterval(8)
    while !ready() && Date() < limit { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    precondition(ready(), "fixture timeout")
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
precondition(ApplicationTermination.request(nil) != nil)
precondition(ApplicationTermination.request(.current) != nil)
let config = NSWorkspace.OpenConfiguration()
config.activates = false
config.createsNewApplicationInstance = true
var running: NSRunningApplication?
var finished = false
NSWorkspace.shared.openApplication(at: root.appendingPathComponent("Quit Fixture.app"), configuration: config) { app, error in
    precondition(error == nil)
    running = app
    finished = true
}
wait { finished }
let app = running!
wait { app.isFinishedLaunching }
try Data().write(to: root.appendingPathComponent("cancel"))
precondition(ApplicationTermination.request(app) == nil)
wait { FileManager.default.fileExists(atPath: root.appendingPathComponent("requested").path) }
precondition(!app.isTerminated, "normal quit must respect cancellation")
try FileManager.default.removeItem(at: root.appendingPathComponent("cancel"))
precondition(ApplicationTermination.request(app) == nil)
wait { app.isTerminated }
precondition(ApplicationTermination.request(app) != nil, "stale captured instance must not target a reused PID")
print("ApplicationTermination: nil/self/stale rejected; normal quit respects cancellation and terminates only isolated fixture.")
""")
    compiler = ["xcrun", "swiftc", "-module-cache-path", str(root / "cache")]
    subprocess.run(compiler + [str(fixture), "-o", str(app / "Contents/MacOS/Fixture")], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    binary = root / "check"
    subprocess.run(compiler + [str(ROOT / "Sources/TileLauncher/ApplicationTermination.swift"), str(harness), "-o", str(binary)], check=True)
    try:
        subprocess.run([str(binary), str(root)], check=True, timeout=40)
    finally:
        # Only clean up this disposable fixture if a failed check left it alive.
        pid_file = root / "fixture-pid"
        if pid_file.exists():
            pid = int(pid_file.read_text())
            process = subprocess.run(["ps", "-p", str(pid), "-o", "comm="], capture_output=True, text=True)
            if process.stdout.strip() == str(app / "Contents/MacOS/Fixture"):
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
