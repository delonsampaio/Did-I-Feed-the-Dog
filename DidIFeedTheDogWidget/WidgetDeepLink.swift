import Foundation

// Single source of truth for the widget → app deep link. All widget views
// (small, medium, lock-screen rectangular) build the same URL; centralizing
// it here keeps the scheme + host wired up correctly in one place.
enum WidgetDeepLink {
    static let scheme = "didfeedthedog"
    static let host = "log"

    static func url(for petId: UUID) -> URL {
        // Force-unwrap is safe — the components below produce a known-valid URL.
        URL(string: "\(scheme)://\(host)?petId=\(petId.uuidString)")!
    }
}
