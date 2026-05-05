import AppIntents
import SwiftData

struct UpdateFoodStockIntent: AppIntent {
    static var title: LocalizedStringResource = "Update Food Stock"
    static var description = IntentDescription("Add portions to your dog food stock after restocking.")

    @Parameter(title: "Dog", requestValueDialog: IntentDialog("Which dog's food stock would you like to update?"))
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

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard portionsAdded > 0 else {
            return .result(dialog: "Please provide a number greater than zero.")
        }

        switch AppSettings.stockMode {
        case .none:
            return .result(dialog: "Food stock tracking is turned off in the app. Turn it on in Settings → Food Stock to use this with Siri.")

        case .shared:
            // In shared mode, ignore the per-dog parameter — there's one pool.
            let current = AppSettings.sharedFoodStock
            let newTotal = min(AppConstants.sharedStockCap, current + portionsAdded)
            let actuallyAdded = newTotal - current
            AppSettings.sharedFoodStock = newTotal
            WidgetDataWriter.write(from: sharedModelContainer.mainContext)

            let portionWord = newTotal == 1 ? "portion" : "portions"
            if actuallyAdded < portionsAdded {
                return .result(dialog: "I capped the shared food pool at \(newTotal) \(portionWord). The maximum is \(AppConstants.sharedStockCap).")
            }
            return .result(dialog: "Updated. The shared food pool now has \(newTotal) \(portionWord) remaining.")

        case .individual:
            let context = sharedModelContainer.mainContext
            guard let foundPet = IntentDataAccess.fetchPets(in: context).first(where: { $0.id == pet.id }) else {
                return .result(dialog: "Couldn't find \(pet.name).")
            }

            let before = foundPet.foodStockCount
            let newTotal = min(AppConstants.perPetStockCap, before + portionsAdded)
            let actuallyAdded = newTotal - before
            foundPet.foodStockCount = newTotal
            try context.save()
            WidgetDataWriter.write(from: context)

            let portionWord = newTotal == 1 ? "portion" : "portions"
            if actuallyAdded < portionsAdded {
                return .result(dialog: "I capped \(foundPet.name ?? "their") stock at \(newTotal) \(portionWord). The maximum per dog is \(AppConstants.perPetStockCap).")
            }
            return .result(dialog: "Updated. \(foundPet.name ?? pet.name) now has \(newTotal) \(portionWord) remaining.")
        }
    }
}
