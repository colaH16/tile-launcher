import Foundation
import XCTest

final class MenuDiagnosticsBuildTests: XCTestCase {
    /// Runs only shell/argument plumbing. Both swift calls are stubs; the first
    /// copy is another stub that stops before metadata, xattr or signing steps.
    private func options(menu: String?, profile: String?) throws -> (status: Int32, calls: String) {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("tile-menu-build-options-" + UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let bin = directory.appendingPathComponent("bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let swift = bin.appendingPathComponent("swift")
        try """
        #!/bin/bash
        printf '%s\\n' '@call' "$@" >> "$TILE_LAUNCHER_TEST_SWIFT_ARGUMENTS"
        for option in "$@"; do
            if [[ "$option" == '--show-bin-path' ]]; then
                printf '%s\\n' "$TILE_LAUNCHER_TEST_BINARY_DIRECTORY"
            fi
        done
        exit 0
        """.write(to: swift, atomically: true, encoding: .utf8)
        let copy = bin.appendingPathComponent("cp")
        try "#!/bin/bash\nexit 73\n".write(to: copy, atomically: true, encoding: .utf8)
        for path in [swift, copy] { try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path) }
        let args = directory.appendingPathComponent("arguments.txt")
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repository.appendingPathComponent("scripts/build.sh").path]
        process.currentDirectoryURL = repository
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "BASH_ENV")
        environment.removeValue(forKey: "ENV")
        environment["PATH"] = bin.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        environment["TILE_LAUNCHER_TEST_SWIFT_ARGUMENTS"] = args.path
        environment["TILE_LAUNCHER_TEST_BINARY_DIRECTORY"] = bin.path
        environment["TILE_LAUNCHER_OUTPUT_DIR"] = directory.appendingPathComponent("synthetic-products").path
        // Each case owns both switches, independent of the parent build matrix.
        // A nil value removes an inherited setting and checks the default OFF.
        environment["TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS"] = menu
        environment["TILE_LAUNCHER_PROFILE_DIAGNOSTICS"] = profile
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        _ = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, (try? String(contentsOf: args, encoding: .utf8)) ?? "")
    }
    func testDiagnosticFlagsAreExplicitAndAppliedToBuildAndBinPath() throws {
        let cases: [(String?, String?)] = [(nil, nil), ("0", "0"), ("1", "0"), ("0", "1"), ("1", "1")]
        for (menu, profile) in cases {
            let result = try options(menu: menu, profile: profile)
            XCTAssertEqual(result.status, 73, "The stub copy stops before every signing/install step")
            let calls = result.calls.split(separator: "\n").map(String.init)
            XCTAssertEqual(calls.filter { $0 == "@call" }.count, 2)
            XCTAssertEqual(calls.filter { $0 == "--show-bin-path" }.count, 1)
            let invocations = result.calls.components(separatedBy: "@call\n").dropFirst()
                .map { $0.split(separator: "\n").map(String.init) }
            XCTAssertEqual(invocations.count, 2)
            let enabled = (menu == "1" ? 1 : 0) + (profile == "1" ? 1 : 0)
            for arguments in invocations {
                XCTAssertEqual(arguments.filter { $0 == "-DTILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS" }.count,
                               menu == "1" ? 1 : 0)
                XCTAssertEqual(arguments.filter { $0 == "-DTILE_LAUNCHER_PROFILE_DIAGNOSTICS" }.count,
                               profile == "1" ? 1 : 0)
                XCTAssertEqual(arguments.filter { $0 == "-Xswiftc" }.count, enabled)
            }
        }
    }
    func testInvalidDiagnosticFlagStopsBeforeAnyBuild() throws {
        for (menu, profile) in [("yes", "0"), ("0", "yes")] {
            let result = try options(menu: menu, profile: profile)
            XCTAssertEqual(result.status, 2)
            XCTAssertTrue(result.calls.isEmpty)
        }
    }
}
