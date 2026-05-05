import AppIntents

struct DogFoodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFeedingIntent(),
            phrases: [
                "Log a \(.applicationName) meal",
                "Log a meal in \(.applicationName)",
                "Record a feeding in \(.applicationName)",
                "Feed \(\.$pet) in \(.applicationName)",
                "Mark \(\.$pet) as fed in \(.applicationName)",
                "Log \(\.$pet)'s meal in \(.applicationName)"
            ],
            shortTitle: "Log Feeding",
            systemImageName: "dog.fill"
        )
        AppShortcut(
            intent: FeedingStatusIntent(),
            phrases: [
                "Check feeding status in \(.applicationName)",
                "Did I feed \(\.$pet) in \(.applicationName)?",
                "Has \(\.$pet) been fed in \(.applicationName)?",
                "When was \(\.$pet) last fed in \(.applicationName)?",
                "Is \(\.$pet) overdue in \(.applicationName)?",
                "When did \(\.$pet) last eat in \(.applicationName)?"
            ],
            shortTitle: "Check Feeding",
            systemImageName: "questionmark.circle"
        )
        AppShortcut(
            intent: FoodStockStatusIntent(),
            phrases: [
                "Check food stock in \(.applicationName)",
                "How much food does \(\.$pet) have in \(.applicationName)?",
                "Check \(\.$pet)'s food stock in \(.applicationName)",
                "Is \(\.$pet)'s food running low in \(.applicationName)?"
            ],
            shortTitle: "Check Stock",
            systemImageName: "box.truck"
        )
        AppShortcut(
            intent: UpdateFoodStockIntent(),
            phrases: [
                "Add dog food in \(.applicationName)",
                "I bought more dog food in \(.applicationName)",
                "Restock \(\.$pet)'s food in \(.applicationName)",
                "Refill \(\.$pet)'s food in \(.applicationName)",
                "Add food for \(\.$pet) in \(.applicationName)"
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
