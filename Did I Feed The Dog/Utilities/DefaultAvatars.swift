import Foundation

enum DefaultAvatars {
    static let all: [String] = [
        "AustralianShepherdAvatar",
        "BeagleAvatar",
        "BoxerAvatar",
        "ChihuahuaAvatar",
        "CorgiAvatar",
        "DobermanPincherAvatar",
        "DoxinAvatar",
        "FrenchBulldogAvatar",
        "GermanShepherdAvatar",
        "GoldenRetrieverAvatar",
        "GreatDaneAvatar",
        "HuskyAvatar",
        "PomeranianAvatar",
        "PoodleAvatar",
        "RottweilerAvatar",
        "ShibaInuAvatar",
        "ShihTzuAvatar",
        "SpanielAvatar"
    ]

    static func defaultFor(id: UUID) -> String {
        all[abs(id.hashValue) % all.count]
    }
}
