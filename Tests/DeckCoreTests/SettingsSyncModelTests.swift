import XCTest
@testable import DeckCore

final class SettingsSyncModelTests: XCTestCase {
    private func stamp(_ t: Double?, _ device: String = "a", _ n: UInt64 = 1) -> SettingsSyncStamp {
        .init(date: t.map { Date(timeIntervalSince1970: $0) }, device: device, sequence: n)
    }
    private func menu(_ id: String = "menu", at t: Double = 10) -> SettingsSyncMenu {
        let s = stamp(t)
        return .init(id: id, appID: "test.app", appName: "Test", path: ["File", id],
                     presence: .init(true, stamp: s), pinned: .init(true, stamp: s),
                     icon: .init([.init(symbol: nil, stamp: s)]))
    }
    func testDifferentFieldsAreBothPreserved() throws {
        let original = menu()
        var a = original, b = original
        a.pinned = .init(false, stamp: stamp(20))
        b.icon = original.icon.choosing("gear", stamp: stamp(21,"b"))
        let merged = try a.merged(with: b)
        XCTAssertFalse(merged.pinned.value); XCTAssertEqual(merged.icon.displayed,"gear")
        XCTAssertFalse(merged.icon.needsChoice)
        XCTAssertEqual(merged,try b.merged(with:a))
    }
    func testLaterOfflineEditRestoresDeletedMenuWithoutLosingOtherFields() throws {
        var a = menu(), b = a
        a.pinned = .init(false, stamp: stamp(15))
        a.presence = .init(false, stamp: stamp(20))
        b.icon = b.icon.choosing("star", stamp: stamp(30,"b"))
        let result = try a.merged(with:b)
        XCTAssertTrue(result.isPresent); XCTAssertFalse(result.pinned.value)
        XCTAssertEqual(result.icon.displayed,"star")
        a.presence = .init(false,stamp:stamp(40))
        XCTAssertFalse(try a.merged(with:result).isPresent)
    }
    func testDelayedOldUploadDoesNotRestoreDeletion() throws {
        var a = menu()
        a.presence = .init(false,stamp:stamp(30))
        XCTAssertFalse(try a.merged(with:menu(at:20)).isPresent)
    }
    func testIndependentIconEditsNeedChoice() {
        let base = menu().icon
        let a = base.choosing("gear",stamp:stamp(20,"a",2))
        let b = base.choosing("star",stamp:stamp(21,"b",1))
        let result = a.merged(with:b)
        XCTAssertTrue(result.needsChoice); XCTAssertEqual(result.edits.count,2)
        XCTAssertEqual(result,b.merged(with:a))
        XCTAssertEqual(result,result.merged(with:result))
        let resolved = result.choosing(nil,stamp:stamp(22,"a",3))
        XCTAssertFalse(resolved.merged(with:result).needsChoice)
        XCTAssertNil(resolved.merged(with:result).displayed)
    }
    func testSequentialIconsAndSameChoiceDoNotPrompt() {
        let a = menu().icon.choosing("gear",stamp:stamp(20,"a",2))
        let b = a.choosing("star",stamp:stamp(21,"b",1))
        XCTAssertEqual(a.merged(with:b),b)
        let same = menu().icon.choosing("gear",stamp:stamp(22,"b",1))
        XCTAssertFalse(a.merged(with:same).needsChoice)
        let next = a.merged(with:same).choosing("heart",stamp:stamp(23,"c",1))
        XCTAssertFalse(next.merged(with:a).merged(with:same).needsChoice)
    }
    func testLegacyCannotBeatRealEditsAndTimestampIsNeverRewritten() {
        let legacy = SettingsSyncField(true,stamp:stamp(nil,"z",10))
        let actual = SettingsSyncField(false,stamp:stamp(10,"a",1))
        XCTAssertEqual(legacy.merged(with:actual),actual)
        XCTAssertEqual(actual.stamp.date,Date(timeIntervalSince1970:10))
    }
    func testEqualTimeTieBreakIsDeterministic() {
        let a = SettingsSyncField(true,stamp:stamp(10,"a"))
        let b = SettingsSyncField(false,stamp:stamp(10,"b"))
        XCTAssertEqual(a.merged(with:b),b.merged(with:a))
        XCTAssertFalse(a.merged(with:b).value)
    }
    func testInitialUnionAndLatestOrderKeepNewItems() throws {
        var a = SettingsSyncSnapshot(), b = SettingsSyncSnapshot()
        a.menus["A"] = menu("A"); b.menus["B"] = menu("B")
        a.orders["test.app"] = .init(["A"],stamp:stamp(20))
        b.orders["test.app"] = .init(["B"],stamp:stamp(30,"b"))
        let result = try a.merged(with:b)
        XCTAssertEqual(result.orderedIDs(appID:"test.app"),["B","A"])
        XCTAssertEqual(result,try b.merged(with:a))
        XCTAssertEqual(result,try result.merged(with:result))
    }
    func testUnpinPreservesSlotForRepin() {
        var s = SettingsSyncSnapshot()
        s.menus["A"] = menu("A"); s.menus["B"] = menu("B")
        s.orders["test.app"] = .init(["B","A"],stamp:stamp(20))
        s.menus["B"]!.pinned = .init(false,stamp:stamp(30))
        XCTAssertEqual(s.orderedIDs(appID:"test.app"),["B","A"])
        s.menus["B"]!.pinned = .init(true,stamp:stamp(40))
        XCTAssertEqual(s.orderedIDs(appID:"test.app"),["B","A"])
    }
    func testUnsupportedSchemaDoesNotOverwriteLocalState() {
        let own = SettingsSyncSnapshot()
        var future = own; future.schema = 99
        XCTAssertThrowsError(try own.merged(with:future))
        XCTAssertEqual(own.schema,1)
    }
    func testRoundTripRetainsConflictAndDeletedFields() throws {
        var s = SettingsSyncSnapshot(); var m = menu()
        m.presence = .init(false,stamp:stamp(40))
        m.icon = m.icon.choosing("gear",stamp:stamp(20,"a",2)).merged(with:menu().icon.choosing("star",stamp:stamp(30,"b",1)))
        s.menus[m.id] = m
        let decoded = try JSONDecoder().decode(SettingsSyncSnapshot.self,from:JSONEncoder().encode(s))
        XCTAssertEqual(s,decoded); XCTAssertFalse(decoded.menus[m.id]!.isPresent)
        XCTAssertEqual(decoded.iconConflicts.count,0)
    }
    func testSameStampDifferentPayloadConverges() throws {
        let t = stamp(20)
        let a = SettingsSyncField(true, stamp: t)
        let b = SettingsSyncField(false, stamp: t)
        XCTAssertEqual(a.merged(with: b), b.merged(with: a))
        var left = menu(), right = menu()
        right.appName = "Another"; right.path = ["Other", "Open"]
        left.pinned = a; right.pinned = b
        XCTAssertEqual(try left.merged(with: right), try right.merged(with: left))
    }
    func testLegacyOrdersBeforeAnyActualDateIncludingDistantPast() {
        let legacy = stamp(nil, "z", 99)
        let actual = SettingsSyncStamp(date: .distantPast, device: "a", sequence: 1)
        XCTAssertLessThan(legacy, actual)
        XCTAssertFalse(actual < legacy)
    }
    func testThreeReplicaMergeIsAssociative() throws {
        var a = SettingsSyncSnapshot(), b = a, c = a
        a.menus["menu"] = menu()
        b.menus["menu"] = menu()
        b.menus["menu"]!.pinned = .init(false, stamp: stamp(20, "b"))
        c.menus["menu"] = menu()
        c.menus["menu"]!.icon = menu().icon.choosing("gear", stamp: stamp(30, "c"))
        XCTAssertEqual(try a.merged(with: b).merged(with: c), try a.merged(with: b.merged(with: c)))
    }
    func testIconDecodeNormalizesDominatedEditsAndRejectsInvalidIdentity() throws {
        struct RawIcon: Encodable { let edits: [SettingsSyncIconEdit] }
        let old = SettingsSyncIconEdit(symbol: "gear", stamp: stamp(10, "a", 1))
        let newer = SettingsSyncIconEdit(symbol: "star", stamp: stamp(20, "b", 1), observed: ["a": 1])
        let data = try JSONEncoder().encode(RawIcon(edits: [old, newer]))
        let decoded = try JSONDecoder().decode(SettingsSyncIcon.self, from: data)
        XCTAssertEqual(decoded.edits, [newer])
        XCTAssertEqual(decoded, decoded.merged(with: decoded))
        let invalid = SettingsSyncIconEdit(symbol: nil, stamp: stamp(30, "a", 1), observed: ["a": 1])
        XCTAssertThrowsError(try JSONDecoder().decode(SettingsSyncIcon.self, from: JSONEncoder().encode(RawIcon(edits: [invalid]))))
    }
    func testInvalidPreferenceAndMenuIdentityAreRejected() throws {
        var snapshot = SettingsSyncSnapshot()
        snapshot.preferences["theme"] = .init(.integer(4), stamp: stamp(10))
        XCTAssertThrowsError(try snapshot.validate())
        snapshot.preferences = [:]
        snapshot.preferences["captureMenus"] = .init(.bool(true), stamp: stamp(10))
        XCTAssertThrowsError(try snapshot.validate())
        var other = menu("another")
        other.appName = "Changed"
        XCTAssertThrowsError(try menu().merged(with: other))
    }

}
