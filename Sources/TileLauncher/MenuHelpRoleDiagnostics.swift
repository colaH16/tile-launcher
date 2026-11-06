#if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
import ApplicationServices
import CoreFoundation
import DeckCore
import Foundation

/// R374 (A): the deferred Help catalog's AXRole read with a typed trace of a
/// non-accepted result. The decisions are those of the shared production
/// mapping `MenuHelpCatalogRoleRead` (AXMenuBarItem/AXMenuItem/AXMenu/AXGroup/
/// AXButton accepted; any other success fails closed; attributeUnsupported/
/// noValue is unavailable; any other error fails). Only AX error codes, CF type categories and SDK-listed role
/// categories leave this type — never raw strings or CF descriptions.
enum MenuHelpRoleRead {
    enum Failure: String, Encodable, Equatable {
        /// AXUIElementCopyAttributeValue returned an error other than below.
        case axError
        /// attributeUnsupported or noValue (the catalog's `.unavailable`).
        case unavailable
        /// Success without a value.
        case missingValue
        /// Success with a value that is not a string (see `valueType`).
        case nonString
        /// A string role listed in the SDK role constants, other than the three menu roles.
        case unsupportedKnownRole
        /// A string role not in the SDK list (custom); never recorded verbatim.
        case unlistedRole
    }
    enum ValueType: String, Encodable, Equatable { case number, boolean, array, element, axValue, other }
    /// AXRoleConstants.h roles. Raw strings are used only for matching.
    enum KnownRole: String, Encodable, Equatable, CaseIterable {
        case application = "AXApplication", systemWide = "AXSystemWide", window = "AXWindow", sheet = "AXSheet"
        case drawer = "AXDrawer", growArea = "AXGrowArea", image = "AXImage", unknown = "AXUnknown"
        case button = "AXButton", radioButton = "AXRadioButton", checkBox = "AXCheckBox"
        case popUpButton = "AXPopUpButton", menuButton = "AXMenuButton", tabGroup = "AXTabGroup"
        case table = "AXTable", column = "AXColumn", row = "AXRow", outline = "AXOutline", browser = "AXBrowser"
        case scrollArea = "AXScrollArea", scrollBar = "AXScrollBar", radioGroup = "AXRadioGroup", list = "AXList"
        case group = "AXGroup", valueIndicator = "AXValueIndicator", comboBox = "AXComboBox", slider = "AXSlider"
        case incrementor = "AXIncrementor", busyIndicator = "AXBusyIndicator"
        case progressIndicator = "AXProgressIndicator", relevanceIndicator = "AXRelevanceIndicator"
        case toolbar = "AXToolbar", disclosureTriangle = "AXDisclosureTriangle", textField = "AXTextField"
        case textArea = "AXTextArea", staticText = "AXStaticText", heading = "AXHeading", menuBar = "AXMenuBar"
        case menuBarItem = "AXMenuBarItem", menu = "AXMenu", menuItem = "AXMenuItem", splitGroup = "AXSplitGroup"
        case splitter = "AXSplitter", colorWell = "AXColorWell", timeField = "AXTimeField", dateField = "AXDateField"
        case helpTag = "AXHelpTag", matte = "AXMatte", dockItem = "AXDockItem", ruler = "AXRuler"
        case rulerMarker = "AXRulerMarker", grid = "AXGrid", levelIndicator = "AXLevelIndicator", cell = "AXCell"
        case layoutArea = "AXLayoutArea", layoutItem = "AXLayoutItem", handle = "AXHandle", popover = "AXPopover"

