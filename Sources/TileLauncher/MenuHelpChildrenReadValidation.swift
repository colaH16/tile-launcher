#if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
import ApplicationServices
import CoreFoundation
import Darwin
import DeckCore
import Foundation

/// Exercises the same diagnostic-ON child reader used by the resolver. AX
/// handles are created locally as opaque values only: no AX messages, app
/// observation, actions, event monitors or production instance are involved.
enum MenuHelpChildrenReadValidation {
    private struct Fixture {
        var leafAllowed = false
        var limit = 100
        var countError = AXError.success
        var count: CFIndex = 2
        var canCopy = true
        var copyError = AXError.success
        var array: CFArray?
        var decodeFails = false
    }
    private enum ResultKind: Equatable { case values(Int), unavailable, failure }
    private struct Observation {
        let result: ResultKind
        let calls: [String]
        let reports: [MenuHelpChildrenRead.Trace]
    }

    private static func array(_ items: [AnyObject]) -> CFArray {
        var pointers: [UnsafeRawPointer?] = items.map { UnsafeRawPointer(Unmanaged.passUnretained($0).toOpaque()) }
        var callbacks = kCFTypeArrayCallBacks
        return pointers.withUnsafeMutableBufferPointer {
            CFArrayCreate(kCFAllocatorDefault, $0.baseAddress, $0.count, &callbacks)!
        }
    }

    private static func run(_ fixture: Fixture) -> Observation {
        var calls: [String] = []
        var reports: [MenuHelpChildrenRead.Trace] = []
        var index = 0
        let result = MenuHelpChildrenRead.read(leafAllowed: fixture.leafAllowed, limit: fixture.limit,
            count: { calls.append("count"); return (fixture.countError, fixture.count) },
            canCopy: { calls.append("canCopy"); return fixture.canCopy },
            copy: { requested in calls.append("copy:\(requested)"); return (fixture.copyError, fixture.array) },
            decode: { value in calls.append("decode"); return fixture.decodeFails ? nil : (value as? [AnyObject]) },
            isElement: { value in
                calls.append("element:\(index)"); index += 1
                return CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID()
            }, report: { reports.append($0); calls.append("report") })
        let kind: ResultKind
        switch result {
        case .value(let elements): kind = .values(elements.count)
        case .unavailable: kind = .unavailable
        case .failure: kind = .failure
        }
        return Observation(result: kind, calls: calls, reports: reports)
    }

