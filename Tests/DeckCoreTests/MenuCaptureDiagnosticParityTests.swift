import XCTest
@testable import DeckCore

#if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
/// Pins short-circuit reader traces independently of the diagnostic overload.
/// These fixtures contain no AX objects and never inspect another app.
final class MenuCaptureDiagnosticParityTests: XCTestCase {
    private final class Node {
        let id: Int
        var role: MenuHelpSearchRow.Role
        var parent: Node?
        var children: [Node]? = []
        var text: String?
        var path: [String]?
        var bounds: CGRect?
        init(_ id: Int, _ role: MenuHelpSearchRow.Role) { self.id = id; self.role = role }
    }
    private struct Fixture {
        let table: Node, row: Node, cell: Node, text: Node
        init() {
            table = Node(0, .table); table.path = ["Help"]
            row = Node(1, .row); row.parent = table
            row.bounds = CGRect(x: -500, y: 70, width: 320, height: 24)
            cell = Node(2, .cell); cell.parent = row; row.children = [cell]
            text = Node(3, .staticText); text.parent = cell
            text.text = "Private fixture title"; cell.children = [text]
        }
    }
    private func trace(_ node: Node) -> (MenuHelpSearchRow.Result?, [String], [MenuHelpSearchRow.Diagnostic]) {
        var calls: [String] = []
        var reports: [MenuHelpSearchRow.Diagnostic] = []
        let result = MenuHelpSearchRow.read(from: node,
            role: { calls.append("role:\($0.id)"); return $0.role },
            parent: { calls.append("parent:\($0.id)"); return $0.parent },
            children: { calls.append("children:\($0.id)"); return $0.children },
            staticText: { calls.append("text:\($0.id)"); return $0.text },
            frame: { calls.append("frame:\($0.id)"); return $0.bounds },
            menuPath: { calls.append("path:\($0.id)"); return $0.path },
            diagnostic: { reports.append($0) })
        return (result, calls, reports)
    }

    func testAncestorLimitDoesNotProbeSeventhNodeOrReadAnyText() throws {
        let ancestors = (0..<6).map { Node($0, .other) }
        for index in 0..<5 { ancestors[index].parent = ancestors[index + 1] }
        let rowOutsideLimit = Node(6, .row)
        ancestors[5].parent = rowOutsideLimit
        let (result, calls, reports) = trace(ancestors[0])
        XCTAssertNil(result)
        XCTAssertEqual(calls, (0..<6).flatMap { ["role:\($0)", "parent:\($0)"] })
        XCTAssertEqual(reports.count, 1)
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(report.failure, .noRow)
        XCTAssertFalse(report.helpOwned)
        XCTAssertEqual(report.cellCount, 0)
        XCTAssertEqual(report.labelCount, 0)
    }

    func testStructuralFailuresStopBeforeLaterReaders() throws {
        typealias Failure = MenuHelpSearchRow.Diagnostic.Failure
        let pathPrefix = ["role:1", "parent:1", "role:0", "path:0"]
        let childPrefix = pathPrefix + ["frame:1", "children:1"]
        let cases: [(String, (Fixture) -> Void, Failure, [String], Bool, Int)] = [
            ("detached row", { $0.row.parent = nil }, .noTable, ["role:1", "parent:1"], false, 0),
            ("wrong parent role", { $0.table.role = .other }, .tableRole,
             ["role:1", "parent:1", "role:0"], false, 0),
            ("missing ancestry", { $0.table.path = nil }, .menuPath, pathPrefix, false, 0),
            ("unreadable row", { $0.row.children = nil }, .rowChildren, childPrefix, true, 0),
            ("empty row", { $0.row.children = [] }, .cellCount, childPrefix, true, 0),
            ("too many cells", { f in f.row.children = (10..<15).map { Node($0, .cell) } },
             .cellCount, childPrefix, true, 5),
            ("non-cell child", { $0.cell.role = .other }, .cellRole,
             childPrefix + ["role:2"], true, 1),
        ]
        for (name, alter, failure, expectedCalls, helpOwned, cellCount) in cases {
            let fixture = Fixture(); alter(fixture)
            let (result, calls, reports) = trace(fixture.row)
            XCTAssertNil(result, name)
            XCTAssertEqual(calls, expectedCalls, name)
            XCTAssertEqual(reports.count, 1, name)
            let report = try XCTUnwrap(reports.first)
            XCTAssertEqual(report.failure, failure, name)
            XCTAssertEqual(report.helpOwned, helpOwned, name)
            XCTAssertEqual(report.cellCount, cellCount, name)
            XCTAssertEqual(report.labelCount, 0, name)
        }
    }

