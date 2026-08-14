import SwiftUI
import UIKit
import CloudKit
import os

extension Notification.Name {
    static let quickActionTriggered = Notification.Name("quickActionTriggered")
    static let didAcceptShare = Notification.Name("didAcceptShare")
}

final class QuickActionManager {
    static let shared = QuickActionManager()
    var pendingPetId: String?
    private init() {}
    
    func update(with pets: [Pet]) {
        // iOS limits Home Screen Quick Actions to 4 items maximum
        UIApplication.shared.shortcutItems = pets.prefix(4).map { pet in
            UIApplicationShortcutItem(
                type: "logFeeding",
                localizedTitle: "Log \(pet.name ?? "Dog")'s Meal",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "fork.knife"),
                userInfo: ["petId": pet.id.uuidString as NSString]
            )
        }
    }
}

// MARK: - Modern SwiftUI Bridging

class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

class QuickActionSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        handle(shortcutItem: shortcutItem)
        completionHandler(true)
    }
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let shortcutItem = connectionOptions.shortcutItem {
            handle(shortcutItem: shortcutItem)
        }

        if let meta = connectionOptions.cloudKitShareMetadata {
            acceptShare(meta)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        acceptShare(cloudKitShareMetadata)
    }

    private func acceptShare(_ metadata: CKShare.Metadata) {
        guard SharingFeatureFlag.isFoundationEnabled else { return }
        let container = CKContainer(identifier: "iCloud.com.delon.DidIFeedTheDog.sharedsync")
        let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
        op.acceptSharesResultBlock = { result in
            switch result {
            case .success:
                Task { @MainActor in
                    await SharedSyncEngine.shared.fetchAllZones()
                    NotificationCenter.default.post(name: .didAcceptShare, object: nil)
                }
            case .failure(let error):
                Logger(subsystem: "com.delon.DidIFeedTheDog", category: "ShareAccept")
                    .error("acceptShare failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        container.add(op)
    }

    private func handle(shortcutItem: UIApplicationShortcutItem) {
        guard shortcutItem.type == "logFeeding",
              let petIdString = shortcutItem.userInfo?["petId"] as? String else { return }

        QuickActionManager.shared.pendingPetId = petIdString
        NotificationCenter.default.post(name: .quickActionTriggered, object: nil, userInfo: ["petId": petIdString])
    }
}