    static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else {
                throw NSError(domain: "TileLauncher.MenuHelpChildrenReadValidation", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        func failed(_ observation: Observation, _ failure: MenuHelpChildrenRead.Failure,
                    result: ResultKind = .failure, calls: [String]) throws -> MenuHelpChildrenRead.Trace {
            try check(observation.result == result, "Diagnostic reader changed the child read outcome")
            try check(observation.calls == calls, "A failure added/reordered reads or continued after its first rejected stage")
            try check(observation.reports.count == 1, "Each failed child read must report exactly once")
            guard let trace = observation.reports.first else {
                throw NSError(domain: "TileLauncher.MenuHelpChildrenReadValidation", code: 2)
            }
            try check(trace.failure == failure, "Incorrect first failure stage")
            return trace
        }
        func noCopyFields(_ trace: MenuHelpChildrenRead.Trace) throws {
            try check(trace.copyErrorCode == nil && trace.requestedCount == nil
                      && trace.returnedCount == nil && trace.invalidIndex == nil,
                      "A child read reported data from a stage it never reached")
        }

        // These create handles without querying accessibility or another app.
        let handle = AXUIElementCreateApplication(getpid())
        let two = array([handle, handle])
        let one = array([handle])
        let three = array([handle, handle, handle])
        var fixture = Fixture(array: two)

        let success = run(fixture)
        try check(success.result == .values(2) && success.reports.isEmpty,
                  "A complete valid array must keep its normal successful outcome")
        try check(success.calls == ["count", "canCopy", "copy:2", "decode", "element:0", "element:1"],
                  "The successful child reader must issue only one count and one copy")

        fixture.count = 0
        let empty = run(fixture)
        try check(empty.result == .values(0) && empty.calls == ["count"] && empty.reports.isEmpty,
                  "An explicit empty child count must not copy, decode or report a failure")

        fixture = Fixture(countError: .attributeUnsupported, array: nil)
        fixture.leafAllowed = true
        let leaf = run(fixture)
        try check(leaf.result == .values(0) && leaf.calls == ["count"] && leaf.reports.isEmpty,
                  "Explicit unsupported children on a known menu item retain leaf compatibility")
        fixture.leafAllowed = false
        let unsupported = try failed(run(fixture), .countUnavailable, result: .unavailable, calls: ["count", "report"])
        try check(unsupported == .init(failure: .countUnavailable,
                                      countErrorCode: Int(AXError.attributeUnsupported.rawValue)),
                  "Unavailable children must report only the failing count error")
        try noCopyFields(unsupported)
        fixture.countError = .noValue; fixture.leafAllowed = true
        let absent = try failed(run(fixture), .countUnavailable, result: .unavailable, calls: ["count", "report"])
        try check(absent == .init(failure: .countUnavailable, countErrorCode: Int(AXError.noValue.rawValue)),
                  "noValue was confused with attributeUnsupported or reported an unread count")
        try noCopyFields(absent)

        fixture = Fixture(countError: .cannotComplete, count: -1, array: two)
        let countError = try failed(run(fixture), .countError, calls: ["count", "report"])
        try check(countError == .init(failure: .countError, countErrorCode: Int(AXError.cannotComplete.rawValue)),
                  "An error must not expose the invalid output count from its failed API call")
        try noCopyFields(countError)
        fixture.countError = .success
        let negative = try failed(run(fixture), .negativeCount, calls: ["count", "report"])
        try check(negative == .init(failure: .negativeCount, reportedCount: -1),
                  "A negative successful count must be distinct from an AX error")
        try noCopyFields(negative)

        fixture = Fixture(canCopy: false, array: two)
        let skipped = try failed(run(fixture), .copyNotAttempted, calls: ["count", "canCopy", "report"])
        try check(skipped == .init(failure: .copyNotAttempted, reportedCount: 2),
                  "An unattempted copy must retain only the preceding valid count")
        try noCopyFields(skipped)

        fixture = Fixture(copyError: .cannotComplete, array: nil)
        let copyError = try failed(run(fixture), .copyError, calls: ["count", "canCopy", "copy:2", "report"])
        try check(copyError == .init(failure: .copyError, copyErrorCode: Int(AXError.cannotComplete.rawValue),
                                    reportedCount: 2, requestedCount: 2),
                  "Copy errors must retain their actual request and AX error")
        try check(copyError.returnedCount == nil && copyError.invalidIndex == nil, "Failed copies have no decoded array")
        fixture.copyError = .success
        let missing = try failed(run(fixture), .missingArray, calls: ["count", "canCopy", "copy:2", "report"])
        try check(missing == .init(failure: .missingArray, reportedCount: 2, requestedCount: 2),
                  "A successful nil array is not an IPC error or a valid empty list")

        fixture = Fixture(array: two, decodeFails: true)
        let undecodable = try failed(run(fixture), .arrayDecode, calls: ["count", "canCopy", "copy:2", "decode", "report"])
        try check(undecodable == .init(failure: .arrayDecode, reportedCount: 2, requestedCount: 2),
                  "A failed decode must not inspect elements or invent a decoded count")

        fixture = Fixture(array: one)
        let mismatch = try failed(run(fixture), .countMismatch, calls: ["count", "canCopy", "copy:2", "decode", "report"])
        try check(mismatch == .init(failure: .countMismatch, reportedCount: 2, requestedCount: 2, returnedCount: 1),
                  "Array count mismatches must stop before any element type reads")

        fixture = Fixture(count: 3, array: array([handle, NSString(string: "private fixture value"), handle]))
        let badType = try failed(run(fixture), .elementType,
                                 calls: ["count", "canCopy", "copy:3", "decode", "element:0", "element:1", "report"])
        try check(badType == .init(failure: .elementType, reportedCount: 3, requestedCount: 3,
                                  returnedCount: 3, invalidIndex: 1),
                  "The first invalid element index must be reported without inspecting later elements")
        try check(!String(reflecting: badType).contains("private fixture value"),
                  "The trace must not retain or expose an AX array value")

        fixture = Fixture(limit: 2, count: 500, array: three)
        let limited = run(fixture)
        try check(limited.result == .values(3) && limited.reports.isEmpty,
                  "The reader must let the existing traversal reject cap+1 as childLimit")
        try check(limited.calls == ["count", "canCopy", "copy:3", "decode", "element:0", "element:1", "element:2"],
                  "An oversized count must request only the existing cap+1, never the full count")

        print("Menu Help children diagnostic: injected actual read path preserves query order and outcomes; count/copy errors, missing/decode/count/type failures and cap+1 distinguished without AX queries.")
    }
}
#endif
