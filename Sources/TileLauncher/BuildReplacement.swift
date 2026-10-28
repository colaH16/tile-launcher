import AppKit
import DeckCore
import OSLog

/// Finder may deliver a reopen event to the running binary after an in-place
/// update. Explicitly launch the bundle on disk; InstanceCoordinator performs
/// the same last-launch-wins handoff used when opening a different app copy.
final class BuildReplacement {
    private let running: AppBuild
    private let bundleURL: URL
    private var requested = false
    private let log = Logger(subsystem: AppIdentity.bundleID, category: "instance")
    init(running: AppBuild, bundleURL: URL = Bundle.main.bundleURL) {
        self.running = running; self.bundleURL = bundleURL
    }
    func requestIfChanged(arguments: [String], activates: Bool = true,
                          onFailure: @escaping (String) -> Void) throws -> Bool {
        let disk = try InstanceCoordinator.build(at: bundleURL)
        guard disk != running else {
            log.info("Reopen keeps current build \(self.running.fingerprint.prefix(12), privacy: .public)")
            return false
        }
        guard !requested else { return true }
        requested = true
        log.info("Reopen requests build replacement \(self.running.fingerprint.prefix(12), privacy: .public) -> \(disk.fingerprint.prefix(12), privacy: .public)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.activates = activates
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { [weak self] _, failure in
            DispatchQueue.main.async {
                if let failure {
                    self?.requested = false
                    onFailure(failure.localizedDescription)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.requested = false }
        return true
    }
}
