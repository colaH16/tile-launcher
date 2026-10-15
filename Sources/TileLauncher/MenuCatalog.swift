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
                        found.append(AvailableMenu(path: next, shortcut: Self.shortcut(element)))
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
            guard var current = Self.element(application, kAXMenuBarAttribute) else {
                finish("이 앱의 메뉴를 읽을 수 없습니다."); return
            }
            let deadline = Date().addingTimeInterval(3)
            for title in command.path {
                guard Date() < deadline else { finish("메뉴를 확인하는 시간이 초과되었습니다. 실행하지 않았습니다."); return }
                let matches = Self.menuChildren(current).filter { Self.value($0, kAXTitleAttribute) as? String == title }
                guard matches.count == 1, let match = matches.first else {
                    finish("메뉴 ‘\(title)’가 바뀌었거나 같은 이름이 여러 개입니다. 설정에서 다시 등록해 주세요."); return
                }
                current = match
                AXUIElementSetMessagingTimeout(current, 0.12)
            }
            guard Self.value(current, kAXEnabledAttribute) as? Bool == true else {
                finish("지금은 ‘\(command.title)’ 메뉴를 사용할 수 없습니다. 문서나 선택 상태를 확인해 주세요."); return
            }
            guard Self.actions(current).contains(kAXPressAction) else { finish("이 메뉴는 실행 동작을 제공하지 않습니다."); return }
            if let shortcut {
                let equivalent = Self.shortcut(current)
                DispatchQueue.main.async { shortcut(equivalent) }
            }
            let result = AXUIElementPerformAction(current, kAXPressAction as CFString)
            // No automatic retry: a timeout can mean the target already acted.
            finish(result == .success ? nil : "메뉴 실행 결과를 확인하지 못했습니다. 대상 앱을 확인해 주세요.")
        }
    }
    private static func shortcut(_ element: AXUIElement) -> MenuShortcut? {
        guard let key = value(element, kAXMenuItemCmdCharAttribute) as? String, !key.isEmpty else { return nil }
        return MenuShortcut(key: key, modifiers: value(element, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0)
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
    private static func menuChildren(_ element: AXUIElement) -> [AXUIElement] {
        children(element).flatMap { child in
            AXUIElementSetMessagingTimeout(child, 0.12)
            return value(child, kAXRoleAttribute) as? String == kAXMenuRole ? children(child) : [child]
        }
    }
    private static func actions(_ element: AXUIElement) -> [String] {
        var values: CFArray?
        guard AXUIElementCopyActionNames(element, &values) == .success else { return [] }
        return values as? [String] ?? []
    }
}
