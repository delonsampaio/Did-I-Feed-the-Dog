import Foundation

enum SharingFeatureFlag {
    /// Phase 1 foundation: render shared dogs on the dashboard. Default off in release.
    static var isFoundationEnabled: Bool {
        UserDefaults.sharedGroup.bool(forKey: "sharingFoundationEnabled")
    }
}
