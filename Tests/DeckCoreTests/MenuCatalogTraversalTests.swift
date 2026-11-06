import XCTest
@testable import DeckCore

final class MenuCatalogTraversalTests: XCTestCase {
    private enum Fault { case none, unavailable, failure }
    private final class Node {
        let id: Int
        var role: MenuCatalogTraversal.Role
        var title: String
        var children: [Node]
        var roleFault = Fault.none
        var titleFault = Fault.none
        var childrenFault = Fault.none
        init(_ id: Int, _ role: MenuCatalogTraversal.Role, _ title: String = "", _ children: [Node] = []) {
            self.id = id; self.role = role; self.title = title; self.children = children
        }
    }
    private typealias Traversal = MenuCatalogTraversal
    private func read<Value>(_ value: Value, fault: Fault) -> Traversal.Read<Value> {
        switch fault {
        case .none: return .value(value)
        case .unavailable: return .unavailable
        case .failure: return .failure
        }
    }
    private func run(_ roots: [Traversal.Root<Node>], rootFault: Fault = .none,
                     limits: Traversal.Limits = .init(), hasTime: () -> Bool = { true },
                     cancelled: () -> Bool = { false },
                     didRead: ((Traversal.Attribute) -> Void)? = nil) -> (Traversal.Outcome<Node>, [String]) {
        var calls: [String] = []
        let result = Traversal.scan(roots: {
            calls.append("roots"); didRead?(.roots)
            return self.read(roots, fault: rootFault)
        }, role: { node in
            calls.append("role:\(node.id)"); didRead?(.role)
            return self.read(node.role, fault: node.roleFault)
        }, title: { node in
            calls.append("title:\(node.id)"); didRead?(.title)
            if [.container, .structuralGroup, .controlLeaf].contains(node.role) {
                XCTFail("Structural/control titles must never be read")
            }
            return self.read(node.title, fault: node.titleFault)
        }, children: { node in
            calls.append("children:\(node.id)"); didRead?(.children)
            return self.read(node.children, fault: node.childrenFault)
        }, hasTime: hasTime, isCancelled: cancelled, limits: limits)
        return (result, calls)
    }
    private func failure(_ value: Traversal.Outcome<Node>, file: StaticString = #filePath, line: UInt = #line) -> Traversal.Failure? {
        switch value {
        case .incomplete(let reason, _): return reason
        case .complete: XCTFail("A partial tree must not be exposed as complete", file: file, line: line); return nil
        }
    }
    private func simple() -> (root: Node, container: Node, leaf: Node) {
        let leaf = Node(3, .menuItem, "PDF…")
        let container = Node(2, .container, "", [leaf])
        let root = Node(1, .menuBarItem, "File", [container])
        return (root, container, leaf)
    }
    func testCompleteTreePreservesEveryPathAndSkipsOnlyProvenExcludedSubtrees() throws {
        let unreadable = Node(99, .menuItem, "never read")
        unreadable.roleFault = .failure
        let apple = Node(0, .menuBarItem, "localized Apple", [unreadable])
        apple.roleFault = .failure
        let help = Node(10, .menuBarItem, "도움말", [unreadable])
        help.childrenFault = .failure
        let pdf = Node(3, .menuItem, "PDF…")
        let export = Node(2, .menuItem, "Export To", [Node(4, .container, "", [pdf])])
        let literal = Node(5, .menuItem, "Export To > PDF…")
        let separator = Node(6, .menuItem)
        let insideHelp = Node(7, .menuItem, "Help", [Node(8, .container, "", [Node(9, .menuItem, "Guide")])])
        let file = Node(1, .menuBarItem, "File", [Node(11, .container, "", [export, literal, separator, insideHelp])])
        let (outcome, calls) = run([.init(node: apple, isAppleMenu: true), .init(node: file), .init(node: help)])
        guard case .complete(let entries, let statistics) = outcome else { return XCTFail("Complete structural fixture rejected") }
        XCTAssertEqual(entries.map(\.path), [["File", "Export To", "PDF…"], ["File", "Export To > PDF…"], ["File", "Help", "Guide"]])
        XCTAssertEqual(entries.map { $0.node.id }, [3, 5, 9])
        XCTAssertFalse(calls.contains("role:0"))
        XCTAssertFalse(calls.contains("role:99"))
        XCTAssertFalse(calls.contains("children:10"))
        XCTAssertFalse(calls.contains("title:11"))
        XCTAssertEqual(statistics.rootReads, 1)
        XCTAssertEqual(statistics.roleReads, statistics.nodes)
        // Structural completion must preserve both literal/breadcrumb candidates,
        // leaving the existing global ambiguity policy to reject the collision.
        let choices = entries.map { CapturedMenu(appID: "fixture", appName: "Fixture", path: $0.path) }
        XCTAssertNil(MenuCapturePolicy.resolveHelp(title: "Export To > PDF…", choices: choices))
    }
    func testMandatoryReadFailuresCannotProducePartialCatalogs() {
        for fault in [Fault.unavailable, .failure] {
            let f = simple()
            for attribute in [Traversal.Attribute.roots, .role, .title, .children] {
                f.root.roleFault = .none; f.root.titleFault = .none; f.root.childrenFault = .none
                switch attribute {
                case .roots: break
                case .role: f.root.roleFault = fault
                case .title: f.root.titleFault = fault
                case .children: f.root.childrenFault = fault
                }
                let (outcome, _) = run([.init(node: f.root)], rootFault: attribute == .roots ? fault : .none)
                let expected: Traversal.Failure = fault == .unavailable ? .unavailable(attribute) : .readFailure(attribute)
                XCTAssertEqual(failure(outcome), expected)
            }
        }
        let f = simple()
        let missing = Node(4, .menuItem, "Unreadable")
        missing.childrenFault = .failure
        f.container.children.append(missing)
        let (afterValidEntry, _) = run([.init(node: f.root)])
        XCTAssertEqual(failure(afterValidEntry), .readFailure(.children), "An earlier valid command must not escape an incomplete result")
    }
    func testSuccessfulEmptySeparatorDiffersFromMissingTitleAndUnnamedBranch() {
        let f = simple()
        f.leaf.title = ""
        let (separator, _) = run([.init(node: f.root)])
        guard case .complete(let entries, _) = separator else { return XCTFail("Explicit childless separator rejected") }
        XCTAssertTrue(entries.isEmpty)
        f.leaf.titleFault = .unavailable
        XCTAssertEqual(failure(run([.init(node: f.root)]).0), .unavailable(.title))
        f.leaf.titleFault = .none
        f.leaf.children = [Node(4, .menuItem, "Child")]
        XCTAssertEqual(failure(run([.init(node: f.root)]).0), .unnamedBranch)
        f.root.title = ""
        XCTAssertEqual(failure(run([.init(node: f.root)]).0), .unnamedBranch)
    }
    func testKnownContainersNeedNoTitleButUnknownOrInvalidRootCannotBeIgnored() {
        let f = simple()
        f.container.titleFault = .failure
        guard case .complete = run([.init(node: f.root)]).0 else { return XCTFail("A structural container needs no title") }
        f.container.roleFault = .unavailable
        XCTAssertEqual(failure(run([.init(node: f.root)]).0), .unavailable(.role))
        f.root.role = .container
        XCTAssertEqual(failure(run([.init(node: f.root)]).0), .invalidRootRole)
    }
    func testCapsUseStructuralNodesAndDoNotExposeCandidatesFromTruncatedTrees() {
        let f = simple()
        guard case .complete(let entries, _) = run([.init(node: f.root)], limits: .init(nodes: 3, children: 1, depth: 3)).0 else {
            return XCTFail("Exact cap boundary should succeed")
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(failure(run([.init(node: f.root)], limits: .init(nodes: 2)).0), .nodeLimit)
        XCTAssertEqual(failure(run([.init(node: f.root)], limits: .init(depth: 2)).0), .depthLimit)
        XCTAssertEqual(failure(run([.init(node: f.root), .init(node: Node(9, .menuBarItem, "Other"))],
                                   limits: .init(children: 1)).0), .childLimit)
        f.container.children.append(Node(4, .menuItem, "Other"))
        XCTAssertEqual(failure(run([.init(node: f.root)], limits: .init(children: 1)).0), .childLimit)
    }
    func testDeadlineAndCancellationBeforeAndAfterEveryReaderStopFurtherReads() {
        let f = simple()
        let before = run([.init(node: f.root)], hasTime: { false })
        XCTAssertEqual(failure(before.0), .deadline)
        XCTAssertTrue(before.1.isEmpty)
        let cancelled = run([.init(node: f.root)], cancelled: { true })
        XCTAssertEqual(failure(cancelled.0), .cancelled)
        XCTAssertTrue(cancelled.1.isEmpty)
        for attribute in [Traversal.Attribute.roots, .role, .title, .children] {
            var timeRemains = true
            let result = run([.init(node: f.root)], hasTime: { timeRemains }, didRead: {
                if $0 == attribute { timeRemains = false }
            })
            XCTAssertEqual(failure(result.0), .deadline)
            var cancel = false
            let stopped = run([.init(node: f.root)], cancelled: { cancel }, didRead: {
                if $0 == attribute { cancel = true }
            })
            XCTAssertEqual(failure(stopped.0), .cancelled)
            XCTAssertEqual(result.1, stopped.1)
            let expectedLast: String
            switch attribute {
            case .roots: expectedLast = "roots"
            case .role: expectedLast = "role:1"
            case .title: expectedLast = "title:1"
            case .children: expectedLast = "children:1"
            }
            XCTAssertEqual(result.1.last, expectedLast)
        }
    }
    func testEmptyCompleteCatalogAndInvalidConfigurationAreDistinctFromFailure() {
        guard case .complete(let entries, let statistics) = run([]).0 else { return XCTFail("Empty roots can be complete") }
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(statistics.rootReads, 1)
        let f = simple()
        for limits in [Traversal.Limits(nodes: 0), .init(children: 0), .init(depth: 0)] {
            let (outcome, calls) = run([.init(node: f.root)], limits: limits)
            XCTAssertEqual(failure(outcome), .invalidLimits)
            XCTAssertTrue(calls.isEmpty)
        }
    }
    func testCyclesAreBoundedAndNeverReportedAsComplete() {
        let f = simple()
        f.container.children = [f.container]
        defer { f.container.children = [] }
        XCTAssertEqual(failure(run([.init(node: f.root)], limits: .init(nodes: 10, depth: 5)).0), .depthLimit)
    }

    func testObservedGroupsAndSevenProvenLeafControlsDoNotHideLaterMenuCandidate() {
        let controls = (5...11).map { Node($0, .controlLeaf, "TSV…") }
        let inner = Node(4, .structuralGroup, "not a menu path", controls)
        let group = Node(3, .structuralGroup, "not a menu path", [inner])
        let tsv = Node(12, .menuItem, "TSV…")
        let menu = Node(2, .container, "", [group, tsv])
        let root = Node(1, .menuBarItem, "File", [menu])
        // Faults ensure no title is used even when it matches the chosen command.
        for node in [group, inner] + controls { node.titleFault = .failure }
        let (outcome, calls) = run([.init(node: root)])
        guard case .complete(let entries, let stats) = outcome else { return XCTFail("Observed complete shape rejected") }
        XCTAssertEqual(entries.map(\.path), [["File", "TSV…"]])
        XCTAssertEqual(entries.map { $0.node.id }, [12])
        XCTAssertEqual(stats.nodes, 12)
        XCTAssertEqual(stats.maximumDepth, 4)
        XCTAssertEqual(stats.roleReads, 12)
        XCTAssertEqual(stats.childrenReads, 12)
        XCTAssertEqual(stats.titleReads, 2)
        var expected = ["roots", "role:1", "title:1", "children:1", "role:2", "children:2",
                        "role:3", "children:3", "role:4", "children:4"]
        for id in 5...11 { expected += ["role:\(id)", "children:\(id)"] }
        expected += ["role:12", "title:12", "children:12"]
        XCTAssertEqual(calls, expected, "One pass must read each structural node, without control titles or an early candidate return")
        let choices = entries.map { CapturedMenu(appID: "fixture", appName: "Fixture", path: $0.path) }
        XCTAssertEqual(MenuCapturePolicy.resolveHelp(title: "TSV…", choices: choices)?.identity.path, ["File", "TSV…"])
    }

    func testMenuItemsInsideGroupsKeepGlobalIdentityAndLiteralAmbiguity() {
        let nested = Node(6, .menuItem, "PDF…")
        let export = Node(4, .menuItem, "Export To", [Node(5, .container, "", [Node(7, .structuralGroup, "", [nested])])])
        let literal = Node(8, .menuItem, "Export To > PDF…")
        let group = Node(3, .structuralGroup, "ignored", [export, literal])
        let root = Node(1, .menuBarItem, "File", [Node(2, .container, "", [group])])
        let (outcome, calls) = run([.init(node: root)])
        guard case .complete(let entries, _) = outcome else { return XCTFail("Nested real menu items must be fully traversed") }
        XCTAssertEqual(entries.map(\.path), [["File", "Export To", "PDF…"], ["File", "Export To > PDF…"]])
        XCTAssertTrue(calls.contains("children:7"))
        var choices = entries.map { CapturedMenu(appID: "fixture", appName: "Fixture", path: $0.path) }
        XCTAssertNil(MenuCapturePolicy.resolveHelp(title: "Export To > PDF…", choices: choices),
                     "A literal-vs-breadcrumb collision must not disappear behind a structural group")
        let duplicate = Node(9, .menuItem, "PDF…")
        group.children = [nested, Node(10, .structuralGroup, "", [duplicate])]
        guard case .complete(let duplicates, _) = run([.init(node: root)]).0 else { return XCTFail("Duplicate paths must reach resolution") }
        XCTAssertEqual(duplicates.map(\.path), [["File", "PDF…"], ["File", "PDF…"]])
        choices = duplicates.map {
            CapturedMenu(appID: "fixture", appName: "Fixture", path: $0.path, axIdentifier: "id-\($0.node.id)")
        }
        XCTAssertNil(MenuCapturePolicy.resolveHelp(title: "PDF…", choices: choices),
                     "Every grouped member of one identity must survive for identifier conflict checks")
        group.children = [nested, Node(11, .menuItem, "Other", [Node(12, .container, "", [duplicate])])]
        guard case .complete(let twoIdentities, _) = run([.init(node: root)]).0 else { return XCTFail("All grouped identities must reach resolution") }
        choices = twoIdentities.map { CapturedMenu(appID: "fixture", appName: "Fixture", path: $0.path) }
        XCTAssertNil(MenuCapturePolicy.resolveHelp(title: "PDF…", choices: choices), "Two real menu identities remain ambiguous")
    }

    func testGroupsAndControlsRequireTheirExactProvenParentRole() {
        for role in [Traversal.Role.structuralGroup, .controlLeaf] {
            XCTAssertEqual(failure(run([.init(node: Node(1, role))]).0), .invalidRootRole)
        }
        for parentRole in [Traversal.Role.menuBarItem, .menuItem] {
            let invalidGroup = Node(3, .structuralGroup)
            let parent = Node(2, parentRole, "Parent", [invalidGroup])
            let root = parentRole == .menuBarItem ? parent : Node(1, .menuBarItem, "File", [parent])
            let (outcome, calls) = run([.init(node: root)])
            XCTAssertEqual(failure(outcome), .invalidGroupParent)
            XCTAssertEqual(calls.last, "role:3", "Invalid ancestry must reject before title or children queries")
        }
        for parentRole in [Traversal.Role.menuBarItem, .menuItem, .container] {
            let button = Node(3, .controlLeaf)
            let parent = Node(2, parentRole, "Parent", [button])
            let root = parentRole == .menuBarItem ? parent : Node(1, .menuBarItem, "File", [parent])
            let (outcome, calls) = run([.init(node: root)])
            XCTAssertEqual(failure(outcome), .invalidControlParent)
            XCTAssertEqual(calls.last, "role:3")
        }
        let hidden = Node(5, .menuItem, "Hidden")
        let button = Node(4, .controlLeaf, "", [hidden])
        let root = Node(1, .menuBarItem, "File", [Node(2, .container, "", [Node(3, .structuralGroup, "", [button])])])
        let (outcome, calls) = run([.init(node: root)])
        XCTAssertEqual(failure(outcome), .nonLeafControl)
        XCTAssertEqual(calls.last, "children:4")
        XCTAssertFalse(calls.contains("role:5"), "A childful button is an error, not a container or ignored subtree")
    }

    func testGroupOrControlReadFailureDiscardsEarlierValidCandidates() {
        for kind in [Traversal.Role.structuralGroup, .controlLeaf] {
            for fault in [Fault.unavailable, .failure] {
                let broken = Node(4, kind)
                broken.childrenFault = fault
                let group = kind == .controlLeaf ? Node(3, .structuralGroup, "", [broken]) : broken
                let root = Node(1, .menuBarItem, "File", [Node(2, .container, "", [Node(5, .menuItem, "Valid"), group])])
                let (outcome, calls) = run([.init(node: root)])
                XCTAssertEqual(failure(outcome), fault == .unavailable ? .unavailable(.children) : .readFailure(.children))
                XCTAssertTrue(calls.contains("title:5"), "An earlier valid candidate must not escape an incomplete final tree")
                XCTAssertEqual(calls.last, "children:4")
                broken.childrenFault = .none
                broken.roleFault = .failure
                XCTAssertEqual(failure(run([.init(node: root)]).0), .readFailure(.role))
            }
        }
    }

    func testAcceptedStructuralNodesShareExistingNodeDepthAndChildLimits() {
        let buttons = (5...11).map { Node($0, .controlLeaf) }
        let inner = Node(4, .structuralGroup, "", buttons)
        let root = Node(1, .menuBarItem, "File", [Node(2, .container, "", [Node(3, .structuralGroup, "", [inner]),
                                                                                  Node(12, .menuItem, "TSV…")])])
        guard case .complete = run([.init(node: root)], limits: .init(nodes: 12, children: 7, depth: 5)).0 else {
            return XCTFail("Exact structural budget boundary should succeed")
        }
        XCTAssertEqual(failure(run([.init(node: root)], limits: .init(nodes: 11)).0), .nodeLimit)
        XCTAssertEqual(failure(run([.init(node: root)], limits: .init(depth: 4)).0), .depthLimit)
        let (tooMany, calls) = run([.init(node: root)], limits: .init(children: 6))
        XCTAssertEqual(failure(tooMany), .childLimit)
        XCTAssertEqual(calls.last, "children:4")
        XCTAssertFalse(calls.contains("role:5"))
    }

    func testDeadlineOrCancellationDuringGroupAndControlChildrenDoesNotContinue() {
        let root = Node(1, .menuBarItem, "File", [Node(2, .container, "", [Node(3, .structuralGroup, "", [Node(4, .controlLeaf)]),
                                                                                  Node(5, .menuItem, "Later")])])
        for stopAt in [3, 4] {
            var childReads = 0, timeRemains = true
            let timed = run([.init(node: root)], hasTime: { timeRemains }, didRead: {
                if $0 == .children { childReads += 1; if childReads == stopAt { timeRemains = false } }
            })
            XCTAssertEqual(failure(timed.0), .deadline)
            XCTAssertEqual(timed.1.last, "children:\(stopAt)")
            XCTAssertFalse(timed.1.contains("role:5"))
            childReads = 0
            var cancel = false
            let cancelled = run([.init(node: root)], cancelled: { cancel }, didRead: {
                if $0 == .children { childReads += 1; if childReads == stopAt { cancel = true } }
            })
            XCTAssertEqual(failure(cancelled.0), .cancelled)
            XCTAssertEqual(cancelled.1, timed.1, "A successful provider crossing cancellation or time cannot supply accepted structure")
        }
    }
}