    func testContentLimitAndLabelAmbiguityKeepOriginalReadBoundaries() throws {
        let prefix = ["role:1", "parent:1", "role:0", "path:0", "frame:1", "children:1", "role:2", "children:2"]
        let oversized = Fixture()
        oversized.cell.children = (10..<19).map { Node($0, .staticText) }
        let (oversizedResult, oversizedCalls, oversizedReports) = trace(oversized.row)
        XCTAssertNil(oversizedResult)
        XCTAssertEqual(oversizedCalls, prefix, "The content cap must reject before reading any child roles or values")
        XCTAssertEqual(oversizedReports.count, 1)
        XCTAssertEqual(try XCTUnwrap(oversizedReports.first).failure, .contentCount)

        let ambiguous = Fixture()
        let second = Node(4, .staticText); second.text = "Another private fixture title"
        let third = Node(5, .staticText); third.text = "Third private fixture title"
        ambiguous.cell.children = [ambiguous.text, second, third]
        let (result, calls, reports) = trace(ambiguous.row)
        XCTAssertNil(result)
        XCTAssertEqual(calls, prefix + ["role:3", "text:3", "role:4", "text:4", "role:5", "text:5"],
                       "Do not add reads, or change the original all-label counting traversal")
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(report.failure, .labelCount)
        XCTAssertEqual(report.labelCount, 3)
        XCTAssertFalse(String(reflecting: report).contains("private fixture title"),
                       "Only failure/count metadata may escape in the diagnostic report")
    }

    func testResolutionCountsDistinctCommandsWithoutReintroducingAppleOrDuplicateObservations() throws {
        let command = CapturedMenu(appID: "fixture", appName: "Fixture", path: ["File", "PDF…"],
                                   shortcut: "p", commandModifier: true, axIdentifier: "pdf-command")
        let apple = CapturedMenu(appID: "fixture", appName: "Fixture", path: ["Apple", "PDF…"],
                                 axIdentifier: "system-command")
        var reports: [MenuCapturePolicy.HelpResolutionDiagnostic] = []
        let result = try XCTUnwrap(MenuCapturePolicy.resolveHelp(title: "PDF...", choices: [apple, command, command],
                                                                 diagnostic: { reports.append($0) }))
        XCTAssertEqual(result.identity, command.identity)
        XCTAssertEqual(result.shortcut, command.shortcut)
        XCTAssertEqual(result.axIdentifier, command.axIdentifier)
        XCTAssertTrue(result.fromHelpSearch)
        XCTAssertEqual(reports.count, 1)
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(report.candidateCount, 2, "Apple paths are excluded; repeated observations are still counted")
        XCTAssertEqual(report.identityCount, 1, "Repeated observations of one command are not ambiguity")
        XCTAssertEqual(report.identifierCount, 1)
    }

    func testPolicyRejectionDoesNotConsumeGestureAndExpiryBoundaryIsInclusive() throws {
        let command = CapturedMenu(appID: "fixture", appName: "Fixture", path: ["File", "Export"])
        var blocked = MenuCapturePreferences(); blocked.excludedMenus.insert(command.identity)
        var gate = MenuCaptureGate()
        gate.arm(time: 0)
        var reasons: [MenuCaptureGate.DiagnosticOutcome] = []
        XCTAssertNil(gate.take(command, matchedUserSelection: true, time: 0.1, preferences: blocked,
                               diagnostic: { reasons.append($0) }))
        guard case .policyRejected? = reasons.last else { return XCTFail("Expected a policy rejection") }
        XCTAssertEqual(reasons.count, 1)
        XCTAssertNotNil(gate.take(command, matchedUserSelection: true, time: 0.8, preferences: .init(),
                                  diagnostic: { reasons.append($0) }), "The 0.8-second boundary remains inclusive")
        guard case .accepted? = reasons.last else { return XCTFail("Policy rejection must not consume the gesture") }
        XCTAssertEqual(reasons.count, 2)

        // Expiry takes precedence over mismatch and policy rejection, as in the
        // original guard order, and a fresh gesture is not poisoned by it.
        gate.arm(time: 0)
        XCTAssertNil(gate.take(command, matchedUserSelection: false, time: 0.800_001, preferences: blocked,
                               diagnostic: { reasons.append($0) }))
        guard case .expired? = reasons.last else { return XCTFail("Expected expiry before later rejection gates") }
        gate.arm(time: 1)
        XCTAssertNotNil(gate.take(command, matchedUserSelection: true, time: 1.1, preferences: .init(),
                                  diagnostic: { reasons.append($0) }))
        guard case .accepted? = reasons.last else { return XCTFail("A fresh gesture must remain usable") }
        XCTAssertEqual(reasons.count, 4)
    }
}
#endif
