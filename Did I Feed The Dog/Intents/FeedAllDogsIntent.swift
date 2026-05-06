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
        When(\.$mealType, .hasValue) {
            Summary("Log \(\.$mealType) for all dogs")
        } otherwise: {
            Summary("Log feeding for all dogs")
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = sharedModelContainer.mainContext
        let allPets = IntentDataAccess.fetchPets(in: context)
        let eligiblePets = allPets.filter { !$0.isFasting }

        guard !eligiblePets.isEmpty else {
            if allPets.isEmpty {
                return .result(dialog: "You haven't added any dogs yet.")
            } else {
                return .result(dialog: "All your dogs are currently fasting.")
            }
        }

        // When the user doesn't specify a meal ("Feed all dogs"), pick a real
        // preset based on time of day so history rows aren't tagged "Meal"/Custom.
        let resolvedMeal = mealType ?? MealTypeAppEnum.defaultForCurrentTime()

        let result = FeedingLogService.logFeedingForAll(
            pets: eligiblePets,
            mealLabel: resolvedMeal.label,
            deductsStock: resolvedMeal.deductsStock,
            logger: LoggedBy.current,
            in: context
        )

        let count = result.events.count
        let dogWord = count == 1 ? "dog" : "dogs"
        var dialogMessage = "Logged \(resolvedMeal.label) for \(count) \(dogWord)."

        if result.didTriggerLowStock {
            dialogMessage += " Note, food stock is running low!"
        } else if AppSettings.stockMode == .shared && resolvedMeal.deductsStock {
            let remaining = AppSettings.sharedFoodStock
            dialogMessage += " The shared pool has \(remaining) portion\(remaining == 1 ? "" : "s") remaining."
        }

        return .result(dialog: IntentDialog(stringLiteral: dialogMessage))
    }
}
