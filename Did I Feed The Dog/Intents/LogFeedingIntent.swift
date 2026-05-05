import AppIntents
import SwiftData
import Foundation

struct LogFeedingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Feeding"
    static var description = IntentDescription("Quickly log a meal for one of your dogs.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Dog", requestValueDialog: IntentDialog("Which dog did you feed?"))
    var pet: PetEntity

    @Parameter(title: "Meal Type", requestValueDialog: IntentDialog("What type of meal?"))
    var mealType: MealTypeAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$mealType) for \(\.$pet)")
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

        _ = FeedingLogService.logFeeding(
            for: modelPet,
            mealLabel: mealType.label,
            deductsStock: mealType.deductsStock,
            logger: LoggedBy.current,
            in: context
        )

        return .result(dialog: "Logged \(mealType.label) for \(modelPet.name ?? "your dog").")
    }
}
