import ApplicationServices

/// Menu-bar acquisition paths used by the production settings lookup.
enum AppSettingsRoute: CaseIterable {
    case multiple, children, roleFirst

    /// Batch API success can still carry an error for an individual attribute.
    static func attributeError(_ raw: CFTypeRef) -> AXError? {
        guard CFGetTypeID(raw) == AXValueGetTypeID(), AXValueGetType(raw as! AXValue) == .axError else { return nil }
        var error = AXError.success
        return AXValueGetValue(raw as! AXValue, .axError, &error) ? error : nil
    }
}
