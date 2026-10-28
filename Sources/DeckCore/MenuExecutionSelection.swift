import Foundation

/// A descriptive selector inside the owning app; execution always resolves a
/// fresh complete path and checks its identifier before sending AXPress.
public struct MenuActionReference: Codable, Equatable {
    public let path: [String]
    public let identifier: String?
    public init(path: [String], identifier: String?) { self.path = path; self.identifier = identifier }
    public var isValid: Bool {
        (2...12).contains(path.count) && path.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 256 }
            && (identifier == nil || MenuAXIdentifier.validated(identifier) != nil)
    }
}

/// Keep the primary selector and its observed Option companion in one edit so
/// merging two Macs cannot accidentally combine unrelated halves of a pair.
public struct MenuExecutionSelection: Codable, Equatable {
    public let identifier: String?
    public let option: MenuActionReference?
    public init(identifier: String?, option: MenuActionReference? = nil) { self.identifier = identifier; self.option = option }
    public var isValid: Bool {
        (identifier == nil || MenuAXIdentifier.validated(identifier) != nil) && (option?.isValid ?? true)
    }
    public var isEmpty: Bool { identifier == nil && option == nil }
}