        /// The encoded category is the case name, not the AX string.
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(String(describing: self))
        }
        /// Window/document/app roots and another menu bar: never probed or expanded.
        var isBoundary: Bool {
            [.application, .systemWide, .window, .sheet, .drawer, .popover, .menuBar].contains(self)
        }
    }
    struct Trace: Equatable {
        var failure: Failure
        var errorCode: Int? = nil
        var valueType: ValueType? = nil
        var role: KnownRole? = nil
    }
    /// Where the failed node sat, from references the catalog already read.
    struct Context: Encodable, Equatable {
        enum Parent: String, Encodable, Equatable { case menuBar, menuBarItem, menuItem, menu, group, control, unknown }
        var parent: Parent
        /// Catalog depth of the failed node (menu bar children are 0); nil if unknown.
        var depth: Int?
        /// Index among the menu bar's children (0 is the Apple menu); nil if unknown.
        var rootIndex: Int?
        var siblingIndex: Int?
        var siblingCount: Int?
        static let unknown = Context(parent: .unknown, depth: nil, rootIndex: nil, siblingIndex: nil, siblingCount: nil)
    }

    enum Classified: Equatable {
        case accepted(MenuCatalogTraversal.Role)
        case rejected(Trace)
    }
    /// Classification of one AXRole result, layered on the shared production
    /// mapping (`MenuHelpCatalogRoleRead`): accepted roles and the decision are
    /// identical to the flag-off build; only the typed reason is added.
    static func classify(error: AXError, value: CFTypeRef?) -> Classified {
        switch MenuHelpCatalogRoleRead.classify(error: error, value: value) {
        case .accepted(let role): return .accepted(role)
        case .unavailable(let code): return .rejected(Trace(failure: .unavailable, errorCode: Int(code.rawValue)))
        case .error(let code): return .rejected(Trace(failure: .axError, errorCode: Int(code.rawValue)))
        case .missingValue: return .rejected(Trace(failure: .missingValue))
        case .nonString: return .rejected(Trace(failure: .nonString, valueType: value.map { valueType($0) }))
        case .unsupported(let raw):
            guard let known = KnownRole(rawValue: raw) else { return .rejected(Trace(failure: .unlistedRole)) }
            return .rejected(Trace(failure: .unsupportedKnownRole, role: known))
        }
    }
    /// The production role read: one `copy` call, the shared flag-off decision,
    /// and `report` at most once for a rejected result.
    static func read(_ copy: () -> (AXError, CFTypeRef?),
                     report: (Trace) -> Void) -> MenuCatalogTraversal.Read<MenuCatalogTraversal.Role> {
        let (error, value) = copy()
        let result = MenuHelpCatalogRoleRead.classify(error: error, value: value)
        if case .rejected(let trace) = classify(error: error, value: value) { report(trace) }
        return MenuHelpCatalogRoleRead.outcome(result)
    }
    static func valueType(_ value: CFTypeRef) -> ValueType {
        switch CFGetTypeID(value) {
        case CFNumberGetTypeID(): return .number
        case CFBooleanGetTypeID(): return .boolean
        case CFArrayGetTypeID(): return .array
        case AXUIElementGetTypeID(): return .element
        case AXValueGetTypeID(): return .axValue
        default: return .other
        }
    }
}

/// R374: read-free parent/depth/root context. The catalog reports the children
/// lists it actually read; this keeps the DFS path of those lists so a failed
/// node is located among references already returned — no AXParent or other query.
struct MenuHelpCatalogPath<Node> {
    struct Location {
        let context: MenuHelpRoleRead.Context
        /// Other children of the same parent; nil at the menu bar level (other
        /// roots are never probed).
        let siblings: [Node]?
    }
    private struct Entry {
        let role: MenuCatalogTraversal.Role?
        let children: [Node]
        let depth: Int?
        let rootIndex: Int?
    }
    private let equal: (Node, Node) -> Bool
    private var roots: [Node]?
    private var entries: [Entry] = []

    init(equal: @escaping (Node, Node) -> Bool) { self.equal = equal }

    mutating func didReadRoots(_ nodes: [Node]) {
        roots = nodes
        entries.removeAll()
    }
    /// After a successful children read of `node` (whose role was just read).
    mutating func didReadChildren(of node: Node, role: MenuCatalogTraversal.Role?, children: [Node]) {
        let found = find(node)
        if let level = found?.level { entries.removeSubrange((level + 1)...) } else { entries.removeAll() }
        entries.append(Entry(role: role, children: children, depth: found?.location.context.depth,
                             rootIndex: found?.location.context.rootIndex))
    }
    func locate(_ node: Node) -> Location? { find(node)?.location }

