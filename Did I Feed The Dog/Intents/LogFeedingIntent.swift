import AppIntents
import SwiftData
import Foundation

struct LogFeedingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Feeding"
    static var description = IntentDescription("Quickly log a meal for one of your dogs.")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Dog",
        requestValueDialog: IntentDialog("Which dog did you feed?")
    )
    var pet: PetEntity

    @Parameter(
        title: "Meal Type",
        requestValueDialog: IntentDialog("What type of meal is this?")
    )
    var mealType: MealTypeAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$mealType) for \(\.$pet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard EntitlementManager.shared.isPro else {
            return .result(dialog: "This feature requires Did I Feed the Dog Pro. Open the app to upgrade.")
        }
        let context = sharedModelContainer.mainContext

        guard let modelPet = IntentDataAccess.fetchPets(in: context).first(where: { $0.id == pet.id }) else {
            return .result(dialog: "Couldn't find \(pet.name) in the app.")
        }

        if modelPet.isFasting {
            return .result(dialog: "\(modelPet.name ?? "That dog") is currently fasting and can't be fed.")
        }

        let result: FeedingLogService.LogResult
        do {
            result = try FeedingLogService.logFeeding(
                for: modelPet,
                mealLabel: mealType.label,
                deductsStock: mealType.deductsStock,
                logger: LoggedBy.current,
                in: context
            )
        } catch {
            return .result(dialog: "Failed to save meal. Please try again or open the app.")
        }

        var dialogMessage = "Logged \(mealType.label) for \(modelPet.name ?? "your dog")."

        if AppSettings.stockMode != .none && mealType.deductsStock {
            let remaining = AppSettings.stockMode == .shared ? AppSettings.sharedFoodStock : modelPet.foodStockCount
            let scopeLabel = AppSettings.stockMode == .shared ? "the shared pool is" : "\(modelPet.name ?? "your dog") is"
            if remaining == 0 {
                dialogMessage += " Heads up, \(scopeLabel) out of food — time to open a new bag!"
            } else if result.didTriggerLowStock {
                dialogMessage += " Note, food stock is running low — \(remaining) portion\(remaining == 1 ? "" : "s") left."
            } else {
                dialogMessage += " \(remaining) portion\(remaining == 1 ? "" : "s") remaining."
            }
        }

        return .result(dialog: IntentDialog(stringLiteral: dialogMessage))
    }
}
