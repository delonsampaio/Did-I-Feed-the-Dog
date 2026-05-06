import AppIntents
import SwiftData
import Foundation

struct LogFeedingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Feeding"
    static var description = IntentDescription("Quickly log a meal for one of your dogs.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Dog", requestValueDialog: IntentDialog("Which dog did you feed?"))
    var pet: PetEntity

    @Parameter(title: "Meal Type")
    var mealType: MealTypeAppEnum?

    static var parameterSummary: some ParameterSummary {
        When(\.$mealType, .hasAnyValue) {
            Summary("Log \(\.$mealType) for \(\.$pet)")
        } otherwise: {
            Summary("Log feeding for \(\.$pet)")
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = sharedModelContainer.mainContext

        guard let modelPet = IntentDataAccess.fetchPets(in: context).first(where: { $0.id == pet.id }) else {
            return .result(dialog: "Couldn't find \(pet.name) in the app.")
        }

        if modelPet.isFasting {
            return .result(dialog: "\(modelPet.name ?? "That dog") is currently fasting and can't be fed.")
        }

        let resolvedMeal = mealType ?? MealTypeAppEnum.defaultForCurrentTime()

        let result = FeedingLogService.logFeeding(
            for: modelPet,
            mealLabel: resolvedMeal.label,
            deductsStock: resolvedMeal.deductsStock,
            logger: LoggedBy.current,
            in: context
        )

        var dialogMessage = "Logged \(resolvedMeal.label) for \(modelPet.name ?? "your dog")."
        
        if result.didTriggerLowStock {
            dialogMessage += " Note, food stock is running low!"
        } else if AppSettings.stockMode != .none && resolvedMeal.deductsStock {
            let remaining = AppSettings.stockMode == .shared ? AppSettings.sharedFoodStock : modelPet.foodStockCount
            dialogMessage += " \(remaining) portion\(remaining == 1 ? "" : "s") remaining."
        }

        return .result(dialog: IntentDialog(stringLiteral: dialogMessage))
    }
}
