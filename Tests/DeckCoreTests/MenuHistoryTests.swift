import XCTest
@testable import DeckCore

final class MenuHistoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
    func menu(_ name: String, days: Double, app: String = "excel") -> MenuCommand {
        var command = MenuCommand(appID: app, appName: app, path: ["File", name], isPinned: false)
        command.isAutomatic = true
        command.recordUse(at: ago(days), observed: true)
        return command
    }
    func visible(_ commands: [MenuCommand], history: MenuHistoryPreferences = .init()) -> [MenuCommand] {
        MenuCommand.ordered(commands, appID: "excel", history: history, at: now)
    }
    func testOldMenusRetainFivePerAppAndSixthExpiresOnlyWhenBothConditionsFail() {
        let commands = (0..<6).map { menu("\($0)", days: Double(40 + $0)) }
        let other = (0..<20).map { menu("other\($0)", days: 0, app: "finder") }
        XCTAssertEqual(visible(commands + other).map(\.title), ["0", "1", "2", "3", "4"])
        XCTAssertEqual(visible(Array(commands.prefix(2))).count, 2)
        XCTAssertEqual(MenuCommand.ordered(commands, appID: "excel", at: now, includingHidden: true).count, 6)
    }
    func testSixthSeventhAndAllWithinThirtyDaysStayIncludingBoundary() {
        let commands = (0..<6).map { menu("\($0)", days: Double($0)) }
            + [menu("boundary", days: 30), menu("old", days: 30.00001)]
        XCTAssertEqual(visible(commands).count, 7)
        XCTAssertTrue(visible(commands).contains { $0.title == "boundary" })
        XCTAssertFalse(visible(commands).contains { $0.title == "old" })
    }
    func testPinsAndUnusedManualMenusDoNotConsumeFiveRecentSlots() {
        let recent = (0..<6).map { menu("\($0)", days: Double(40 + $0)) }
        let pins = (0..<8).map { i -> MenuCommand in
            var item = menu("pin\(i)", days: 0); item.isPinned = true; return item
        }
        let manual = MenuCommand(appID: "excel", appName: "Excel", path: ["File", "Manual"], isPinned: false)
        XCTAssertEqual(visible(recent + pins + [manual]).count, 14)
        XCTAssertEqual(visible(recent + pins).filter { !$0.isPinned }.count, 5)
    }
    func testFrequencyUsesNinetyDayWindowAndCombinesBothSources() {
        var command = menu("Monthly", days: 90)
        command.recordUse(at: ago(60))
        command.recordUse(at: ago(31), observed: true)
        XCTAssertTrue(command.isFrequent(history: .init(), at: now))
        XCTAssertFalse(command.isFrequent(history: .init(), at: now.addingTimeInterval(1)))
        XCTAssertEqual(command.useCount, 1)
        XCTAssertEqual(command.observedCount, 2)
        let recent = (0..<5).map { menu("\($0)", days: Double($0)) }
        XCTAssertTrue(visible(recent + [command]).contains { $0.id == command.id })
    }
    func testChangingPeriodsRestoresArchivedMenusAndChangesWideState() {
        var monthly = menu("Monthly", days: 100)
        monthly.recordUse(at: ago(80)); monthly.recordUse(at: ago(60))
        let commands = (0..<6).map { menu("\($0)", days: Double(40 + $0)) } + [monthly]
        XCTAssertFalse(visible(commands).contains { $0.id == monthly.id })
        XCTAssertEqual(visible(commands, history: .init(recentDays: 120)).count, 7)
        XCTAssertTrue(monthly.isFrequent(history: .init(frequentDays: 120), at: now))
        XCTAssertFalse(monthly.isFrequent(history: .init(frequentDays: 30), at: now))
    }
    func testOnlyThreeLatestDatesAreNeededRegardlessOfLongHistory() throws {
        var command = menu("Long history", days: 300)
        for day in (0..<100).reversed() { command.recordUse(at: ago(Double(day))) }
        XCTAssertEqual(command.recentUses, [ago(0), ago(1), ago(2)])
        XCTAssertFalse(command.isFrequent(history: .init(frequentDays: 1), at: now))
        XCTAssertTrue(command.isFrequent(history: .init(frequentDays: 2), at: now))
        XCTAssertEqual(try JSONDecoder().decode(MenuCommand.self, from: JSONEncoder().encode(command)), command)
    }
    func testLegacyLifetimeCountsDoNotPretendToHaveNinetyDayDates() throws {
        var command = menu("Legacy", days: 10)
        command.useCount = 500
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as! [String: Any]
        object.removeValue(forKey: "recentUses")
        var migrated = try JSONDecoder().decode(MenuCommand.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(migrated.id, command.id)
        XCTAssertEqual(migrated.useCount, 500)
        XCTAssertEqual(migrated.recentUses, [ago(10)])
        XCTAssertFalse(migrated.isFrequent(history: .init(), at: now))
        migrated.recordUse(at: ago(2)); migrated.recordUse(at: ago(1))
        XCTAssertTrue(migrated.isFrequent(history: .init(), at: now))
    }
    func testPreferencesDefaultsPersistenceAndValidation() throws {
        XCTAssertEqual(MenuHistoryPreferences.restore(nil), .init(recentDays: 30, frequentDays: 90))
        XCTAssertEqual(MenuHistoryPreferences.restore(Data("bad".utf8)), .init())
        XCTAssertEqual(MenuHistoryPreferences(recentDays: 0, frequentDays: -1), .init())
        XCTAssertEqual(MenuHistoryPreferences.restore(Data("{\"recentDays\":-1}".utf8)), .init())
        let preferences = MenuHistoryPreferences(recentDays: 45, frequentDays: 180)
        XCTAssertEqual(MenuHistoryPreferences.restore(try JSONEncoder().encode(preferences)), preferences)
    }
}
