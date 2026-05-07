import AppIntents

struct DogFoodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Voice phrases intentionally omit the `\(\.$pet)` parameter slot.
        // iOS's predicted-shortcut layer was matching spoken pet names to
        // wrong donated UUIDs (e.g. "Feed Cooper" → Bella's UUID), bypassing
        // entity resolution entirely. Dropping the parameter forces Siri to
        // prompt via `requestValueDialog`, which always uses the picker /
        // `entities(matching:)` path — reliable instead of "hope for the best".
        AppShortcut(
            intent: LogFeedingIntent(),
            phrases: [
                "Log a meal in \(.applicationName)",
                "Log a \(.applicationName) meal",
                "I fed the dog in \(.applicationName)",
                "I fed my dog in \(.applicationName)",
                "Record a feeding in \(.applicationName)",
                "Feed the dog in \(.applicationName)",
                "Feed my dog in \(.applicationName)",
                "Mark my dog as fed in \(.applicationName)",
                "Log my dog's meal in \(.applicationName)"
            ],
            shortTitle: "Log Feeding",
            systemImageName: "dog.fill"
        )
        AppShortcut(
            intent: FeedingStatusIntent(),
            phrases: [
                "Did I feed the dog in \(.applicationName)",
                "Did I feed my dog in \(.applicationName)",
                "Has the dog been fed in \(.applicationName)",
                "Has my dog been fed in \(.applicationName)",
                "Check feeding status in \(.applicationName)",
                "When was my dog last fed in \(.applicationName)",
                "Is my dog overdue in \(.applicationName)",
                "When did my dog last eat in \(.applicationName)"
            ],
            shortTitle: "Check Feeding",
            systemImageName: "questionmark.circle"
        )
        AppShortcut(
            intent: FoodStockStatusIntent(),
            phrases: [
                "Check food stock in \(.applicationName)",
                "How much dog food is left in \(.applicationName)",
                "How much food is left in \(.applicationName)",
                "Do I need more dog food in \(.applicationName)",
                "Check my dog's food stock in \(.applicationName)",
                "Is my dog's food running low in \(.applicationName)"
            ],
            shortTitle: "Check Stock",
            systemImageName: "box.truck"
        )
        AppShortcut(
            intent: UpdateFoodStockIntent(),
            phrases: [
                "Add dog food in \(.applicationName)",
                "I bought more dog food in \(.applicationName)",
                "I bought dog food in \(.applicationName)",
                "Update food stock in \(.applicationName)",
                "Restock dog food in \(.applicationName)",
                "Refill my dog's food in \(.applicationName)",
                "Add food in \(.applicationName)"
            ],
            shortTitle: "Update Stock",
            systemImageName: "plus.box"
        )
        AppShortcut(
            intent: FeedAllDogsIntent(),
            phrases: [
                "Feed all dogs in \(.applicationName)",
                "Mark all dogs as fed in \(.applicationName)",
                "Log all feedings in \(.applicationName)",
                "I fed all the dogs in \(.applicationName)"
            ],
            shortTitle: "Feed All Dogs",
            systemImageName: "fork.knife"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .lime
}
