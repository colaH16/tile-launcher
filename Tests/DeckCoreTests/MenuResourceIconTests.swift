import XCTest
@testable import DeckCore

final class MenuResourceIconTests: XCTestCase {
    private func icon(_ app: String = "music", _ digest: String = "a") -> MenuResourceIcon {
        MenuResourceIcon(kind: .symbol, digest: String(repeating: digest, count: 64), template: true,
                         sourceAppID: app, sourceAppName: app, resourceName: "film")
    }
    func testOwnParentWinsAndBorrowingRequiresUnambiguousExactTitle() {
        let own = icon(), other = icon("other", "b")
        let pool = [MenuIconCandidate(title: "Open", parent: "File", icon: own),
                    MenuIconCandidate(title: "Open", parent: "Edit", icon: other)]
        XCTAssertEqual(MenuIconMatch.resolve(appID: "music", path: ["File", "Open"], candidates: pool), own)
        XCTAssertNil(MenuIconMatch.resolve(appID: "third", path: ["File", "Open"], candidates: pool))
        XCTAssertEqual(MenuIconMatch.resolve(appID: "third", path: ["File", " OPEN "], candidates: [pool[0]]), own)
        XCTAssertNil(MenuIconMatch.resolve(appID: "third", path: ["File", "Open…"], candidates: pool))
        XCTAssertNil(MenuIconMatch.resolve(appID: "third", path: ["File", "열기"], candidates: pool))
        let conflict = MenuIconCandidate(title: "Open", parent: "Other", icon: icon("music", "b"))
        XCTAssertEqual(MenuIconMatch.resolve(appID: "music", path: ["File", "Open"], candidates: [pool[0], conflict]), own)
        XCTAssertNil(MenuIconMatch.resolve(appID: "music", path: ["Unknown", "Open"], candidates: [pool[0], conflict]))
    }
    func testManualChoiceAndNoIconOverrideResourceWhileDefaultPrefersResource() {
        let resource = icon(), shortcut = MenuShortcut(key: "o", modifiers: 0)
        XCTAssertEqual(MenuTileGlyph.resolve(symbol: "star", preset: "folder", shortcut: shortcut, resource: resource), .symbol("star"))
        XCTAssertEqual(MenuTileGlyph.resolve(symbol: "", preset: "folder", shortcut: shortcut, resource: resource), .shortcut("⌘O"))
        XCTAssertEqual(MenuTileGlyph.resolve(symbol: nil, preset: "folder", shortcut: shortcut, resource: resource), .resource(resource))
    }
    func testFrozenSourceAndKindRoundTripWithCommand() throws {
        var command = MenuCommand(appID: "target", appName: "Target", path: ["File", "Open"])
        command.resourceIcon = icon("donor")
        let decoded = try JSONDecoder().decode(MenuCommand.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(decoded, command)
        XCTAssertEqual(decoded.resourceIcon?.sourceAppID, "donor")
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as! [String: Any]
        object.removeValue(forKey: "resourceIcon")
        XCTAssertNil(try JSONDecoder().decode(MenuCommand.self, from: JSONSerialization.data(withJSONObject: object)).resourceIcon)
        object["resourceIcon"] = ["kind": "unknown-future-format"]
        let recovered = try JSONDecoder().decode(MenuCommand.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(recovered.resourceIcon)
        XCTAssertEqual(recovered.id, command.id)
        XCTAssertFalse(MenuResourceIcon(kind: .pdf, digest: "../escape", template: false,
                                        sourceAppID: "a", sourceAppName: "A", resourceName: "x").validDigest)
    }
    func testReadsOnlyActualMenuImageAndKeepsLocalizationKeys() {
        let links = MenuNibResources.links(in: nib())
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.title, "Show Movie in Library")
        XCTAssertEqual(links.first?.titleKey, "movie.title")
        XCTAssertEqual(links.first?.parent, "View")
        XCTAssertEqual(links.first?.resource, "film")
        XCTAssertEqual(links.first?.systemSymbol, true)
        XCTAssertTrue(MenuNibResources.links(in: nib(imageKey: "NSOnImage")).isEmpty)
    }
    func testTruncatedUnknownAndMaliciousArchivesFailClosed() {
        let valid = nib()
        for length in 0..<valid.count { XCTAssertTrue(MenuNibResources.links(in: valid.prefix(length)).isEmpty, "length \(length)") }
        var unknown = valid; unknown[14] = 99
        XCTAssertTrue(MenuNibResources.links(in: unknown).isEmpty)
        var oversized = valid; oversized.replaceSubrange(18..<22, with: [255, 255, 255, 127])
        XCTAssertTrue(MenuNibResources.links(in: oversized).isEmpty)
        var random: UInt64 = 0x12345
        for _ in 0..<400 {
            var bytes = valid
            random = random &* 6364136223846793005 &+ 1
            let offset = Int(random % UInt64(bytes.count))
            bytes[offset] ^= UInt8(truncatingIfNeeded: random >> 32)
            _ = MenuNibResources.links(in: bytes) // No trap, recursion, or unbounded allocation.
        }
    }
    /// Independent minimal encoder for a menu → resource link. No Cocoa objects
    /// are decoded/executed by the production parser.
    private func nib(imageKey: String = "NSImage") -> Data {
        func u32(_ n: Int) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) } }
        func vi(_ number: Int) -> [UInt8] {
            var n = number, result: [UInt8] = []
            repeat { let part = UInt8(n & 127); n >>= 7; result.append(part | (n == 0 ? 128 : 0)) } while n != 0
            return result
        }
        let keys = ["NSTitle", imageKey, "NSMenu", "NS.bytes", "NSKey", "NSResourceName", "NSCatalogName", "NSClassName"]
        let names = ["NSMenuItem", "NSLocalizableString", "NSString", "NSMenu", "NSCustomResource"]
        func ref(_ key: Int, _ object: Int) -> [UInt8] { vi(key) + [10] + u32(object) }
        func text(_ value: String) -> [UInt8] { vi(3) + [8] + vi(value.utf8.count) + Array(value.utf8) }
        let fields: [(Int, [[UInt8]])] = [
            (0, [ref(0,1), ref(1,5), ref(2,3)]), (1, [text("Show Movie in Library"), ref(4,2)]),
            (2, [text("movie.title")]), (3, [ref(0,4)]), (2, [text("View")]),
            (4, [ref(5,6), ref(6,7), ref(7,8)]), (2, [text("film")]), (2, [text("system")]), (2, [text("NSImage")])]
        var objects: [UInt8] = [], values: [UInt8] = [], valueCount = 0
        for (name, fields) in fields {
            objects += vi(name) + vi(valueCount) + vi(fields.count)
            valueCount += fields.count; values += fields.flatMap { $0 }
        }
        let keyBytes: [UInt8] = keys.flatMap { vi($0.utf8.count) + Array($0.utf8) }
        let classBytes: [UInt8] = names.flatMap { name -> [UInt8] in
            var bytes = vi(name.utf8.count + 1)
            bytes += vi(0); bytes += Array(name.utf8); bytes.append(0)
            return bytes
        }
        let keyOffset = 50 + objects.count, valueOffset = keyOffset + keyBytes.count, classOffset = valueOffset + values.count
        let header = [1,10,fields.count,50,keys.count,keyOffset,valueCount,valueOffset,names.count,classOffset].flatMap(u32)
        var bytes = Array("NIBArchive".utf8)
        for segment in [header, objects, keyBytes, values, classBytes] { bytes += segment }
        return Data(bytes)
    }
}
