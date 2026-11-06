import Foundation
import XCTest

final class MenuDiagnosticsBuildTests: XCTestCase {
    /// Runs only shell/argument plumbing. Both swift calls are stubs; the first
    /// copy is another stub that stops before metadata, xattr or signing steps.
    private func options(_ option: String?) throws -> (status: Int32, calls: String) {
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
        environment["TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS"] = option
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        _ = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, (try? String(contentsOf: args, encoding: .utf8)) ?? "")
    }
    func testDiagnosticFlagIsExplicitAndAppliedToBuildAndBinPath() throws {
        let flag = "-DTILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS"
        for option in [nil, "0", "1"] as [String?] {
            let result = try options(option)
            XCTAssertEqual(result.status, 73, "The stub copy stops before every signing/install step")
            let calls = result.calls.split(separator: "\n").map(String.init)
            XCTAssertEqual(calls.filter { $0 == "@call" }.count, 2)
            XCTAssertEqual(calls.filter { $0 == "--show-bin-path" }.count, 1)
            XCTAssertEqual(calls.filter { $0 == flag }.count, option == "1" ? 2 : 0)
            XCTAssertEqual(calls.filter { $0 == "-Xswiftc" }.count, option == "1" ? 2 : 0)
        }
    }
    func testInvalidDiagnosticFlagStopsBeforeAnyBuild() throws {
        let result = try options("yes")
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.calls.isEmpty)
    }
}
