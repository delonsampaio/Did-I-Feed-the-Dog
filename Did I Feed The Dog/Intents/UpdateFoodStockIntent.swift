import AppIntents
import SwiftData
import WidgetKit

struct UpdateFoodStockIntent: AppIntent {
    static var title: LocalizedStringResource = "Update Food Stock"
    static var description = IntentDescription("Add portions to a dog's food stock after restocking")

    @Parameter(title: "Dog", requestValueDialog: IntentDialog("Which dog's food stock did you restock?"))
    var pet: PetEntity

    @Parameter(
        title: "Portions Added",
        description: "How many portions did you add?",
        requestValueDialog: IntentDialog("How many portions did you add?")
    )
    var portionsAdded: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$portionsAdded) portions for \(\.$pet)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard portionsAdded > 0 else {
            return .result(dialog: "Please provide a number greater than zero.")
        }

        switch AppSettings.stockMode {
        case .none:
            return .result(dialog: "Food stock tracking is turned off in the app.")
        case .shared:
            AppSettings.sharedFoodStock = min(9999, AppSettings.sharedFoodStock + portionsAdded)
            AppSettings.resetStockOutCount(petId: nil)
            WidgetCenter.shared.reloadAllTimelines()
            let total = AppSettings.sharedFoodStock
            let portionWord = total == 1 ? "portion" : "portions"
            return .result(dialog: "Updated. The shared pool now has \(total) \(portionWord) remaining.")
        case .individual:
            let context = ModelContext(sharedModelContainer)
            let pets = IntentDataAccess.fetchPets(in: context)
            guard let foundPet = pets.first(where: { $0.id == pet.id }) else {
                return .result(dialog: "Could not find \(pet.name).")
            }

            foundPet.foodStockCount = min(999, foundPet.foodStockCount + portionsAdded)
            AppSettings.resetStockOutCount(petId: foundPet.id)
            try? context.save()
            WidgetCenter.shared.reloadAllTimelines()

            let total = foundPet.foodStockCount
            let portionWord = total == 1 ? "portion" : "portions"
            return .result(dialog: "Updated. \(pet.name) now has \(total) \(portionWord) remaining.")
        }
    }
}
