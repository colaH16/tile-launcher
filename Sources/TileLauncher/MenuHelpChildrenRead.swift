#if TILE_LAUNCHER_MENU_CAPTURE_DIAGNOSTICS
import ApplicationServices
import CoreFoundation
import DeckCore
import Foundation

/// R368 diagnostic build only: the dev79 children read for the deferred Help
/// resolver, step for step, with the first non-success branch reported as a
/// typed trace. The decisions, order, short-circuits and AX calls are exactly
/// those of the flag-off `elements` body; the AX calls are supplied by the
/// caller. A trace carries only a branch, AX error codes, counts and an index —
/// never titles, values, objects or coordinates.
enum MenuHelpChildrenRead {
    enum Failure: String, Encodable, Equatable {
        /// AXUIElementGetAttributeValueCount returned another error.
        case countError
        /// The count call succeeded with a negative count.
        case negativeCount
        /// AXChildren unsupported/noValue where a leaf is not allowed.
        case countUnavailable
        /// The deadline or cancellation stopped the read before the copy.
        case copyNotAttempted
        /// AXUIElementCopyAttributeValues returned an error.
        case copyError
        /// The copy succeeded without an array.
        case missingArray
        /// The array could not be bridged to objects.
        case arrayDecode
        /// The bridged array did not have exactly the requested count.
        case countMismatch
        /// An item was not an AXUIElement.
        case elementType
    }
    struct Trace: Equatable {
        var failure: Failure
        var countErrorCode: Int? = nil
        var copyErrorCode: Int? = nil
        var reportedCount: Int? = nil
        var requestedCount: Int? = nil
        var returnedCount: Int? = nil
        var invalidIndex: Int? = nil
    }

    /// `report` is called at most once, only for a failure. A normal childless
    /// leaf (`MenuHelpChildrenPolicy.isUnsupportedLeaf`: attributeUnsupported on
    /// a known menu item, `leafAllowed`) and a zero count are not traced.
    static func read(leafAllowed: Bool, limit: Int,
                     count: () -> (AXError, CFIndex),
                     canCopy: () -> Bool,
                     copy: (CFIndex) -> (AXError, CFArray?),
                     decode: (CFArray) -> [AnyObject]? = { $0 as? [AnyObject] },
                     isElement: (AnyObject) -> Bool = { CFGetTypeID($0 as CFTypeRef) == AXUIElementGetTypeID() },
                     report: (Trace) -> Void) -> MenuCatalogTraversal.Read<[AXUIElement]> {
        let (countResult, reported) = count()
        if countResult == .attributeUnsupported || countResult == .noValue {
            // Same policy as the flag-off body: only an explicitly unsupported
            // AXChildren on a known menu item is a leaf; noValue is not.
            if MenuHelpChildrenPolicy.isUnsupportedLeaf(countResult, menuItem: leafAllowed) { return .value([]) }
            report(Trace(failure: .countUnavailable, countErrorCode: Int(countResult.rawValue)))
            return .unavailable
        }
        guard countResult == .success else {
            report(Trace(failure: .countError, countErrorCode: Int(countResult.rawValue)))
            return .failure
        }
        guard reported >= 0 else {
            report(Trace(failure: .negativeCount, reportedCount: Int(reported)))
            return .failure
        }
        if reported == 0 { return .value([]) }
        guard canCopy() else {
            report(Trace(failure: .copyNotAttempted, reportedCount: Int(reported)))
            return .failure
        }
        // Beyond the cap, only cap + 1 is fetched so the traversal reports childLimit.
        let requested = min(reported, CFIndex(limit + 1))
        let (copyResult, values) = copy(requested)
        guard copyResult == .success else {
            report(Trace(failure: .copyError, copyErrorCode: Int(copyResult.rawValue),
                         reportedCount: Int(reported), requestedCount: Int(requested)))
            return .failure
        }
        guard let values else {
            report(Trace(failure: .missingArray, reportedCount: Int(reported), requestedCount: Int(requested)))
            return .failure
        }
        guard let items = decode(values) else {
            report(Trace(failure: .arrayDecode, reportedCount: Int(reported), requestedCount: Int(requested)))
            return .failure
        }
        guard items.count == requested else {
            report(Trace(failure: .countMismatch, reportedCount: Int(reported), requestedCount: Int(requested),
                         returnedCount: items.count))
            return .failure
        }
        var children: [AXUIElement] = []
        children.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            // Never cast an item the predicate rejected.
            guard isElement(item) else {
                report(Trace(failure: .elementType, reportedCount: Int(reported), requestedCount: Int(requested),
                             returnedCount: items.count, invalidIndex: index))
                return .failure
            }
            children.append(item as! AXUIElement)
        }
        return .value(children)
    }
}
#endif
