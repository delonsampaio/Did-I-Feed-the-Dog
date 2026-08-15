import CloudKit
import SwiftUI
import UIKit

/// Presents UICloudSharingController for an already-saved zone-wide CKShare. Locked to
/// read-write participants (no read-only or public toggle).
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    private let container = CKContainer(identifier: "iCloud.com.delon.DidIFeedTheDog.sharedsync")

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}

// `.sheet(item:)` requires `Identifiable`. SDK-header grep confirmed CKShare/CKRecord
// declare no such conformance (CKShare.h: `@interface CKShare : CKRecord <NSSecureCoding,
// NSCopying>`), and a build attempt without this extension confirmed it at compile time
// ("requires that 'CKShare' conform to 'Identifiable'"). A first attempt at
// `extension CKShare: Identifiable { var id: String { ... } }` alone failed with an
// ambiguous-witness error against the stdlib's `Identifiable where Self: AnyObject`
// default (`id: ObjectIdentifier`); pinning `ID` explicitly resolves the ambiguity.
extension CKShare: @retroactive Identifiable {
    public typealias ID = String
    public var id: String { recordID.recordName }
}
