import AppKit
import ApplicationServices
import DeckCore
import Darwin

struct ServerWindow {
    let id: CGWindowID
    let pid: pid_t
    let title: String?
    let bounds: CGRect
    let onScreen: Bool
    let alpha: Double
    let orderedIn: Bool?
    var isCandidate: Bool { WindowPresence.serverCandidate(alpha: alpha, bounds: bounds, orderedIn: orderedIn) }
}

/// No images or screen capture. Public WindowServer metadata supplies the full
/// inventory; optional private symbols supply IDs/Space membership absent from
/// public AX. Every private entry point is runtime-checked and isolated here.
final class DesktopWindows {
    private typealias Connection = @convention(c) () -> UInt32
    private typealias Displays = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias Spaces = @convention(c) (UInt32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias WindowNumber = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32
    private typealias OrderedIn = @convention(c) (UInt32, CGWindowID, UnsafeMutablePointer<UInt8>) -> Int32
    private let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private let ax = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY)
    private var connection: UInt32?
    private var displays: Displays?
    private var spaces: Spaces?
    private var windowNumber: WindowNumber?
    private var orderedIn: OrderedIn?
    private(set) var records: [CGWindowID: ServerWindow] = [:]
    private(set) var valid = false
    private var activeSpaces: Set<UInt64> = []
    private var memberships: [CGWindowID: Set<UInt64>] = [:]

    init() {
        if let sky {
            if let symbol = dlsym(sky, "CGSMainConnectionID") ?? dlsym(sky, "_CGSDefaultConnection") {
                connection = unsafeBitCast(symbol, to: Connection.self)()
            }
            if let p = dlsym(sky, "CGSCopyManagedDisplaySpaces") { displays = unsafeBitCast(p, to: Displays.self) }
            if let p = dlsym(sky, "CGSCopySpacesForWindows") { spaces = unsafeBitCast(p, to: Spaces.self) }
            if let p = dlsym(sky, "SLSWindowIsOrderedIn") ?? dlsym(sky, "CGSWindowIsOrderedIn") {
                orderedIn = unsafeBitCast(p, to: OrderedIn.self)
            }
        }
        if let ax, let p = dlsym(ax, "_AXUIElementGetWindow") { windowNumber = unsafeBitCast(p, to: WindowNumber.self) }
    }
    // Keep framework handles alive for these function pointers for the app lifetime.
    func refresh() {
        memberships.removeAll(keepingCapacity: true)
        activeSpaces.removeAll(keepingCapacity: true)
        if let connection, let list = displays?(connection)?.takeRetainedValue() as? [[String: Any]] {
            for display in list {
                if let current = display["Current Space"] as? [String: Any], let id = Self.spaceID(current) {
                    activeSpaces.insert(id)
                }
            }
        }
        guard let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            valid = false
            return
        }
        valid = true
        records.removeAll(keepingCapacity: true)
        for row in rows {
            guard let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value, id != 0,
                  let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  (row[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let dictionary = row[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary), !bounds.isEmpty else { continue }
            let title = (row[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
            records[id] = ServerWindow(id: id, pid: pid, title: title, bounds: bounds,
                                       onScreen: row[kCGWindowIsOnscreen as String] as? Bool ?? false,
                                       alpha: (row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                                       orderedIn: ordering(for: id))
        }
    }
    private func ordering(for id: CGWindowID) -> Bool? {
        guard let connection, let orderedIn else { return nil }
        var result: UInt8 = 255
        guard orderedIn(connection, id, &result) == 0, result <= 1 else { return nil }
        return result == 1
    }
    func id(for element: AXUIElement, pid: pid_t) -> CGWindowID? {
        var id: CGWindowID = 0
        if windowNumber?(element, &id) == AXError.success.rawValue, id != 0,
           records[id]?.pid == pid { return id }
        // Exact, unambiguous geometry only; never guess among overlapping windows.
        guard let position: AXValue = Self.attribute(element, kAXPositionAttribute),
              let size: AXValue = Self.attribute(element, kAXSizeAttribute),
              AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        let rect = CGRect(origin: point, size: dimensions)
        let matches = records.values.filter { $0.pid == pid && $0.bounds == rect }
        return matches.count == 1 ? matches[0].id : nil
    }
    func desktop(for id: CGWindowID?) -> WindowDesktop {
        guard valid, let id, let record = records[id] else { return .unknown }
        return WindowDesktop.resolve(windowSpaces: membership(id), activeSpaces: activeSpaces, onScreen: record.onScreen)
    }
    // Space metadata is read-only. Do not directly set a managed display's
    // current Space: it can expose two Spaces without a Dock transition.
    private func membership(_ id: CGWindowID) -> Set<UInt64>? {
        if let saved = memberships[id] { return saved }
        guard let connection, let values = spaces?(connection, 7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return nil }
        let result = Set(values.map(\.uint64Value))
        memberships[id] = result
        return result
    }
    private static func spaceID(_ dictionary: [String: Any]) -> UInt64? {
        ((dictionary["ManagedSpaceID"] ?? dictionary["id64"]) as? NSNumber)?.uint64Value
    }
    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
