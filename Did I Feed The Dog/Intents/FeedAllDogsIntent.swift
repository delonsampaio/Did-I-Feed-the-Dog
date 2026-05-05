import AppIntents
import SwiftData
import Foundation

struct FeedAllDogsIntent: AppIntent {
    static var title: LocalizedStringResource = "Feed All Dogs"
    static var description = IntentDescription("Log a meal for all your dogs at once. Fasting dogs are skipped.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Meal Type")
    var mealType: MealTypeAppEnum?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$mealType) for all dogs")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = sharedModelContainer.mainContext
        let loggedByName = UserDefaults.standard.string(forKey: "loggedByName") ?? "Family Member"

        let allPets = IntentDataAccess.fetchPets(in: context)
        let eligiblePets = allPets.filter { !$0.isFasting }

        guard !eligiblePets.isEmpty else {
            if allPets.isEmpty {
                return .result(dialog: "You haven't added any dogs yet.")
            } else {
                return .result(dialog: "All your dogs are currently fasting.")
            }
        }

        let label = mealType?.rawValue ?? "Meal"
        let stockModeRaw = UserDefaults.standard.string(forKey: "stockMode") ?? ""
        let stockMode = StockMode(rawValue: stockModeRaw) ?? .none

        for pet in eligiblePets {
            let event = FeedingEvent(
                timestamp: .now,
                mealType: label,
                notes: "",
                loggedBy: loggedByName,
                pet: pet
            )
            context.insert(event)

            if stockMode == .individual {
                pet.decrementStock()
            }

            NotificationManager.shared.scheduleOverdueNotification(for: pet, lastFedDate: .now)
        }

        if stockMode == .shared {
            let current = UserDefaults.standard.integer(forKey: "sharedFoodStock")
            UserDefaults.standard.set(max(0, current - eligiblePets.count), forKey: "sharedFoodStock")
        }

        WidgetDataWriter.write(from: context)
        try context.save()

        let count = eligiblePets.count
        let dogWord = count == 1 ? "dog" : "dogs"
        return .result(dialog: "Logged \(label) for \(count) \(dogWord).")
    }
}
