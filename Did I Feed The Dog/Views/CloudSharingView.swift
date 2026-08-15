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

extension CKShare: @retroactive Identifiable {
    public typealias ID = String
    public var id: String { recordID.recordName }
}