    private func find(_ node: Node) -> (location: Location, level: Int?)? {
        for level in entries.indices.reversed() {
            let entry = entries[level]
            guard let index = entry.children.firstIndex(where: { equal($0, node) }) else { continue }
            let parent: MenuHelpRoleRead.Context.Parent
            switch entry.role {
            case .menuBarItem: parent = .menuBarItem
            case .menuItem: parent = .menuItem
            case .container: parent = .menu
            case .structuralGroup: parent = .group
            case .controlLeaf: parent = .control
            case nil: parent = .unknown
            }
            let siblings = entry.children.enumerated().filter { $0.offset != index }.map(\.element)
            return (Location(context: .init(parent: parent, depth: entry.depth.map { $0 + 1 }, rootIndex: entry.rootIndex,
                                            siblingIndex: index, siblingCount: entry.children.count),
                             siblings: siblings), level)
        }
        if let roots, let index = roots.firstIndex(where: { equal($0, node) }) {
            return (Location(context: .init(parent: .menuBar, depth: 0, rootIndex: index,
                                            siblingIndex: index, siblingCount: roots.count),
                             siblings: nil), nil)
        }
        return nil
    }
}

/// R374 (B): bounded, metadata-only structure of the failed node's subtree,
/// then its already-read siblings. Roles and children edges only — no title,
/// value, description, identifier, position or action. Generic over an opaque
/// node so the loop is testable with injected providers.
enum MenuHelpStructureProbe {
    struct Limits: Equatable {
        /// Shared by the subtree (first) and siblings (after it).
        var nodes = 64
        var children = 100
        /// Nodes at this relative depth are recorded but not expanded (count only).
        var depth = 4
        var seconds: TimeInterval = 1
        var isValid: Bool { nodes > 0 && children > 0 && depth >= 0 && seconds.isFinite && seconds > 0 }
    }
    /// A children read. `limit` 0 means count only (no copy).
    enum Children<Node> {
        case nodes([Node], reported: Int)
        case unavailable(code: Int)
        case countError(code: Int)
        case copyError(code: Int)
        /// Negative count, missing/undecodable array, count mismatch or a non-element item.
        case invalid
        /// Cancellation or the deadline between the count and the copy.
        case stopped
    }
    enum Status: String, Encodable, Equatable { case complete, truncated, cancelled, deadline }
    enum Presence: String, Encodable, Equatable { case present, absent, unknown }
    struct Issue: Encodable, Equatable {
        enum Kind: String, Encodable, Equatable {
            case roleError, roleUnavailable, roleMissing, roleNonString, unlistedRole
            case childrenUnavailable, childrenCountError, childrenCopyError, childrenInvalid
            case childLimit, nodeLimit, depthLimit, boundary, notRead
        }
        var kind: Kind
        var code: Int? = nil
    }
    struct Node: Encodable, Equatable {
        /// nil when unreadable or unlisted (see `unlisted`).
        var role: MenuHelpRoleRead.KnownRole?
        var unlisted: Bool? = nil
        /// Index of the parent in `nodes`; nil for the failed node and siblings.
        var parent: Int?
        /// Relative to the failed node (0).
        var depth: Int
        /// nil unless a count was read and accepted (0 also for a proven menu-item leaf).
        var childCount: Int? = nil
        var issue: Issue? = nil
    }
    struct Report: Encodable, Equatable {
        /// complete only if the subtree and (when present) the siblings are complete.
        var status: Status
        var subtreeStatus: Status
        /// nil when sibling references were not available.
        var siblingStatus: Status?
        /// [0] is the failed node itself (role from the failed read, not re-read).
        var nodes: [Node]
        var siblings: [Node]?
        var siblingMenu: Presence
        var descendantMenuItem: Presence
        var descendantMenu: Presence
        var durationMilliseconds: Int
    }

