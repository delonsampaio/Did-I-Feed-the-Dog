import AppIntents

struct DogFoodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFeedingIntent(),
            shortcuts: [
                "Log a \(.applicationName) meal",
                "Log feeding in \(.applicationName)",
                "I fed the dog"
            ],
            shortTitle: "Log Feeding",
            systemImageName: "dog.fill"
        )
        AppShortcut(
            intent: FeedingStatusIntent(),
            shortcuts: [
                "Did I feed the dog in \(.applicationName)?",
                "Check feeding status in \(.applicationName)",
                "Has the dog been fed?"
            ],
            shortTitle: "Check Feeding",
            systemImageName: "questionmark.circle"
        )
        AppShortcut(
            intent: FoodStockStatusIntent(),
            shortcuts: [
                "How much food is left in \(.applicationName)?",
                "Check food stock in \(.applicationName)"
            ],
            shortTitle: "Check Stock",
            systemImageName: "box.truck"
        )
        AppShortcut(
            intent: UpdateFoodStockIntent(),
            shortcuts: [
                "Update food stock in \(.applicationName)",
                "Add dog food in \(.applicationName)"
            ],
            shortTitle: "Update Stock",
            systemImageName: "plus.box"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .green
}
