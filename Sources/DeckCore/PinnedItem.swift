import Foundation

public enum FolderOpenMode: String, Codable, CaseIterable, Identifiable {
    case overlay, finder
    public var id: Self { self }
    public var title: String {
        switch self {
        case .overlay: return "오버레이에서 탐색"
        case .finder: return "Finder에서 열기"
        }
    }
}

public struct PinnedItem: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable { case app, folder, trash }
    public var id: String { path }
    public let kind: Kind
    public let path: String
    public let bundleID: String?
    public let name: String
    public private(set) var openMode: FolderOpenMode
    public var opensInOverlay: Bool { kind == .folder && openMode == .overlay }

    public init(kind: Kind, path: String, bundleID: String?, name: String,
                openMode: FolderOpenMode = .overlay) {
        self.kind = kind
        self.path = path
        self.bundleID = bundleID
        self.name = name
        self.openMode = kind == .trash ? .finder : openMode
    }

    public mutating func setOpenMode(_ mode: FolderOpenMode) {
        guard kind == .folder else { return }
        openMode = mode
    }

    private enum CodingKeys: String, CodingKey { case kind, path, bundleID, name, openMode }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try values.decode(Kind.self, forKey: .kind),
                  path: try values.decode(String.self, forKey: .path),
                  bundleID: try values.decodeIfPresent(String.self, forKey: .bundleID),
                  name: try values.decode(String.self, forKey: .name),
                  openMode: try values.decodeIfPresent(FolderOpenMode.self, forKey: .openMode) ?? .overlay)
    }
}