    /// Checks cancellation and the absolute end (min(deadline, start + limits.seconds))
    /// before and after every provider call. One IPC can still overrun its timeout.
    /// Only listed, non-boundary roles are expanded.
    static func scan<N>(target: N, targetRole: MenuHelpRoleRead.KnownRole, siblings: [N]?,
                        role: (N) -> (AXError, CFTypeRef?),
                        children: (N, Int) -> Children<N>,
                        clock: () -> TimeInterval, deadline: TimeInterval,
                        isCancelled: () -> Bool, limits: Limits = .init()) -> Report {
        let started = clock()
        guard limits.isValid else {
            return Report(status: .truncated, subtreeStatus: .truncated, siblingStatus: siblings == nil ? nil : .truncated,
                          nodes: [Node(role: targetRole, parent: nil, depth: 0, issue: .init(kind: .notRead))],
                          siblings: siblings == nil ? nil : [], siblingMenu: .unknown,
                          descendantMenuItem: .unknown, descendantMenu: .unknown, durationMilliseconds: 0)
        }
        let end = min(deadline, started + limits.seconds)
        var stop: Status?
        func proceed() -> Bool {
            if stop != nil { return false }
            if isCancelled() { stop = .cancelled; return false }
            if clock() >= end { stop = .deadline; return false }
            return true
        }
        func roleNode(_ error: AXError, _ value: CFTypeRef?, parent: Int?, depth: Int) -> Node {
            switch MenuHelpRoleRead.classify(error: error, value: value) {
            case .accepted(let accepted):
                let known: MenuHelpRoleRead.KnownRole
                switch accepted {
                case .menuBarItem: known = .menuBarItem
                case .menuItem: known = .menuItem
                case .container: known = .menu
                case .structuralGroup: known = .group
                case .controlLeaf: known = .button
                }
                return Node(role: known, parent: parent, depth: depth)
            case .rejected(let trace):
                switch trace.failure {
                case .unsupportedKnownRole: return Node(role: trace.role, parent: parent, depth: depth)
                case .unlistedRole: return Node(role: nil, unlisted: true, parent: parent, depth: depth)
                case .unavailable: return Node(role: nil, parent: parent, depth: depth, issue: .init(kind: .roleUnavailable, code: trace.errorCode))
                case .axError: return Node(role: nil, parent: parent, depth: depth, issue: .init(kind: .roleError, code: trace.errorCode))
                case .missingValue: return Node(role: nil, parent: parent, depth: depth, issue: .init(kind: .roleMissing))
                case .nonString: return Node(role: nil, parent: parent, depth: depth, issue: .init(kind: .roleNonString))
                }
            }
        }

        // 1. The failed node's subtree, breadth first.
        var nodes = [Node(role: targetRole, parent: nil, depth: 0)]
        var refs = [target]
        var explored = true
        var index = 0
        while index < nodes.count {
            guard proceed() else { explored = false; break }
            let node = nodes[index]
            guard let known = node.role else {
                // Unreadable or unlisted (custom) roles are never expanded.
                if node.unlisted == true { nodes[index].issue = .init(kind: .unlistedRole) }
                explored = false; index += 1; continue
            }
            if known.isBoundary {
                nodes[index].issue = .init(kind: .boundary); explored = false; index += 1; continue
            }
            let remaining = limits.nodes - nodes.count
            let limit = node.depth >= limits.depth ? 0 : max(0, min(limits.children, remaining))
            let result = children(refs[index], limit)
            guard proceed() else { explored = false; nodes[index].issue = nodes[index].issue ?? .init(kind: .notRead); break }
            switch result {
            case .stopped:
                nodes[index].issue = .init(kind: .notRead); explored = false
            case .unavailable(let code):
                let error = Int32(exactly: code).flatMap(AXError.init(rawValue:)) ?? .failure
                if MenuHelpChildrenPolicy.isUnsupportedLeaf(error, menuItem: known == .menuItem) {
                    nodes[index].childCount = 0
                } else {
                    nodes[index].issue = .init(kind: .childrenUnavailable, code: code); explored = false
                }
            case .countError(let code): nodes[index].issue = .init(kind: .childrenCountError, code: code); explored = false
            case .copyError(let code): nodes[index].issue = .init(kind: .childrenCopyError, code: code); explored = false
            case .invalid: nodes[index].issue = .init(kind: .childrenInvalid); explored = false
            case .nodes(let kids, let reported):
                // The provider contract: count only for limit 0, otherwise exactly
                // min(reported, limit + 1). Anything else is inconsistent data.
                let expected = limit == 0 ? 0 : min(reported, limit + 1)
                guard reported >= 0, kids.count == expected else {
                    nodes[index].issue = .init(kind: .childrenInvalid); explored = false; break
                }
                nodes[index].childCount = reported
                guard reported > 0 else { break }
                if limit == 0 {
                    let kind: Issue.Kind = node.depth >= limits.depth ? .depthLimit : .nodeLimit
                    nodes[index].issue = .init(kind: kind); explored = false; break
                }
                if reported > limit {
                    nodes[index].issue = .init(kind: limit < limits.children ? .nodeLimit : .childLimit); explored = false
                }
                for kid in kids.prefix(limit) {
                    guard proceed() else { explored = false; break }
                    let (error, value) = role(kid)
                    nodes.append(roleNode(error, value, parent: index, depth: node.depth + 1))
                    refs.append(kid)
                    guard proceed() else { explored = false; break }
                }
            }
            if stop != nil { explored = false; break }
            index += 1
        }
        let subtreeStatus: Status = stop ?? (explored ? .complete : .truncated)

        // 2. Siblings, with what the subtree left of the same budget.
        var siblingNodes: [Node]?
        var siblingStatus: Status?
        if let siblings {
            var list: [Node] = []
            var complete = true
            for sibling in siblings {
                guard nodes.count + list.count < limits.nodes else { complete = false; break }
                guard proceed() else { complete = false; break }
                let (error, value) = role(sibling)
                let node = roleNode(error, value, parent: nil, depth: 0)
                list.append(node)
                // An unreadable role could be a menu; an unlisted string cannot.
                if node.role == nil && node.unlisted != true { complete = false }
                guard proceed() else { complete = false; break }
            }
            siblingNodes = list
            siblingStatus = stop ?? (complete ? .complete : .truncated)
        }

        func presence(_ role: MenuHelpRoleRead.KnownRole, in list: ArraySlice<Node>, complete: Bool) -> Presence {
            if list.contains(where: { $0.role == role }) { return .present }
            return complete ? .absent : .unknown
        }
        let descendants = nodes.dropFirst()
        let overall: Status = stop
            ?? (subtreeStatus == .complete && (siblingStatus == nil || siblingStatus == .complete) ? .complete : .truncated)
        return Report(status: overall, subtreeStatus: subtreeStatus, siblingStatus: siblingStatus,
                      nodes: nodes, siblings: siblingNodes,
                      siblingMenu: siblingNodes.map { presence(.menu, in: $0[...], complete: siblingStatus == .complete) } ?? .unknown,
                      descendantMenuItem: presence(.menuItem, in: descendants, complete: subtreeStatus == .complete),
                      descendantMenu: presence(.menu, in: descendants, complete: subtreeStatus == .complete),
                      durationMilliseconds: MenuCaptureDiagnostics.milliseconds(clock() - started))
    }
}

