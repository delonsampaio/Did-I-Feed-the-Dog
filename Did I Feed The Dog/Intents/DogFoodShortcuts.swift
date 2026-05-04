import AppIntents

struct DogFoodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFeedingIntent(),
            phrases: [
                "Log a \(.applicationName) meal",
                "Log feeding in \(.applicationName)",
                "I fed the dog in \(.applicationName)"
            ],
            shortTitle: "Log Feeding",
            systemImageName: "dog.fill"
        )
        AppShortcut(
            intent: FeedingStatusIntent(),
            phrases: [
                "Did I feed the dog in \(.applicationName)?",
                "Check feeding status in \(.applicationName)",
                "Has the dog been fed?"
            ],
            shortTitle: "Check Feeding",
            systemImageName: "questionmark.circle"
        )
        AppShortcut(
            intent: FoodStockStatusIntent(),
            phrases: [
                "How much food is left in \(.applicationName)?",
                "Check food stock in \(.applicationName)"
            ],
            shortTitle: "Check Stock",
            systemImageName: "box.truck"
        )
        AppShortcut(
            intent: UpdateFoodStockIntent(),
            phrases: [
                "Update food stock in \(.applicationName)",
                "Add dog food in \(.applicationName)"
            ],
            shortTitle: "Update Stock",
            systemImageName: "plus.box"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .lime
}
