import AppKit
import ApplicationServices

/// Each lookup owns its AX application/bar references; no system-wide timeout.
struct AppSettingsAXAccess {
    let deadline: TimeInterval
    let cancelled: () -> Bool
    func prepare(_ element: AXUIElement) throws {
        guard !cancelled() else { throw ApplicationSettingsMenu.ReadError.cancelled }
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { throw ApplicationSettingsMenu.ReadError.deadline }
        let status = AXUIElementSetMessagingTimeout(element, Float(min(0.3, remaining)))
        guard status == .success else { throw ApplicationSettingsMenu.ReadError.ax(status) }
    }
    func check(_ status: AXError) throws {
        guard status == .success || status == .noValue || status == .attributeUnsupported else {
            throw ApplicationSettingsMenu.ReadError.ax(status)
        }
    }
    func value(_ element: AXUIElement, _ key: String) throws -> CFTypeRef? {
        try prepare(element)
        var result: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, key as CFString, &result)
        try check(status)
        return status == .success ? result : nil
    }
    func element(_ raw: CFTypeRef?) -> AXUIElement? {
        guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }
    func menuBar(route: AppSettingsRoute, app: AppItem) throws -> AXUIElement? {
        let application = AXUIElementCreateApplication(app.pid)
        let bar: AXUIElement?
        switch route {
        case .roleFirst:
            _ = try value(application, kAXRoleAttribute)
            bar = element(try value(application, kAXMenuBarAttribute))
        case .multiple:
            try prepare(application)
            var results: CFArray?
            let status = AXUIElementCopyMultipleAttributeValues(application, [kAXMenuBarAttribute, kAXRoleAttribute] as CFArray, [], &results)
            try check(status)
            let raw = (results as? [AnyObject])?.first
            if let raw, let error = AppSettingsRoute.attributeError(raw) {
                try check(error)
                bar = nil
            } else { bar = element(raw) }
        case .children:
            let children = try value(application, kAXChildrenAttribute) as? [AXUIElement] ?? []
            var candidate: AXUIElement?
            for child in children.prefix(32) {
                if try value(child, kAXRoleAttribute) as? String == kAXMenuBarRole { candidate = child; break }
            }
            bar = candidate
        }
        guard let bar else { throw ApplicationSettingsMenu.ReadError.incomplete }
        try prepare(bar)
        var pid: pid_t = 0
        let status = AXUIElementGetPid(bar, &pid)
        try check(status)
        guard status == .success && pid == app.pid else { throw ApplicationSettingsMenu.ReadError.incomplete }
        return bar
    }
}
