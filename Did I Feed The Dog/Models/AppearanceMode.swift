import SwiftUI
import UIKit

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    func apply() {
        let style: UIUserInterfaceStyle = switch self {
        case .system: .unspecified
        case .light:  .light
        case .dark:   .dark
        }
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach { $0.overrideUserInterfaceStyle = style }
    }
}
