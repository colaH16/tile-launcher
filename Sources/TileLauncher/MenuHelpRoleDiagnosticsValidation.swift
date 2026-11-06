#if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
import ApplicationServices
import CoreFoundation
import DeckCore
import Darwin
import Foundation

/// Injected providers exercise the production diagnostic helpers. No AX query,
/// application observation, window access, user text or actions are involved.
enum MenuHelpRoleDiagnosticsValidation {
    private enum RoleResult: Equatable { case value(MenuCatalogTraversal.Role), unavailable, failure }
    private final class Scenario {
        var graph: [Int: [Int]] = [:]
        var roles: [Int: CFTypeRef] = [:]
        var childResults: [Int: MenuHelpStructureProbe.Children<Int>] = [:]
        var calls: [String] = []
        var now: TimeInterval = 10
        var cancelled = false
        var afterCall: ((String, Scenario) -> Void)?

        func scan(targetRole: MenuHelpRoleRead.KnownRole = .group, siblings: [Int]? = nil, deadline: TimeInterval = 100,
                  limits: MenuHelpStructureProbe.Limits = .init()) -> MenuHelpStructureProbe.Report {
            MenuHelpStructureProbe.scan(target: 0, targetRole: targetRole, siblings: siblings,
                role: { node in
                    let call = "role:\(node)"
                    self.calls.append(call)
                    self.afterCall?(call, self)
                    return (.success, self.roles[node] ?? (kAXMenuItemRole as NSString))
                }, children: { node, limit in
                    let call = "children:\(node):\(limit)"
                    self.calls.append(call)
                    self.afterCall?(call, self)
                    if let result = self.childResults[node] { return result }
                    let children = self.graph[node] ?? []
                    return .nodes(Array(children.prefix(limit == 0 ? 0 : limit + 1)), reported: children.count)
                }, clock: { self.now }, deadline: deadline, isCancelled: { self.cancelled }, limits: limits)
        }
    }
    private struct ChildrenFixture {
        var limit = 100
        var count: CFIndex = 2
        var countError = AXError.success
        var canCopy = true
        var copyError = AXError.success
        var array: CFArray?
        var decodeFails = false
    }
    private enum ChildrenResult: Equatable {
        case nodes(Int, reported: Int), unavailable(Int), countError(Int), copyError(Int), invalid, stopped
    }
    private static func array(_ items: [AnyObject]) -> CFArray {
        var pointers: [UnsafeRawPointer?] = items.map { UnsafeRawPointer(Unmanaged.passUnretained($0).toOpaque()) }
        var callbacks = kCFTypeArrayCallBacks
        return pointers.withUnsafeMutableBufferPointer {
            CFArrayCreate(kCFAllocatorDefault, $0.baseAddress, $0.count, &callbacks)!
        }
    }
    private static func children(_ fixture: ChildrenFixture) -> (ChildrenResult, [String]) {
        var calls: [String] = []
        var index = 0
        let actual = MenuHelpStructureChildrenRead.read(limit: fixture.limit,
            count: { calls.append("count"); return (fixture.countError, fixture.count) },
            canCopy: { calls.append("canCopy"); return fixture.canCopy },
            copy: { calls.append("copy:\($0)"); return (fixture.copyError, fixture.array) },
            decode: { calls.append("decode"); return fixture.decodeFails ? nil : ($0 as? [AnyObject]) },
            isElement: {
                calls.append("element:\(index)"); index += 1
                return CFGetTypeID($0 as CFTypeRef) == AXUIElementGetTypeID()
            })
        let result: ChildrenResult
        switch actual {
        case .nodes(let nodes, let reported): result = .nodes(nodes.count, reported: reported)
        case .unavailable(let code): result = .unavailable(code)
        case .countError(let code): result = .countError(code)
        case .copyError(let code): result = .copyError(code)
        case .invalid: result = .invalid
        case .stopped: result = .stopped
        }
        return (result, calls)
    }

    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else {
                throw NSError(domain: "TileLauncher.MenuHelpRoleDiagnosticsValidation", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        func read(_ error: AXError, _ value: CFTypeRef?, expected: RoleResult,
                  trace: MenuHelpRoleRead.Trace? = nil) throws {
            var calls: [String] = []
            var traces: [MenuHelpRoleRead.Trace] = []
            let actual = MenuHelpRoleRead.read({ calls.append("copyRole"); return (error, value) }, report: {
                calls.append("report"); traces.append($0)
            })
            let result: RoleResult
            switch actual {
            case .value(let value): result = .value(value)
            case .unavailable: result = .unavailable
            case .failure: result = .failure
            }
            try check(result == expected, "Role diagnostics changed the original catalog outcome")
            try check(calls == (trace == nil ? ["copyRole"] : ["copyRole", "report"]),
                      "Role diagnostics must retain exactly one existing read, then at most one report")
            try check(traces == (trace.map { [$0] } ?? []), "Role trace exposed an unread value or changed its first failure")
        }

        try read(.success, kAXMenuBarItemRole as NSString, expected: .value(.menuBarItem))
        try read(.success, kAXMenuItemRole as NSString, expected: .value(.menuItem))
        try read(.success, kAXMenuRole as NSString, expected: .value(.container))
        try read(.cannotComplete, kAXGroupRole as NSString, expected: .failure,
                 trace: .init(failure: .axError, errorCode: Int(AXError.cannotComplete.rawValue)))
        for error in [AXError.attributeUnsupported, .noValue] {
            try read(error, kAXGroupRole as NSString, expected: .unavailable,
                     trace: .init(failure: .unavailable, errorCode: Int(error.rawValue)))
        }
        try read(.success, nil, expected: .failure, trace: .init(failure: .missingValue))
        try read(.success, NSNumber(value: 7), expected: .failure, trace: .init(failure: .nonString, valueType: .number))
        try read(.success, kCFBooleanTrue, expected: .failure, trace: .init(failure: .nonString, valueType: .boolean))
        try read(.success, NSArray(), expected: .failure, trace: .init(failure: .nonString, valueType: .array))
        try read(.success, kAXGroupRole as NSString, expected: .failure,
                 trace: .init(failure: .unsupportedKnownRole, role: .group))
        try read(.success, "private custom role fixture" as NSString, expected: .failure,
                 trace: .init(failure: .unlistedRole))

        let known = MenuHelpRoleRead.Trace(failure: .unsupportedKnownRole, role: .group)
        var probes = 0
        func attempt(_ gate: MenuHelpStructureProbeGate, trace: MenuHelpRoleRead.Trace? = known,
                     failure: MenuCatalogTraversal.Failure = .readFailure(.role), allowed: Bool = true) -> Int? {
            gate.run(expectedEpoch: gate.captureEpoch(), after: trace, catalogFailure: failure,
                     canStart: { allowed }, probe: { _ in probes += 1; return probes })
        }
        for logActive in [false, true] {
            for structureFlag in [false, true] {
                var args = ["TileLauncher"]
                if logActive { args.append("--menu-capture-log") }
                if structureFlag { args.append("--menu-capture-structure") }
                let parsed = MenuHelpStructureProbeGate.current(logActive: logActive, arguments: args, availability: { true })
                let gate = MenuHelpStructureProbeGate(logActive: parsed.logActive, structureRequested: parsed.structureRequested)
                try check((attempt(gate) != nil) == (logActive && structureFlag),
                          "Both a live opted-in logger and the separate structure flag are required")
            }
        }
        let gate = MenuHelpStructureProbeGate(logActive: true, structureRequested: true)
        let before = probes
        let rejectedTraces: [MenuHelpRoleRead.Trace?] = [nil, .init(failure: .axError, errorCode: -1),
            .init(failure: .unavailable), .init(failure: .missingValue), .init(failure: .nonString, valueType: .number),
            .init(failure: .unlistedRole), .init(failure: .unsupportedKnownRole, role: .window)]
        for trace in rejectedTraces {
            try check(attempt(gate, trace: trace) == nil, "Unsafe or unproven role must never trigger structure reads")
        }
        try check(attempt(gate, failure: .readFailure(.children)) == nil
                  && attempt(gate, failure: .deadline) == nil && attempt(gate, allowed: false) == nil,
                  "Only an actual role failure with current cancellation/deadline may start a probe")
        try check(probes == before, "Ineligible probes performed extra work")
        try check(attempt(gate) != nil && attempt(gate) == nil && probes == before + 1,
                  "Skipped admission must not consume the latch; admitted diagnostics run only once per gate")

        var available = false
        let live = MenuHelpStructureProbeGate(logActive: true, structureRequested: true, availability: { available })
        try check(attempt(live) == nil, "Inactive, expired, closed or full log must prevent all probe work")
        available = true
        let becameUnavailable = live.run(expectedEpoch: live.captureEpoch(), after: known,
                                         catalogFailure: .readFailure(.role)) { cancelled in
            let before = cancelled(); available = false
            return !before && cancelled()
        }
        try check(becameUnavailable == true, "Logger availability must be checked live during a running probe")
        let lifecycle = MenuHelpStructureProbeGate(logActive: true, structureRequested: true)
        let cancelledBySettings = lifecycle.run(expectedEpoch: lifecycle.captureEpoch(), after: known,
                                                catalogFailure: .readFailure(.role)) { cancelled in
            let before = cancelled(); lifecycle.cancelProbes()
            return !before && cancelled()
        }
        try check(cancelledBySettings == true, "Effective settings/target/stop invalidation must cancel the running probe")
        let epochLatch = MenuHelpStructureProbeLatch()
        let epochGate = MenuHelpStructureProbeGate(logActive: true, structureRequested: true, latch: epochLatch)
        let sealedEpoch = epochGate.captureEpoch()
        epochGate.cancelProbes()
        let oldEpoch = epochGate.run(expectedEpoch: sealedEpoch, after: known, catalogFailure: .readFailure(.role)) { _ in
            probes += 1; return true
        }
        try check(oldEpoch == nil && !epochLatch.isUsed,
                  "Settings cancellation after seal but before probe admission must reject without consuming the once latch")
        let admittingEpoch = epochGate.captureEpoch()
        let admissionRace = epochGate.run(expectedEpoch: admittingEpoch, after: known,
            catalogFailure: .readFailure(.role), canStart: { epochGate.cancelProbes(); return true }) { _ in
                probes += 1; return true
            }
        try check(admissionRace == nil && !epochLatch.isUsed,
                  "Cancellation during eligibility checks must not be adopted as a fresh epoch or consume admission")
        try check(attempt(epochGate) != nil && epochLatch.isUsed,
                  "A newly sealed request after cancellation can use the still-unconsumed process latch")

        // Read-free context must follow DFS sibling/root movement rather than
        // confusing the deepest earlier branch with the current failed node.
        var path = MenuHelpCatalogPath<Int>(equal: ==)
        path.didReadRoots([10, 20, 30])
        try check(path.locate(20)?.context == .init(parent: .menuBar, depth: 0, rootIndex: 1,
                                                   siblingIndex: 1, siblingCount: 3)
                  && path.locate(20)?.siblings == nil, "Other menu-bar roots must not become optional probe siblings")
        path.didReadChildren(of: 20, role: .menuBarItem, children: [21, 22])
        path.didReadChildren(of: 21, role: .container, children: [211])
        path.didReadChildren(of: 211, role: .menuItem, children: [2111])
        try check(path.locate(2111)?.context.depth == 3, "Known descendant context lost its actual depth")
        path.didReadChildren(of: 22, role: .container, children: [221, 222])
        try check(path.locate(222)?.context == .init(parent: .menu, depth: 2, rootIndex: 1,
                                                    siblingIndex: 1, siblingCount: 2)
                  && path.locate(222)?.siblings == [221] && path.locate(2111) == nil,
                  "A DFS sibling move must discard stale deeper context and exclude the failed node from siblings")
        path.didReadChildren(of: 30, role: .menuBarItem, children: [31])
        try check(path.locate(31)?.context.rootIndex == 2 && path.locate(31)?.context.depth == 1
                  && path.locate(222) == nil, "A new root must discard old-root path context")
        try check(path.locate(999) == nil, "Unproven context must remain unknown without an extra parent query")

        let tree = Scenario()
        tree.graph = [0: [1, 2], 1: [3]]
        tree.roles[1] = kAXMenuRole as NSString
        let complete = tree.scan()
        try check(complete.status == .complete && complete.nodes.map(\.parent) == [nil, 0, 0, 1],
                  "Complete subtree must retain observed parent relationships")
        try check(tree.calls == ["children:0:63", "role:1", "role:2", "children:1:61", "role:3",
                                 "children:2:60", "children:3:60"],
                  "Probe must not re-read the failed role or query titles, parents, values or other roots")
        try check(complete.descendantMenu == .present && complete.descendantMenuItem == .present
                  && complete.siblingMenu == .unknown, "Only read structure may establish presence")
        let empty = Scenario().scan()
        try check(empty.status == .complete && empty.descendantMenu == .absent
                  && empty.descendantMenuItem == .absent, "Observed empty subtree may establish absence")

        let unreadableChildren: [MenuHelpStructureProbe.Children<Int>] = [
            .unavailable(code: Int(AXError.noValue.rawValue)), .countError(code: -1), .copyError(code: -2), .invalid]
        for result in unreadableChildren {
            let scenario = Scenario()
            scenario.childResults[0] = result
            let report = scenario.scan()
            try check(report.status == .truncated && report.descendantMenu == .unknown
                      && report.descendantMenuItem == .unknown && scenario.calls == ["children:0:63"],
                      "Unreadable children cannot establish a complete empty subtree")
        }
        let unsupportedBranch = Scenario()
        unsupportedBranch.childResults[0] = .unavailable(code: Int(AXError.attributeUnsupported.rawValue))
        let unavailableBranch = unsupportedBranch.scan()
        try check(unavailableBranch.status == .truncated && unavailableBranch.nodes[0].childCount == nil,
                  "Unsupported group children do not prove a leaf or zero count")
        let unsupportedItem = Scenario()
        unsupportedItem.childResults[0] = .unavailable(code: Int(AXError.attributeUnsupported.rawValue))
        let provenLeaf = unsupportedItem.scan(targetRole: .menuItem)
        try check(provenLeaf.status == .complete && provenLeaf.nodes[0].childCount == 0,
                  "Only explicit unsupported children on a known menu item establish a compatible leaf")
        for (value, issue) in [("private custom role fixture", MenuHelpStructureProbe.Issue.Kind.unlistedRole),
                               (kAXWindowRole, .boundary)] {
            let scenario = Scenario(); scenario.graph = [0: [1], 1: [2]]
            scenario.roles[1] = value as NSString
            let report = scenario.scan()
            try check(report.status == .truncated && report.nodes[1].issue?.kind == issue
                      && scenario.calls == ["children:0:63", "role:1"] && report.descendantMenu == .unknown,
                      "Unknown/custom and boundary roles must never be expanded")
        }
        let inconsistent = Scenario()
        inconsistent.childResults[0] = .nodes([], reported: 1)
        try check(inconsistent.scan().nodes[0].issue?.kind == .childrenInvalid,
                  "Count and returned references must agree before an empty subtree can be inferred")
        for limits in [MenuHelpStructureProbe.Limits(nodes: 0), .init(children: 0), .init(depth: -1),
                       .init(seconds: .nan), .init(seconds: 0)] {
            let invalid = Scenario()
            try check(invalid.scan(limits: limits).status == .truncated && invalid.calls.isEmpty,
                      "Invalid diagnostic limits must fail closed with zero provider calls")
        }

        let cap = Scenario()
        cap.graph[0] = Array(1...101)
        let capped = cap.scan(limits: .init(nodes: 200, children: 100, depth: 4, seconds: 1))
        try check(cap.calls.first == "children:0:100" && capped.nodes.count == 101
                  && capped.nodes[0].issue?.kind == .childLimit && capped.status == .truncated,
                  "Child-count retrieval must respect the copy cap and preserve truncation, not claim completeness")
        let depth = Scenario()
        depth.graph = [0: [1], 1: [2], 2: [3], 3: [4], 4: [5]]
        let deep = depth.scan()
        try check(deep.nodes.count == 5 && deep.nodes.last?.depth == 4
                  && deep.nodes.last?.issue?.kind == .depthLimit && depth.calls.last == "children:4:0"
                  && !depth.calls.contains("role:5"), "Depth-four boundary must count only, never copy or visit deeper nodes")

        let priority = Scenario()
        priority.graph[0] = [1]
        let peers = Array(100...199)
        let priorityReport = priority.scan(siblings: peers)
        try check(priorityReport.descendantMenuItem == .present && priority.calls.first == "children:0:63"
                  && priority.calls.firstIndex(of: "role:1")! < priority.calls.firstIndex(of: "role:100")!
                  && priorityReport.nodes.count + (priorityReport.siblings?.count ?? 0) <= 64,
                  "Optional siblings must not consume the shared budget before the failed subtree")
        try check(priorityReport.subtreeStatus == .complete && priorityReport.siblingStatus == .truncated
                  && priorityReport.descendantMenu == .absent && priorityReport.siblingMenu == .unknown,
                  "Truncated optional siblings must not erase a complete subtree, or claim absent sibling menus")

        for onRole in [false, true] {
            let cancel = Scenario()
            cancel.graph[0] = [1]
            cancel.afterCall = { call, state in
                if call == (onRole ? "role:1" : "children:0:63") { state.cancelled = true }
            }
            let cancelled = cancel.scan()
            try check(cancelled.status == .cancelled
                      && cancel.calls == (onRole ? ["children:0:63", "role:1"] : ["children:0:63"]),
                      "Cancellation during a successful provider call must stop before the next call")
        }
        let preCancelled = Scenario(); preCancelled.cancelled = true
        try check(preCancelled.scan().status == .cancelled && preCancelled.calls.isEmpty,
                  "Already cancelled work must issue zero providers")
        let noTime = Scenario()
        try check(noTime.scan(deadline: 10).status == .deadline && noTime.calls.isEmpty,
                  "Original request deadline wins before the separate one-second probe budget")
        let crossing = Scenario()
        crossing.graph[0] = [1]
        crossing.afterCall = { _, state in state.now = 10.5 }
        try check(crossing.scan(deadline: 10.5).status == .deadline && crossing.calls == ["children:0:63"],
                  "A call crossing the original deadline must not trigger role reads")
        let separate = Scenario()
        separate.afterCall = { _, state in state.now = 11 }
        try check(separate.scan(deadline: 100).status == .deadline && separate.calls == ["children:0:63"],
                  "Separate one-second diagnostic deadline must remain bounded inside a longer request")

        // The actual native count/copy adapter, not a duplicate fixture reader.
        // Creating an opaque own-PID handle sends no AX messages.
        let handle = AXUIElementCreateApplication(getpid())
        let two = array([handle, handle])
        func childrenCheck(_ fixture: ChildrenFixture, _ expected: ChildrenResult, _ calls: [String]) throws {
            let actual = children(fixture)
            try check(actual.0 == expected && actual.1 == calls,
                      "Structure child adapter changed its result, queried an unreached stage, or exceeded its count/copy budget")
        }
        try childrenCheck(.init(array: two), .nodes(2, reported: 2),
                          ["count", "canCopy", "copy:2", "decode", "element:0", "element:1"])
        try childrenCheck(.init(limit: 0, count: 500, array: nil), .nodes(0, reported: 500), ["count"])
        try childrenCheck(.init(count: 0, array: two), .nodes(0, reported: 0), ["count"])
        try childrenCheck(.init(count: -1, array: two), .invalid, ["count"])
        try childrenCheck(.init(countError: .cannotComplete, array: two),
                          .countError(Int(AXError.cannotComplete.rawValue)), ["count"])
        try childrenCheck(.init(countError: .noValue, array: two),
                          .unavailable(Int(AXError.noValue.rawValue)), ["count"])
        try childrenCheck(.init(canCopy: false, array: two), .stopped, ["count", "canCopy"])
        try childrenCheck(.init(copyError: .cannotComplete, array: two),
                          .copyError(Int(AXError.cannotComplete.rawValue)), ["count", "canCopy", "copy:2"])
        try childrenCheck(.init(array: nil), .invalid, ["count", "canCopy", "copy:2"])
        try childrenCheck(.init(array: two, decodeFails: true), .invalid, ["count", "canCopy", "copy:2", "decode"])
        try childrenCheck(.init(array: array([handle])), .invalid, ["count", "canCopy", "copy:2", "decode"])
        try childrenCheck(.init(count: 3, array: array([handle, NSString(string: "private child fixture"), handle])),
                          .invalid, ["count", "canCopy", "copy:3", "decode", "element:0", "element:1"])
        try childrenCheck(.init(limit: 2, count: 500, array: array([handle, handle, handle])), .nodes(3, reported: 500),
                          ["count", "canCopy", "copy:3", "decode", "element:0", "element:1", "element:2"])

        print("Menu Help role diagnostics: original single-read outcomes, typed failures, opt-in/once admission and bounded injected structure traversal verified without AX queries.")
    }
}
#endif
