// UI-free fixture. Compile only with verify-instance-handoff.py's unique bundle ID.
import AppKit
import DeckCore

enum AppIdentity {
    static let bundleID = Bundle.main.bundleIdentifier!
}
precondition(AppIdentity.bundleID.hasPrefix("dev.cola16.TileLauncher.handoff-test."))
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let build = try InstanceCoordinator.build(at: Bundle.main.bundleURL)
guard let lock = try InstanceCoordinator.acquire(build: build) else { exit(0) }
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    let replacement = BuildReplacement(running: build)
    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = Bundle.main.object(forInfoDictionaryKey: "ProbeDirectory") as! String
        let ready = URL(fileURLWithPath: root).appendingPathComponent("ready-\(getpid())")
        try! Data(build.fingerprint.utf8).write(to: ready)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        do { _ = try replacement.requestIfChanged(arguments: [], activates: false) { fputs($0, stderr) } }
        catch { fputs(error.localizedDescription, stderr) }
        return false
    }
}
let delegate = ProbeDelegate()
app.delegate = delegate
// A failed driver cannot leave a fixture running indefinitely.
DispatchQueue.main.asyncAfter(deadline: .now() + 90) { app.terminate(nil) }
withExtendedLifetime(lock) { app.run() }
