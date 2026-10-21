import AppKit
import ApplicationServices
import DeckCore

struct AvailableMenu: Identifiable {
    let path: [String]
    var shortcut: MenuShortcut? = nil
    var id: String { path.joined(separator: "\u{1f}") }
    var title: String { path.joined(separator: " › ") }
}

/// Read menus only on explicit request; resolve a fresh exact path for each execution.
final class MenuCatalog: ObservableObject {
    @Published private(set) var choices: [AvailableMenu] = []
    @Published private(set) var loading = false
    @Published private(set) var message: String?
    private let queue = DispatchQueue(label: "TileLauncher.menus", qos: .userInitiated)
    private var generation = UUID()

    init(initialChoices: [AvailableMenu] = []) { choices = Self.searchableChoices(initialChoices) }

    static func searchableChoices(_ menus: [AvailableMenu]) -> [AvailableMenu] {
        let appMenus = menus.filter { !MenuCapturePolicy.isAppleMenuPath($0.path) }
        let counts = Dictionary(grouping: appMenus, by: \.id)
        return appMenus.filter { counts[$0.id]?.count == 1 }
    }

    func clear() { generation = UUID(); choices = []; loading = false; message = nil }

    func load(app: AppItem) {
        let request = UUID()
        generation = request
        choices = []; message = nil; loading = true
        queue.async { [self] in
            guard AXIsProcessTrusted() else {
                DispatchQueue.main.async { [weak self] in
                    guard self?.generation == request else { return }
                    self?.loading = false; self?.message = "접근성 권한을 허용한 뒤 다시 불러와 주세요."
                }
                return
            }
            let application = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(application, 0.08)
            var found: [AvailableMenu] = []
            var count = 0
            let deadline = Date().addingTimeInterval(3)
            var incomplete = false
            func walk(_ element: AXUIElement, path: [String], depth: Int) {
                guard count < 1800, depth < 12, Date() < deadline else { incomplete = true; return }
                count += 1
                AXUIElementSetMessagingTimeout(element, 0.08)
                let role = Self.value(element, kAXRoleAttribute) as? String ?? ""
                let title = Self.value(element, kAXTitleAttribute) as? String ?? ""
                let namedItem = role == kAXMenuBarItemRole || role == kAXMenuItemRole
                let next = namedItem && !title.isEmpty ? path + [title] : path
                guard !MenuCapturePolicy.isAppleMenuPath(next) else { return }
                let children = Self.children(element)
                if role == kAXMenuItemRole, !title.isEmpty, children.isEmpty, next.count >= 2 {
                    if Self.actions(element).contains(kAXPressAction) {
                        found.append(AvailableMenu(path: next, shortcut: MenuShortcutReading.read(element).shortcut))
                    }
                } else {
                    for child in children { walk(child, path: next, depth: depth + 1) }
                }
            }
            if let bar = Self.element(application, kAXMenuBarAttribute) {
                // Match automatic capture: macOS's first root is the system Apple menu.
                for root in Self.children(bar).dropFirst() { walk(root, path: [], depth: 0) }
            }
            // Duplicate menu titles cannot safely identify an action after a later menu update.
            let unique = Self.searchableChoices(found)
            DispatchQueue.main.async { [weak self] in
                guard self?.generation == request else { return }
                self?.loading = false; self?.choices = unique
                self?.message = incomplete ? "응답 시간 안에 읽은 메뉴만 표시합니다. 필요한 메뉴가 없으면 해당 앱에서 메뉴를 연 뒤 다시 불러와 주세요."
                    : unique.isEmpty ? "이 앱이 메뉴를 제공하지 않았습니다. 앱에서 메뉴를 한 번 연 뒤 다시 불러오거나 메뉴 경로를 직접 추가해 주세요." : nil
            }
        }
    }

