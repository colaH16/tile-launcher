import Foundation
import Carbon

/// Finder's application-level `trash` object represents the unified Trash.
/// A file URL for ~/.Trash opens only that volume's directory, even in Finder.
public enum FinderTrashRequest {
    public static func makeOpenEvent() throws -> NSAppleEventDescriptor {
        let property = NSAppleEventDescriptor.record()
        property.setDescriptor(NSAppleEventDescriptor(typeCode: OSType(cProperty)), forKeyword: AEKeyword(keyAEDesiredClass))
        property.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: AEKeyword(keyAEContainer))
        property.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        // `trsh` is Finder's read-only trash property, defined in Finder.sdef.
        property.setDescriptor(NSAppleEventDescriptor(typeCode: 0x74727368), forKeyword: AEKeyword(keyAEKeyData))
        guard let trash = property.coerce(toDescriptorType: DescType(typeObjectSpecifier)) else {
            throw NSError(domain: "TileLauncher.FinderTrash", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Finder 휴지통 열기 요청을 만들지 못했습니다."])
        }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                                          eventID: AEEventID(kAEOpenDocuments),
                                          targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder"),
                                          returnID: AEReturnID(kAutoGenerateReturnID),
                                          transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(trash, forKeyword: AEKeyword(keyDirectObject))
        return event
    }
}
