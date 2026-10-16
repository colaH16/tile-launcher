import XCTest
@testable import DeckCore

final class MenuOrderingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private func menu(_ title: String, uses: Int, days: Double = 0, pinned: Bool = false, app: String = "iterm") -> MenuCommand {
        var value = MenuCommand(appID: app, appName: app, path: ["Shell", title], isPinned: pinned)
        value.isAutomatic = true
        for index in 0..<uses {
            value.recordUse(at: now.addingTimeInterval(-days * 86_400 - Double(index)), observed: index % 2 == 0)
        }
        return value
    }
    func testPinnedManualOrderPrecedesCombinedCountsAcrossRecentAndFrequent() {
        let pinA = menu("Pin A", uses: 1, pinned: true), pinB = menu("Pin B", uses: 20, pinned: true)
        let recentHigh = menu("Old but retained", uses: 12, days: 100)
        let frequent = menu("Frequent", uses: 4)
        let recent = menu("Recent", uses: 1)
        let foreign = menu("Other app", uses: 100, app: "other")
        let all = [recent, pinA, frequent, pinB, foreign, recentHigh]
        XCTAssertFalse(recentHigh.isFrequent(history: .init(), at: now))
        XCTAssertTrue(frequent.isFrequent(history: .init(), at: now))
        XCTAssertEqual(MenuCommand.ordered(all, appID: "iterm", at: now).map(\.id),
                       [pinA.id, pinB.id, recentHigh.id, frequent.id, recent.id])
        XCTAssertEqual(MenuCommand.ordered(all, appID: "iterm", at: now, includingHidden: true).map(\.id),
                       [pinA.id, pinB.id, recentHigh.id, frequent.id, recent.id])
    }
    func testEqualCountsUseLatestDateThenStableStorageOrder() {
        let older = menu("Older", uses: 2, days: 1)
        let newerA = menu("Newer A", uses: 2), newerB = menu("Newer B", uses: 2)
        let unusedA = menu("Unused A", uses: 0), unusedB = menu("Unused B", uses: 0)
        let all = [older, newerA, unusedA, newerB, unusedB]
        XCTAssertEqual(MenuCommand.ordered(all, appID: "iterm", at: now, includingHidden: true).map(\.id),
                       [newerA.id, newerB.id, older.id, unusedA.id, unusedB.id])
    }
    func testHighLifetimeCountDoesNotOverrideExistingRetentionPolicy() {
        let recentFive = (0..<5).map { menu("Recent \($0)", uses: 1, days: Double(40 + $0)) }
        let expired = menu("Expired", uses: 100, days: 200)
        let ordered = MenuCommand.ordered([expired] + recentFive, appID: "iterm", at: now)
        XCTAssertEqual(ordered.map(\.id), recentFive.map(\.id))
        XCTAssertEqual(MenuCommand.ordered([expired] + recentFive, appID: "iterm", at: now, includingHidden: true).first?.id, expired.id)
    }
    func testOnlyPinnedPeersOfSameAppHaveMoveTargetsAndSingletonHasNone() {
        let a = menu("A", uses: 1, pinned: true), b = menu("B", uses: 2, pinned: true)
        let frequent = menu("Frequent", uses: 8), recent = menu("Recent", uses: 1)
        let other = menu("Other", uses: 2, pinned: true, app: "other")
        let all = [frequent, a, other, recent, b]
        let targets = MenuCommand.pinnedMoveTargets(in: all)
        XCTAssertNil(targets[frequent.id]); XCTAssertNil(targets[recent.id])
        XCTAssertNil(targets[a.id]?.previous); XCTAssertEqual(targets[a.id]?.next, b.id)
        XCTAssertEqual(targets[b.id]?.previous, a.id); XCTAssertNil(targets[b.id]?.next)
        XCTAssertNil(targets[other.id]?.previous); XCTAssertNil(targets[other.id]?.next)
        XCTAssertNil(MenuCommand.pinnedMoveTarget(for: a.id, by: 1, in: [a, frequent]))
        XCTAssertEqual(MenuCommand.pinnedMoveTarget(for: a.id, by: 1, in: all), b.id)
        XCTAssertEqual(MenuCommand.pinnedMoveTarget(for: b.id, by: -1, in: all), a.id)
        for offset in [0, 2, Int.max, Int.min] {
            XCTAssertNil(MenuCommand.pinnedMoveTarget(for: a.id, by: offset, in: all))
        }
    }
}
