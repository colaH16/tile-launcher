import XCTest
@testable import DeckCore

final class MenuResolutionTests: XCTestCase {
    func testProfileAlternateRequiresExactlyOneMatchingSavedShortcut() {
        let labels = [0:"", 1:"Profiles", 2:"fish", 3:"fish"]
        let tree = [0:[1], 1:[2,3]]
        var shortcuts: [Int: MenuShortcut] = [2: MenuShortcut(key: "x", modifiers: 4)!,
                                             3: MenuShortcut(key: "x", modifiers: 6)!]
        var unreadable: Int?
        func resolve(_ saved: MenuShortcut?) -> MenuPathResolution<Int> {
            MenuPathResolver.resolve(paths: [["Profiles", "fish"]], root: 0,
                children: { tree[$0] ?? [] }, title: { labels[$0] }, equal: ==,
                preferredShortcut: saved, shortcut: { (shortcuts[$0], $0 != unreadable) })
        }
        let normal = MenuShortcut(key: "X", modifiers: 4)!
        if case .found(let node) = resolve(normal) { XCTAssertEqual(node, 2) } else { XCTFail() }
        if case .found(let node) = resolve(shortcuts[3]) { XCTAssertEqual(node, 3) } else { XCTFail() }
        guard case .ambiguous = resolve(nil) else { return XCTFail("No saved equivalent must not guess") }
        guard case .ambiguous = resolve(MenuShortcut(key: "z", modifiers: 4)) else { return XCTFail("Stale equivalent must not guess") }
        unreadable = 3
        guard case .unavailable = resolve(normal) else { return XCTFail("Unreadable alternate must not be ignored") }
        unreadable = nil
        shortcuts[3] = normal
        guard case .ambiguous = resolve(normal) else { return XCTFail("Two matching actions must remain blocked") }
    }
    func testRepeatedReferenceIsOneActionAndParentDuplicatesStayAmbiguous() {
        let labels = [0:"", 1:"Profiles", 2:"fish", 3:"Profiles"]
        var tree = [0:[1,1], 1:[2,2]]
        var reads = 0
        func resolve() -> MenuPathResolution<Int> {
            MenuPathResolver.resolve(paths: [["Profiles", "fish"]], root: 0,
                children: { tree[$0] ?? [] }, title: { labels[$0] }, equal: ==,
                preferredShortcut: MenuShortcut(key: "X", modifiers: 4), shortcut: { _ in reads += 1; return (nil, true) })
        }
        if case .found(let node) = resolve() { XCTAssertEqual(node, 2) } else { XCTFail() }
        XCTAssertEqual(reads, 0)
        tree[0] = [1,3]
        guard case .ambiguous = resolve() else { return XCTFail("Leaf equivalent cannot choose a parent") }
        XCTAssertEqual(reads, 0)
    }
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
