import Foundation

enum DefaultAvatars {
    static let all: [String] = [
        "AustralianShepherdAvatar",
        "Basset Hound Avatar",
        "BeagleAvatar",
        "Bernese Mountain Avatar",
        "Biewer Terrier Avatar",
        "Border Collie Avatar",
        "Boston Terrier Avatar",
        "BoxerAvatar",
        "Cane Corso Avatar",
        "ChihuahuaAvatar",
        "Collie Avatar",
        "CorgiAvatar",
        "DobermanPincherAvatar",
        "DoxinAvatar",
        "FrenchBulldogAvatar",
        "German Shorthaired Pointer Avatar",
        "GermanShepherdAvatar",
        "GoldenRetrieverAvatar",
        "GreatDaneAvatar",
        "Havanese Avatar",
        "HuskyAvatar",
        "Labrador Retriever Avatar",
        "Maltese Avatar",
        "Mastiff Avatar",
        "Miniature Schnauzer Avatar",
        "Newfoundland Avatar",
        "PomeranianAvatar",
        "PoodleAvatar",
        "Rhodesian Ridgeback Avatar",
        "RottweilerAvatar",
        "ShibaInuAvatar",
        "ShihTzuAvatar",
        "SpanielAvatar",
        "Vizsla Avatar",
        "Weimaraner Avatar",
        "West Highland White Terrier Avatar",
    ]

    static func defaultFor(id: UUID) -> String {
        all[abs(id.hashValue) % all.count]
    }
}
