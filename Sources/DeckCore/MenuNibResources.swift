import Foundation

/// Reads values, never instantiates NSNib/NSKeyedUnarchiver or another app's code.
/// NIBArchive is not a public interchange format; unknown versions fail closed.
/// Layout reference: github.com/matsmattsson/nibsqueeze/blob/master/NibArchive.md
public enum MenuNibResources {
    public struct Link: Equatable {
        public let title: String
        public let titleKey: String?
        public let parent: String?
        public let parentKey: String?
        public let resource: String
        public let systemSymbol: Bool
    }
    public static func links(in data: Data) -> [Link] {
        (try? Archive(data).links()) ?? []
    }
    private enum Invalid: Error { case archive }
    private enum Value { case reference(Int), bytes(Data), ignored }
    private struct Object { let name: String; let values: [String: Value] }
    private struct Reader {
        let bytes: [UInt8]
        var position = 0
        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, position >= 0, position <= bytes.count, count <= bytes.count - position else { throw Invalid.archive }
            defer { position += count }
            return Array(bytes[position..<(position + count)])
        }
        mutating func integer(_ size: Int) throws -> Int {
            let raw = try take(size)
            return raw.enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
        }
        mutating func variable() throws -> Int {
            var result = 0
            for shift in stride(from: 0, through: 28, by: 7) {
                let byte = try integer(1)
                result |= (byte & 127) << shift
                if byte & 128 != 0 { return result }
            }
            throw Invalid.archive
        }
        mutating func string(_ count: Int) throws -> String {
            guard let value = String(bytes: try take(count), encoding: .utf8) else { throw Invalid.archive }
            return value.trimmingCharacters(in: .init(charactersIn: "\0"))
        }
    }
    private struct Archive {
        var objects: [Object] = []
        init(_ data: Data) throws {
            guard data.count >= 50, data.count <= 8 * 1024 * 1024 else { throw Invalid.archive }
            var r = Reader(bytes: Array(data))
            guard try r.string(10) == "NIBArchive", try r.integer(4) == 1 else { throw Invalid.archive }
            let version = try r.integer(4)
            guard version == 9 || version == 10 else { throw Invalid.archive }
            var header: [(count: Int, offset: Int)] = []
            for limit in [100_000, 10_000, 300_000, 1_000] {
                let count = try r.integer(4), offset = try r.integer(4)
                guard count <= limit, offset >= 50, offset <= data.count else { throw Invalid.archive }
                header.append((count, offset))
            }
            r.position = header[0].offset
            var ranges: [(Int, Int, Int)] = []
            for _ in 0..<header[0].count { ranges.append((try r.variable(), try r.variable(), try r.variable())) }
            r.position = header[1].offset
            var keys: [String] = []
            for _ in 0..<header[1].count { keys.append(try r.string(r.variable())) }
            r.position = header[3].offset
            var names: [String] = []
            for _ in 0..<header[3].count {
                let count = try r.variable(), extra = try r.variable()
                guard extra <= 16 else { throw Invalid.archive }
                _ = try r.take(extra * 4)
                names.append(try r.string(count))
            }
            r.position = header[2].offset
            var values: [(String, Value)] = []
            for _ in 0..<header[2].count {
                let key = try r.variable(), type = try r.integer(1)
                guard keys.indices.contains(key) else { throw Invalid.archive }
                let value: Value
                switch type {
                case 0, 1, 2, 3, 6, 7:
                    _ = try r.take([0:1, 1:2, 2:4, 3:8, 6:4, 7:8][type]!); value = .ignored
                case 4, 5, 9: value = .ignored
                case 8: value = .bytes(Data(try r.take(r.variable())))
                case 10:
                    let index = try r.integer(4)
                    guard index < header[0].count else { throw Invalid.archive }
                    value = .reference(index)
                default: throw Invalid.archive
                }
                values.append((keys[key], value))
            }
            var expandedCount = 0
            for (name, start, count) in ranges {
                guard names.indices.contains(name), start <= values.count, count <= values.count - start else { throw Invalid.archive }
                expandedCount += count
                guard expandedCount <= 600_000 else { throw Invalid.archive }
                var fields: [String: Value] = [:]
                for (key, value) in values[start..<(start + count)] { fields[key] = value }
                objects.append(Object(name: names[name], values: fields))
            }
        }
        func reference(_ object: Int, _ key: String) -> Int? {
            if case .reference(let index) = objects[object].values[key] { return index }
            return nil
        }
        func string(_ object: Int?, _ key: String = "NS.bytes") -> String? {
            guard let object else { return nil }
            switch objects[object].values[key] {
            case .bytes(let bytes): return String(data: bytes, encoding: .utf8)
            case .reference(let index):
                if case .bytes(let bytes) = objects[index].values["NS.bytes"] { return String(data: bytes, encoding: .utf8) }
                return nil
            default: return nil
            }
        }
        func links() -> [Link] {
            objects.indices.compactMap { i in
                guard objects[i].name == "NSMenuItem" || string(i, "NSOriginalClassName") == "NSMenuItem",
                      let titleRef = reference(i, "NSTitle"), let title = string(titleRef), !title.isEmpty,
                      let image = reference(i, "NSImage"), objects[image].name == "NSCustomResource",
                      string(image, "NSClassName") == "NSImage",
                      let resource = string(image, "NSResourceName"), !resource.isEmpty, resource.count <= 240 else { return nil }
                let parent = reference(i, "NSMenu").flatMap { reference($0, "NSTitle") }
                return Link(title: title, titleKey: string(titleRef, "NSKey"), parent: string(parent),
                            parentKey: string(parent, "NSKey"), resource: resource,
                            systemSymbol: string(image, "NSCatalogName") == "system" || string(image, "IBNamespaceID") == "system")
            }
        }
    }
}
