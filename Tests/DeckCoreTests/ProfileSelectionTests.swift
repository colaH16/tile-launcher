import XCTest
@testable import DeckCore

final class ProfileSelectionTests: XCTestCase {
    private let basic = LauncherProfile(id: "default", name: "Work")
    private let manual = LauncherProfile(id: "manual", name: "Manual")
    private let work = LauncherProfile(id: "work", name: "기본")
    private var profiles: [LauncherProfile] { [basic, manual, work] }

    func testAutomaticFallbackAndManualSelectionAreIndependentRoles() throws {
        for focus in [nil, "missing", "default"] as [String?] {
            let result = try XCTUnwrap(ProfileSelection.resolve(profiles: profiles, defaultProfileID: basic.id,
                manualProfileID: manual.id, focusProfileID: focus, followFocus: true))
            XCTAssertEqual(result.profile.id, basic.id)
            XCTAssertEqual(result.reason, .defaultProfile)
        }
        let automatic = try XCTUnwrap(ProfileSelection.resolve(profiles: profiles, defaultProfileID: basic.id,
            manualProfileID: manual.id, focusProfileID: work.id, followFocus: true))
        XCTAssertEqual(automatic.profile.id, work.id)
        XCTAssertEqual(automatic.reason, .focus)
        for focus in [nil, "missing", work.id, basic.id] as [String?] {
            let result = try XCTUnwrap(ProfileSelection.resolve(profiles: profiles, defaultProfileID: basic.id,
                manualProfileID: manual.id, focusProfileID: focus, followFocus: false))
            XCTAssertEqual(result.profile.id, manual.id)
            XCTAssertEqual(result.reason, .manual)
        }
        XCTAssertEqual(ProfileSelection.resolve(profiles: profiles, defaultProfileID: basic.id,
            manualProfileID: "missing", focusProfileID: work.id, followFocus: false)?.profile.id, basic.id)
        XCTAssertNil(ProfileSelection.resolve(profiles: [], defaultProfileID: basic.id,
            manualProfileID: manual.id, focusProfileID: nil, followFocus: true))
    }

    func testEligibilityUsesCurrentRoleRatherThanNameOrFormerDefaultIdentity() {
        XCTAssertFalse(ProfileSelection.isEligibleForFocus(basic.id, profiles: profiles, defaultProfileID: basic.id))
        XCTAssertTrue(ProfileSelection.isEligibleForFocus(work.id, profiles: profiles, defaultProfileID: basic.id))
        XCTAssertTrue(ProfileSelection.isEligibleForFocus(basic.id, profiles: profiles, defaultProfileID: work.id))
        XCTAssertNil(ProfileSelection.normalizedFocusID(work.id, profiles: profiles, defaultProfileID: work.id))
        XCTAssertNil(ProfileSelection.normalizedFocusID("missing", profiles: profiles, defaultProfileID: basic.id))
        XCTAssertNil(ProfileSelection.normalizedFocusID(nil, profiles: profiles, defaultProfileID: basic.id))
        XCTAssertEqual(ProfileSelection.resolve(profiles: profiles, defaultProfileID: work.id,
            manualProfileID: manual.id, focusProfileID: basic.id, followFocus: true)?.profile.id, basic.id)
    }

    func testLegacyMigrationPrefersCanonicalOverManualWithoutTakingWorkOutOfFocus() throws {
        let ordered = [work, manual, basic]
        for stored in [nil, "deleted"] as [String?] {
            let restored = ProfileCatalog.restore(profilesData: try JSONEncoder().encode(ordered), legacyPinsData: nil,
                                                  storedDefaultID: stored, storedManualID: work.id)
            XCTAssertEqual(restored.profiles, ordered)
            XCTAssertEqual(restored.defaultProfileID, "default")
            XCTAssertEqual(restored.manualProfileID, "work")
            XCTAssertTrue(ProfileSelection.isEligibleForFocus(work.id, profiles: restored.profiles,
                                                             defaultProfileID: restored.defaultProfileID))
        }
        let explicit = ProfileCatalog.restore(profilesData: try JSONEncoder().encode(ordered), legacyPinsData: nil,
                                               storedDefaultID: manual.id, storedManualID: work.id)
        XCTAssertEqual(explicit.defaultProfileID, manual.id)
        XCTAssertEqual(explicit.manualProfileID, work.id)
        XCTAssertEqual(explicit.profiles, ordered)
    }

    func testMissingCanonicalMigrationCopiesOldFallbackAndIsIdempotent() throws {
        let folder = PinnedItem(kind: .folder, path: "/Synthetic/Folder", bundleID: nil, name: "Folder", openMode: .finder)
        let old = [LauncherProfile(id: "oma", name: "기본", items: [folder]), work]
        let first = ProfileCatalog.restore(profilesData: try JSONEncoder().encode(old), legacyPinsData: nil,
                                           storedDefaultID: nil, storedManualID: "oma")
        XCTAssertEqual(Array(first.profiles.prefix(2)), old)
        XCTAssertEqual(first.profiles.last, LauncherProfile(id: "default", name: "기본", items: [folder]))
        XCTAssertEqual(first.defaultProfileID, "default")
        XCTAssertEqual(first.manualProfileID, "oma")
        XCTAssertTrue(ProfileSelection.isEligibleForFocus("oma", profiles: first.profiles, defaultProfileID: first.defaultProfileID))
        let second = ProfileCatalog.restore(profilesData: try JSONEncoder().encode(first.profiles), legacyPinsData: nil,
                                            storedDefaultID: first.defaultProfileID, storedManualID: first.manualProfileID)
        XCTAssertEqual(second, first, "Repeated init cannot duplicate the synthesized default or rewrite old references")
        let missingManual = ProfileCatalog.restore(profilesData: try JSONEncoder().encode(old), legacyPinsData: nil,
                                                   storedDefaultID: nil, storedManualID: "deleted")
        XCTAssertEqual(missingManual.manualProfileID, "default")
        XCTAssertEqual(missingManual.profiles.last?.items, old[0].items)
    }

    func testDefaultAndManualDraftFieldsMergeIndependentlyAndValidateBothTargets() throws {
        let base = RegisteredSettingsDraft(profiles: profiles, defaultProfileID: basic.id, manualProfileID: manual.id, followsFocus: true)
        var edit = base; edit.defaultProfileID = work.id
        var live = base; live.manualProfileID = basic.id
        let merged = try edit.rebased(from: base, onto: live)
        XCTAssertEqual(merged.defaultProfileID, work.id)
        XCTAssertEqual(merged.manualProfileID, basic.id)
        XCTAssertTrue(merged.followsFocus)
        edit = base; edit.profiles.removeAll { $0.id == work.id }
        live = base; live.defaultProfileID = work.id
        XCTAssertThrowsError(try edit.rebased(from: base, onto: live), "A concurrently selected default must not silently vanish")
        edit = base; edit.profiles.removeAll { $0.id == manual.id }
        XCTAssertThrowsError(try edit.rebased(from: base, onto: base), "A missing manual role needs an explicit valid replacement")
    }
}