/// R374 (B): the probe's AXChildren read — count, then at most
/// min(count, limit + 1) items; `limit` 0 (or less) is count only. The native
/// adapter supplies the two AX calls (with its 25 ms timeout); `canCopy`
/// re-checks cancellation/deadline between them.
enum MenuHelpStructureChildrenRead {
    static func read(limit: Int,
                     count: () -> (AXError, CFIndex),
                     canCopy: () -> Bool,
                     copy: (CFIndex) -> (AXError, CFArray?),
                     decode: (CFArray) -> [AnyObject]? = { $0 as? [AnyObject] },
                     isElement: (AnyObject) -> Bool = { CFGetTypeID($0 as CFTypeRef) == AXUIElementGetTypeID() })
        -> MenuHelpStructureProbe.Children<AXUIElement> {
        let (result, reported) = count()
        if result == .attributeUnsupported || result == .noValue { return .unavailable(code: Int(result.rawValue)) }
        guard result == .success else { return .countError(code: Int(result.rawValue)) }
        guard reported >= 0 else { return .invalid }
        if reported == 0 || limit <= 0 { return .nodes([], reported: Int(reported)) }
        guard canCopy() else { return .stopped }
        // limit < reported here implies limit + 1 <= reported: no overflow, no oversize request.
        let requested: CFIndex = CFIndex(limit) >= reported ? reported : CFIndex(limit) + 1
        let (copied, values) = copy(requested)
        guard copied == .success else { return .copyError(code: Int(copied.rawValue)) }
        guard let values, let items = decode(values), items.count == requested else { return .invalid }
        var kids: [AXUIElement] = []
        kids.reserveCapacity(items.count)
        for item in items {
            // Never cast an item the predicate rejected.
            guard isElement(item) else { return .invalid }
            kids.append(item as! AXUIElement)
        }
        return .nodes(kids, reported: Int(reported))
    }
}

