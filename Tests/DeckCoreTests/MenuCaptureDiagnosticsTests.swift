import XCTest
@testable import DeckCore

final class MenuCaptureDiagnosticsTests: XCTestCase {
    private final class Node {
        let id: Int
        var role: MenuHelpSearchRow.Role
        var parent: Node?
        var children: [Node]?
        var text: String?
        var path: [String]?
        var frame: CGRect?
        init(_ id: Int, _ role: MenuHelpSearchRow.Role) { self.id = id; self.role = role; children = [] }
    }
    private func fixture() -> (table: Node, row: Node, cell: Node, text: Node) {
        let table = Node(0, .table); table.path = ["Help"]
        let row = Node(1, .row); row.parent = table; table.children = [row]
        row.frame = CGRect(x: -900, y: 120, width: 360, height: 24)
        let cell = Node(2, .cell); cell.parent = row; row.children = [cell]
        let text = Node(3, .staticText); text.parent = cell; text.text = "Export To > PDF…"; cell.children = [text]
        return (table, row, cell, text)
    }
    private func read(_ node: Node, calls: inout [String]) -> MenuHelpSearchRow.Result? {
        // The trace records accessor order, never a second traversal or read.
        var result: [String] = []
        let value = MenuHelpSearchRow.read(from: node,
            role: { result.append("role:\($0.id)"); return $0.role },
            parent: { result.append("parent:\($0.id)"); return $0.parent },
            children: { result.append("children:\($0.id)"); return $0.children },
            staticText: { result.append("text:\($0.id)"); return $0.text },
            frame: { result.append("frame:\($0.id)"); return $0.frame },
            menuPath: { result.append("path:\($0.id)"); return $0.path })
        calls = result
        return value
    }
    func testHelpRowAccessorOrderIsPinnedForBothBuildConfigurations() throws {
        let f = fixture()
        var calls: [String] = []
        let result = try XCTUnwrap(read(f.text, calls: &calls))
        XCTAssertEqual(result.label, "Export To > PDF…")
        XCTAssertEqual(result.frame, f.row.frame)
        XCTAssertEqual(calls, ["role:3", "parent:3", "role:2", "parent:2", "role:1", "parent:1", "role:0",
                               "path:0", "frame:1", "children:1", "role:2", "children:2", "role:3", "text:3"])
        f.table.path = ["File"]
        XCTAssertNil(read(f.text, calls: &calls))
        XCTAssertEqual(calls, ["role:3", "parent:3", "role:2", "parent:2", "role:1", "parent:1", "role:0", "path:0"])
    }

    #if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
    func testReasonTapPreservesReaderCallsAndDoesNotExposeLabels() throws {
        let f = fixture()
        for scenario in 0..<5 {
            f.table.path = scenario == 1 ? ["File"] : ["Help"]
            f.row.frame = scenario == 2 ? .zero : CGRect(x: -900, y: 120, width: 360, height: 24)
            f.cell.children = scenario == 3 ? nil : [f.text]
            f.text.text = scenario == 4 ? "" : "Export To > PDF…"
            var expected: [String] = []
            let normal = read(f.text, calls: &expected)
            var calls: [String] = []
            var diagnostic: MenuHelpSearchRow.Diagnostic?
            let traced = MenuHelpSearchRow.read(from: f.text,
                role: { calls.append("role:\($0.id)"); return $0.role },
                parent: { calls.append("parent:\($0.id)"); return $0.parent },
                children: { calls.append("children:\($0.id)"); return $0.children },
                staticText: { calls.append("text:\($0.id)"); return $0.text },
                frame: { calls.append("frame:\($0.id)"); return $0.frame },
                menuPath: { calls.append("path:\($0.id)"); return $0.path },
                diagnostic: { diagnostic = $0 })
            XCTAssertEqual(traced, normal)
            XCTAssertEqual(calls, expected, "Enabling the reason tap must not add/reorder supplied readers")
            let detail = try XCTUnwrap(diagnostic)
            let reasons: [MenuHelpSearchRow.Diagnostic.Failure] = [.none, .helpOwnership, .rowFrame, .cellChildren, .labelValue]
            XCTAssertEqual(detail.failure, reasons[scenario])
            XCTAssertEqual(detail.helpOwned, scenario != 1)
            XCTAssertEqual(detail.cellCount, scenario == 1 || scenario == 2 ? 0 : 1)
        }
    }
    func testHelpResolutionTapPreservesLiteralBreadcrumbAndIdentityAmbiguity() throws {
        let pdf = CapturedMenu(appID: "fixture", appName: "Fixture", path: ["File", "Export To", "PDF…"], axIdentifier: "one")
        let literal = CapturedMenu(appID: "fixture", appName: "Fixture", path: ["File", "Export To > PDF…"], axIdentifier: "two")
        let other = CapturedMenu(appID: "fixture", appName: "Fixture", path: ["Other", "Export To", "PDF…"], axIdentifier: "three")
        for choices in [[], [pdf], [pdf, literal], [pdf, other]] as [[CapturedMenu]] {
            var diagnostic: MenuCapturePolicy.HelpResolutionDiagnostic?
            let result = MenuCapturePolicy.resolveHelp(title: "Export To > PDF…", choices: choices, diagnostic: { diagnostic = $0 })
            XCTAssertEqual(result, MenuCapturePolicy.resolveHelp(title: "Export To > PDF…", choices: choices))
            let detail = try XCTUnwrap(diagnostic)
            XCTAssertEqual(detail.candidateCount, choices.count)
            XCTAssertEqual(detail.identityCount, choices.count)
            XCTAssertEqual(detail.identifierCount, choices.count == 1 ? 1 : nil)
            XCTAssertEqual(result != nil, choices.count == 1)
        }
        var duplicate = pdf
        // Same path but conflicting identifiers must remain rejected.
        duplicate = CapturedMenu(appID: "fixture", appName: "Fixture", path: pdf.identity.path, axIdentifier: "different")
        var count: Int?
        XCTAssertNil(MenuCapturePolicy.resolveHelp(title: "PDF…", choices: [pdf, duplicate], diagnostic: { count = $0.identifierCount }))
        XCTAssertEqual(count, 2)
    }
    func testPhysicalGateDiagnosticTapPreservesConsumptionAndRejections() {
        let menu = CapturedMenu(appID: "fixture", appName: "Fixture", path: ["File", "Export"])
        var normal = MenuCaptureGate(), traced = MenuCaptureGate()
        var reason: MenuCaptureGate.DiagnosticOutcome?
        func take(_ time: TimeInterval, _ match: Bool, _ expected: MenuCaptureGate.DiagnosticOutcome) {
            let result = traced.take(menu, matchedUserSelection: match, time: time, preferences: .init(), diagnostic: { reason = $0 })
            XCTAssertEqual(result, normal.take(menu, matchedUserSelection: match, time: time, preferences: .init()))
            switch (reason, expected) {
            case (.unarmed, .unarmed), (.beforeArm, .beforeArm), (.unmatched, .unmatched),
                 (.accepted, .accepted), (.consumed, .consumed), (.expired, .expired): break
            default: XCTFail("Incorrect physical gate reason")
            }
        }
        take(1, true, .unarmed)
        normal.arm(time: 2); traced.arm(time: 2)
        take(1.9, true, .beforeArm)
        take(2.1, false, .unmatched)
        take(2.2, true, .accepted)
        take(2.3, true, .consumed)
        normal.arm(time: 3); traced.arm(time: 3)
        take(3.9, true, .expired)
        normal.cancel(); traced.cancel()
        take(4, true, .unarmed)
    }
    #endif
}
