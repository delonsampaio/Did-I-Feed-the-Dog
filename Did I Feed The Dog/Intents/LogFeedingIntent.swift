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
        Summary("Log \(\.$mealType) for \(\.$pet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = sharedModelContainer.mainContext

        let loggedByName = UserDefaults.standard.string(forKey: "loggedByName") ?? "Family Member"

        guard let modelPet = IntentDataAccess.fetchPets(in: context).first(where: { $0.id == pet.id }) else {
            return .result(dialog: "Couldn't find \(pet.name) in the app.")
        }
        
        let label = mealType?.rawValue ?? "Meal"
        
        // Corrected 'timestamp' argument to match FeedingEvent.swift
        let event = FeedingEvent(
            timestamp: .now,
            mealType: label,
            notes: "",
            loggedBy: loggedByName,
            pet: modelPet
        )
        
        context.insert(event)
        
        let stockModeRaw = UserDefaults.standard.string(forKey: "stockMode") ?? ""
        switch StockMode(rawValue: stockModeRaw) ?? .none {
        case .individual:
            modelPet.decrementStock()
        case .shared:
            let current = UserDefaults.standard.integer(forKey: "sharedFoodStock")
            UserDefaults.standard.set(max(0, current - 1), forKey: "sharedFoodStock")
        case .none:
            break
        }

        NotificationManager.shared.scheduleOverdueNotification(for: modelPet, lastFedDate: .now)
        WidgetDataWriter.write(from: context)
        
        try context.save()
        
        return .result(dialog: "Logged \(label) for \(modelPet.name ?? "your dog").")
    }
}