    /// `shortcut` reports the item's current keyboard equivalent (nil = none) before it is pressed.
    func execute(_ command: MenuCommand, in app: AppItem, shortcut: ((MenuShortcut?) -> Void)? = nil,
                 completion: @escaping (String?) -> Void) {
        queue.async {
            func finish(_ error: String?) { DispatchQueue.main.async { completion(error) } }
            guard AXIsProcessTrusted(), command.appID == app.id else {
                finish("메뉴에 접근할 수 없습니다. 앱과 접근성 권한을 확인해 주세요."); return
            }
            let application = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(application, 0.12)
            guard let bar = Self.element(application, kAXMenuBarAttribute) else {
                finish("이 앱의 메뉴를 읽을 수 없습니다."); return
            }
            let deadline = Date().addingTimeInterval(3)
            var failed = false
            func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
                guard !failed, Date() < deadline else { failed = true; return nil }
                AXUIElementSetMessagingTimeout(element, 0.08)
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
                if result != .success && result != .noValue && result != .attributeUnsupported { failed = true }
                return result == .success ? value : nil
            }
            let resolved = MenuPathResolver.resolve(paths: MenuPathMatch.paths(command), root: bar, children: { element in
                let raw = read(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
                var children: [AXUIElement] = []
                for child in raw {
                    if read(child, kAXRoleAttribute) as? String == kAXMenuRole {
                        children += read(child, kAXChildrenAttribute) as? [AXUIElement] ?? []
                    } else { children.append(child) }
                    if failed { return nil }
                }
                return failed ? nil : children
            }, title: { element in
                let name = read(element, kAXTitleAttribute) as? String ?? ""
                return failed ? nil : name
            }, equal: { CFEqual($0, $1) }, preferredShortcut: command.shortcut, shortcut: { element in
                let key = read(element, kAXMenuItemCmdCharAttribute) as? String
                guard !failed else { return (nil, false) }
                guard let key, !key.isEmpty else { return (nil, true) }
                guard let modifiers = read(element, kAXMenuItemCmdModifiersAttribute) as? Int, !failed,
                      let equivalent = MenuShortcut(key: key, modifiers: modifiers) else { return (nil, false) }
                return (equivalent, true)
            })
            let current: AXUIElement
            switch resolved {
            case .found(let element): current = element
            case .unavailable: finish("메뉴 정보를 확인하지 못했습니다. 실행하지 않았습니다."); return
            case .ambiguous: finish("같은 경로의 메뉴가 여러 개입니다. 실행하지 않았습니다."); return
            case .missing: finish("메뉴 경로가 바뀌었거나 언어 연결을 확인하지 못했습니다. 설정에서 다시 등록해 주세요."); return
            }
            guard Date() < deadline else { finish("메뉴 확인 시간이 초과되었습니다. 실행하지 않았습니다."); return }
            guard Self.value(current, kAXEnabledAttribute) as? Bool == true else {
                finish("지금은 ‘\(command.title)’ 메뉴를 사용할 수 없습니다. 문서나 선택 상태를 확인해 주세요."); return
            }
            guard Self.actions(current).contains(kAXPressAction) else { finish("이 메뉴는 실행 동작을 제공하지 않습니다."); return }
            // Report only a confirmed reading: a timeout must not erase a saved shortcut.
            if let shortcut, case let reading = MenuShortcutReading.read(current), reading.known {
                DispatchQueue.main.async { shortcut(reading.shortcut) }
            }
            let result = AXUIElementPerformAction(current, kAXPressAction as CFString)
            // No automatic retry: a timeout can mean the target already acted.
            finish(result == .success ? nil : "메뉴 실행 결과를 확인하지 못했습니다. 대상 앱을 확인해 주세요.")
        }
    }
    private static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    private static func element(_ element: AXUIElement, _ key: String) -> AXUIElement? {
        guard let result = value(element, key), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    private static func actions(_ element: AXUIElement) -> [String] {
        var values: CFArray?
        guard AXUIElementCopyActionNames(element, &values) == .success else { return [] }
        return values as? [String] ?? []
    }
}

/// A menu item's keyboard equivalent, distinguishing “none” from “could not read”.
enum MenuShortcutReading {
    static func read(_ element: AXUIElement) -> (shortcut: MenuShortcut?, known: Bool) {
        var raw: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, kAXMenuItemCmdCharAttribute as CFString, &raw) {
        case .success:
            if let key = raw as? String, !key.isEmpty {
                var modifiers: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, kAXMenuItemCmdModifiersAttribute as CFString, &modifiers) == .success
                else { return (nil, false) }
                return (MenuShortcut(key: key, modifiers: modifiers as? Int ?? 0), true)
            }
            return noCharacter(element)
        case .noValue, .attributeUnsupported: return noCharacter(element)
        default: return (nil, false)
        }
    }
    /// Arrow/Delete/F-key equivalents have no character. They are not shown,
    /// but they are not “removed” either, so leave any saved value alone.
    private static func noCharacter(_ element: AXUIElement) -> (shortcut: MenuShortcut?, known: Bool) {
        var key: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXMenuItemCmdVirtualKeyAttribute as CFString, &key)
        if result == .success, key != nil { return (nil, false) }
        return (nil, result == .noValue || result == .attributeUnsupported || result == .success)
    }
}
