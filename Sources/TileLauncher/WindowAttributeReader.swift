import ApplicationServices

enum WindowAttributeReader {
    static let keys = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute,
                       kAXMinimizedAttribute, kAXPositionAttribute, kAXSizeAttribute]
    static func read(_ element: AXUIElement,
        batch: (AXUIElement, [String]) -> (AXError, [AnyObject]?) = { element, keys in
            var raw: CFArray?
            let result = AXUIElementCopyMultipleAttributeValues(element, keys as CFArray, .init(rawValue: 0), &raw)
            return (result, raw as? [AnyObject])
        }, single: (AXUIElement, String) -> (AXError, CFTypeRef?) = { element, key in
            var raw: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, key as CFString, &raw)
            return (result, raw)
        }) -> [CFTypeRef?]? {
        let (status, raw) = batch(element, keys)
        if status == .cannotComplete { return nil }
        if status == .success, let raw, raw.count == keys.count {
            var values: [CFTypeRef?] = []
            for value in raw {
                if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError {
                    var error = AXError.success
                    AXValueGetValue(value as! AXValue, .axError, &error)
                    if error == .cannotComplete { return nil }
                    values.append(nil)
                } else { values.append(value) }
            }
            return values
        }
        var values: [CFTypeRef?] = []
        for (index, key) in keys.enumerated() {
            let (result, value) = single(element, key)
            if result == .cannotComplete { return nil }
            values.append(result == .success ? value : nil)
            if index == 0 && (result != .success || value as? String != kAXWindowRole) {
                return values + Array(repeating: nil, count: keys.count - 1)
            }
        }
        return values
    }
}
