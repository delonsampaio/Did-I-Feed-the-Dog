import Foundation
import UIKit

// Resolves the display name to attach to FeedingEvent.loggedBy. Reads the
// user-set name from AppStorage; falls back to UIDevice.current.name (which
// in iOS 16+ returns the model name like "iPhone" without a special
// entitlement, so the SettingsView field is how households disambiguate).
enum LoggedBy {
    static let storageKey = "loggedByName"

    static var current: String {
        let stored = UserDefaults.standard.string(forKey: storageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? UIDevice.current.name : stored
    }
}
