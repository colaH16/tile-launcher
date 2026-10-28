import XCTest
@testable import DeckCore

final class MenuHelpSearchRowTests: XCTestCase {
    private final class Node {
        let role: MenuHelpSearchRow.Role
        var parent: Node?
        var children: [Node]? = []
        var text: String?
        var path: [String]?
        var bounds: CGRect?
        init(_ role: MenuHelpSearchRow.Role, parent: Node? = nil) {
            self.role = role; self.parent = parent
            parent?.children?.append(self)
        }
    }
    private func fixture(_ title: String = "New Window") -> (table: Node, row: Node, cell: Node, text: Node) {
        let table = Node(.table); table.path = ["Help"]
        let row = Node(.row, parent: table)
        row.bounds = CGRect(x: -690, y: 76, width: 360, height: 24)
        let cell = Node(.cell, parent: row)
        _ = Node(.other, parent: cell) // The menu icon has no AXPress action either.
        let text = Node(.staticText, parent: cell); text.text = title
        return (table, row, cell, text)
    }
    private func read(_ node: Node) -> MenuHelpSearchRow.Result? {
        MenuHelpSearchRow.read(from: node, role: { $0.role }, parent: { $0.parent },
                              children: { $0.children }, staticText: {
            XCTAssertEqual($0.role, .staticText, "Never read a search field or terminal value")
            return $0.text
        }, frame: { $0.bounds }, menuPath: { $0.path })
    }
    func testNonPressableHelpRowsCaptureBothITermCommandsOnMouseRelease() throws {
        for title in ["New Window", "New Window with Current Profile"] {
            let f = fixture(title)
            let canonical = CapturedMenu(appID: "com.googlecode.iterm2", appName: "iTerm2",
                                         path: ["Shell", title], shortcut: "N", commandModifier: true)
            for original in [f.row, f.cell, f.text, f.cell.children![0]] {
                let hit = try XCTUnwrap(read(original))
                let menu = try XCTUnwrap(MenuCapturePolicy.resolveHelp(title: hit.label, choices: [canonical]))
                XCTAssertEqual(menu.identity.path, ["Shell", title])
                XCTAssertTrue(menu.fromHelpSearch)
                let point = CGPoint(x: -675, y: 88) // Icon/row padding, outside the text label.
                var gate = MenuCaptureGate()
                XCTAssertNil(gate.take(menu, matchedUserSelection: true, time: 1, preferences: .init()))
                gate.arm(time: 1.1)
                XCTAssertNotNil(gate.take(menu, matchedUserSelection: hit.frame.contains(point), time: 1.1, preferences: .init()))
                XCTAssertNil(gate.take(menu, matchedUserSelection: true, time: 1.2, preferences: .init()))
            }
        }
    }
    func testOtherTablesAppleMenusAndDetachedResultsAreNotMenuCommands() {
        let f = fixture()
        for path in [nil, ["Shell"], ["Apple"], ["Help", "Unrelated submenu"]] as [[String]?] {
            f.table.path = path
            XCTAssertNil(read(f.text))
        }
        f.table.path = ["도움말"]
        XCTAssertNotNil(read(f.text))
        f.row.parent = nil
        XCTAssertNil(read(f.text))
    }
    func testUnknownChildrenAmbiguousLabelsAndInvisibleRowsAreRejected() {
        let f = fixture()
        f.cell.children = nil
        XCTAssertNil(read(f.row))
        f.cell.children = [f.text]
        let other = Node(.staticText, parent: f.cell); other.text = "Another command"
        XCTAssertNil(read(f.row))
        f.cell.children = [f.text]
        for bounds in [CGRect.zero, CGRect(x: 0, y: 0, width: -1, height: 1),
                       CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10)] {
            f.row.bounds = bounds
            XCTAssertNil(read(f.row))
        }
    }
    func testReleaseOutsideTheSearchRowDoesNotCaptureHighlightedCommand() throws {
        let f = fixture()
        let hit = try XCTUnwrap(read(f.row))
        let menu = CapturedMenu(appID: "iterm", appName: "iTerm", path: ["Shell", hit.label])
        var gate = MenuCaptureGate(); gate.arm(time: 1)
        XCTAssertNil(gate.take(menu, matchedUserSelection: hit.frame.contains(CGPoint(x: 50, y: 50)),
                               time: 1.1, preferences: .init()))
    }
    func testBreadcrumbSearchLabelsResolveOnlyUniqueRealMenuPaths() {
        let a = CapturedMenu(appID: "iterm", appName: "iTerm", path: ["Profiles", "bonjour", "Open All in New Window"])
        let b = CapturedMenu(appID: "iterm", appName: "iTerm", path: ["Profiles", "Open All in New Window"])
        XCTAssertEqual(MenuCapturePolicy.resolveHelp(title: "bonjour > Open All in New Window", choices: [a, b])?.identity, a.identity)
        XCTAssertNil(MenuCapturePolicy.resolveHelp(title: "Open All in New Window", choices: [a, b]))
        let otherRoot = CapturedMenu(appID: "iterm", appName: "iTerm", path: ["Other", "bonjour", "Open All in New Window"])
        XCTAssertNil(MenuCapturePolicy.resolveHelp(title: "bonjour > Open All in New Window", choices: [a, otherRoot]))
        let literal = CapturedMenu(appID: "iterm", appName: "iTerm", path: ["Tools", "bonjour > Open All in New Window"])
        XCTAssertEqual(MenuCapturePolicy.resolveHelp(title: literal.identity.path.last!, choices: [literal])?.identity, literal.identity)
        XCTAssertNil(MenuCapturePolicy.resolveHelp(title: literal.identity.path.last!, choices: [literal, a]))
        let apple = CapturedMenu(appID: "iterm", appName: "iTerm", path: ["Apple", "Recent Items", "Example"])
        XCTAssertNil(MenuCapturePolicy.resolveHelp(title: "Recent Items > Example", choices: [apple]))
    }
}