/// Once per process for production; tests can inject a separate latch.
final class MenuHelpStructureProbeLatch {
    static let process = MenuHelpStructureProbeLatch()
    private let lock = NSLock()
    private var used = false
    init() {}
    var isUsed: Bool { lock.lock(); defer { lock.unlock() }; return used }
    /// True exactly once.
    func consume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !used else { return false }
        used = true
        return true
    }
}

/// Runtime gate for (B): compile flag (this file), `--menu-capture-log` (an
/// active logger that can still accept records) and `--menu-capture-structure`,
/// the first SDK-listed unsupported, non-boundary role behind an actual catalog
/// role failure, and once per process. `probe` is never called otherwise.
/// `cancelProbes()` (target/settings change, stop, suppression) stops a running
/// probe without touching capture policy.
final class MenuHelpStructureProbeGate {
    let logActive: Bool
    let structureRequested: Bool
    private let availability: () -> Bool
    private let latch: MenuHelpStructureProbeLatch
    private let lock = NSLock()
    private var epoch: UInt64 = 0

    init(logActive: Bool, structureRequested: Bool, availability: @escaping () -> Bool = { true },
         latch: MenuHelpStructureProbeLatch = MenuHelpStructureProbeLatch()) {
        self.logActive = logActive
        self.structureRequested = structureRequested
        self.availability = availability
        self.latch = latch
    }
    /// Production: the process-wide latch.
    static func current(logActive: Bool, arguments: [String] = CommandLine.arguments,
                        availability: @escaping () -> Bool) -> MenuHelpStructureProbeGate {
        MenuHelpStructureProbeGate(logActive: logActive,
                                   structureRequested: logActive && arguments.contains("--menu-capture-structure"),
                                   availability: availability, latch: .process)
    }
    var isAvailable: Bool { availability() }
    func cancelProbes() { lock.lock(); epoch &+= 1; lock.unlock() }
    /// Sampled by the monitor when a request is sealed; any later
    /// `cancelProbes()` makes that request's probe ineligible or cancelled.
    func captureEpoch() -> UInt64 { lock.lock(); defer { lock.unlock() }; return epoch }

    /// `expectedEpoch` is the request's seal-time epoch, never a fresh sample.
    /// The epoch is checked before and after eligibility/`canStart`, immediately
    /// before the latch; a rejection never consumes the latch. `probe` receives
    /// `cancelled`: true once the epoch differs from `expectedEpoch` or the log
    /// can no longer accept records.
    func run<T>(expectedEpoch: UInt64, after trace: MenuHelpRoleRead.Trace?,
                catalogFailure: MenuCatalogTraversal.Failure,
                canStart: () -> Bool = { true },
                probe: (_ cancelled: @escaping () -> Bool) -> T) -> T? {
        guard captureEpoch() == expectedEpoch,
              logActive, structureRequested, catalogFailure == .readFailure(.role),
              let trace, trace.failure == .unsupportedKnownRole,
              let role = trace.role, !role.isBoundary,
              availability(), canStart(),
              captureEpoch() == expectedEpoch,
              latch.consume() else { return nil }
        // A cancellation after this point is seen by the scanner's first
        // checkpoint, before any AX call.
        return probe { [self] in captureEpoch() != expectedEpoch || !availability() }
    }
}
#endif
