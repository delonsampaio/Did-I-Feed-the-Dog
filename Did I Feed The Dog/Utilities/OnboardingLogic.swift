import Foundation

/// Pure decision logic for the onboarding flow, extracted so it can be unit-tested
/// independently of the SwiftUI view.
///
/// Background: on a reinstall, the user's dogs sync down from CloudKit asynchronously.
/// A returning user must not be asked to re-add dogs they already have, and any name
/// typed during the cold-start race must never be silently dropped by the free-tier cap.
enum OnboardingLogic {

    /// The dog names onboarding should create.
    ///
    /// - Returning users (`existingDogCount > 0`) add nothing: they already have their
    ///   dogs, so onboarding only collects their name. This also defuses the cold-start
    ///   race where a user types a dog before iCloud sync completes.
    /// - New users get their typed names, trimmed, deduplicated case-insensitively, and
    ///   capped to the free-tier limit of one dog unless Pro.
    static func dogNamesToInsert(typed: [String], existingDogCount: Int, isPro: Bool) -> [String] {
        guard existingDogCount == 0 else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for raw in typed {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            if !isPro && result.count >= 1 { break }
            result.append(trimmed)
        }
        return result
    }

    /// Whether the user may advance past the add-dog step.
    /// Returning users can always continue (the dog name is replaced by an optional
    /// "your name" field); new users must enter at least one dog name.
    static func canLeaveAddDogStep(hasExistingDogs: Bool, hasTypedDogName: Bool) -> Bool {
        hasExistingDogs || hasTypedDogName
    }
}
