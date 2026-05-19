import AppIntents
import SwiftData
import Foundation

struct FeedAllDogsIntent: AppIntent {
    static var title: LocalizedStringResource = "Feed All Dogs"
    static var description = IntentDescription("Log a meal for all your dogs at once. Fasting dogs are skipped.")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Meal Type",
        requestValueDialog: IntentDialog("What type of meal is this?")
    )
    var mealType: MealTypeAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$mealType) for all dogs")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(sharedModelContainer)
        let allPets = IntentDataAccess.fetchPets(in: context)
        let eligiblePets = allPets.filter { !$0.isFasting }

        guard !eligiblePets.isEmpty else {
            if allPets.isEmpty {
                return .result(dialog: "You haven't added any dogs yet.")
            } else {
                return .result(dialog: "All your dogs are currently fasting.")
            }
        }

        let result = await logFeedingForAllOnBackground(
            pets: eligiblePets,
            mealLabel: mealType.label,
            deductsStock: mealType.deductsStock,
            in: context
        )

        let count = result.events.count
        let dogWord = count == 1 ? "dog" : "dogs"
        var dialogMessage = "Logged \(mealType.label) for \(count) \(dogWord)."

        if mealType.deductsStock {
            switch AppSettings.stockMode {
            case .shared:
                let remaining = AppSettings.sharedFoodStock
                if remaining == 0 {
                    dialogMessage += " Heads up, the shared pool is out of food — time to open a new bag!"
                } else if result.didTriggerLowStock {
                    dialogMessage += " Note, the shared pool is running low — \(remaining) portion\(remaining == 1 ? "" : "s") left."
                } else {
                    dialogMessage += " The shared pool has \(remaining) portion\(remaining == 1 ? "" : "s") remaining."
                }
            case .individual:
                if !result.petsAtZeroStock.isEmpty {
                    let names = result.petsAtZeroStock.compactMap { $0.name }.joined(separator: ", ")
                    let verb = result.petsAtZeroStock.count == 1 ? "is" : "are"
                    dialogMessage += " Heads up, \(names) \(verb) out of food — time to open a new bag!"
                } else if result.didTriggerLowStock {
                    dialogMessage += " Note, food stock is running low for one or more dogs."
                }
            case .none:
                break
            }
        }

        return .result(dialog: IntentDialog(stringLiteral: dialogMessage))
    }

    @MainActor
    private func logFeedingForAllOnBackground(
        pets: [Pet],
        mealLabel: String,
        deductsStock: Bool,
        in context: ModelContext
    ) async -> FeedingLogService.BatchResult {
        FeedingLogService.logFeedingForAll(
            pets: pets,
            mealLabel: mealLabel,
            deductsStock: deductsStock,
            logger: LoggedBy.current,
            in: context
        )
    }
}
