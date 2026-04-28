import AppIntents

struct DogFoodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFeedingIntent(),
            phrases: [
                "Log \(\.$pet)'s feeding in \(.applicationName)",
                "Log \(\.$meal) feeding for \(\.$pet) in \(.applicationName)",
                "Feed \(\.$pet) in \(.applicationName)"
            ],
            shortTitle: "Log Feeding",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: UpdateFoodStockIntent(),
            phrases: [
                "Update \(\.$pet)'s food stock in \(.applicationName)",
                "Restock \(\.$pet)'s food in \(.applicationName)"
            ],
            shortTitle: "Update Food Stock",
            systemImageName: "bag.fill"
        )
        AppShortcut(
            intent: FeedingStatusIntent(),
            phrases: [
                "Did I feed \(\.$pet) in \(.applicationName)",
                "When did I last feed \(\.$pet) in \(.applicationName)"
            ],
            shortTitle: "Feeding Status",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: FoodStockStatusIntent(),
            phrases: [
                "How much food does \(\.$pet) have in \(.applicationName)",
                "Check \(\.$pet)'s food stock in \(.applicationName)"
            ],
            shortTitle: "Food Stock",
            systemImageName: "chart.bar.fill"
        )
    }
}
