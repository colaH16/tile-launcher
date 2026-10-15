import XCTest
@testable import DeckCore

final class MenuResolutionTests: XCTestCase {
    func testResolverDoesNotMixParentsAndLeavesAcrossLanguages() {
        let labels = [0:"", 1:"파일", 2:"開く"]
        let children = [0:[1], 1:[2]]
        let result = MenuPathResolver.resolve(paths: [["File","Open"], ["파일","열기"], ["ファイル","開く"]], root: 0,
            children: { children[$0] ?? [] }, title: { labels[$0] }, equal: ==)
        guard case .missing = result else { return XCTFail("Mixed-language path was accepted") }
    }
    func testOriginalPathWinsAndAmbiguousPathsOrReadErrorsNeverExecute() {
        let labels = [0:"", 1:"File", 2:"Open", 3:"Open", 4:"파일", 5:"열기"]
        let paths = [["File","Open"], ["파일","열기"]]
        var tree = [0:[1,4], 1:[2], 4:[5]]
        func resolve() -> MenuPathResolution<Int> {
            MenuPathResolver.resolve(paths: paths, root: 0, children: { tree[$0] ?? [] }, title: { labels[$0] }, equal: ==)
        }
        if case .found(let target) = resolve() { XCTAssertEqual(target, 2) } else { XCTFail() }
        tree[1] = [2,3]
        guard case .ambiguous = resolve() else { return XCTFail("Duplicate exact path accepted") }
        let failed = MenuPathResolver.resolve(paths: paths, root: 0, children: { _ in nil as [Int]? }, title: { labels[$0] }, equal: ==)
        guard case .unavailable = failed else { return XCTFail("Read failure treated as absence") }
    }
    func testExclusionKeepsEveryVerifiedWholePathButNotAnotherMenu() {
        var command = MenuCommand(appID: "app", appName: "App", path: ["File", "Open"])
        command.resourceBinding = .init(identity: .init(appID: "app", archive: "Main.nib", keys: ["File", "document.open"]),
            paths: [["File", "Open"], ["파일", "문서 열기"]])
        var preferences = MenuCapturePreferences()
        preferences.excludedMenus.formUnion(MenuPathMatch.paths(command).map { MenuIdentity(appID: command.appID, path: $0) })
        XCTAssertFalse(MenuCapturePolicy.allows(CapturedMenu(appID: "app", appName: "App", path: ["파일", "문서 열기"]), preferences: preferences))
        XCTAssertTrue(MenuCapturePolicy.allows(CapturedMenu(appID: "app", appName: "App", path: ["Project", "Open"]), preferences: preferences))
        XCTAssertTrue(MenuCapturePolicy.allows(CapturedMenu(appID: "another", appName: "Another", path: ["File", "Open"]), preferences: preferences))
    }
    func testRetriesAreBoundedAndRecoveryResetsTheBudget() {
        var budget = AXReadRetryBudget()
        XCTAssertEqual(budget.nextDelay(), 0.35)
        XCTAssertEqual(budget.nextDelay(), 1)
        XCTAssertNil(budget.nextDelay())
        XCTAssertNil(budget.nextDelay())
        budget.reset()
        XCTAssertEqual(budget.nextDelay(), 0.35)
    }
}
