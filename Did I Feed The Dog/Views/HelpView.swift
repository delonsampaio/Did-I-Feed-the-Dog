import SwiftUI

private struct FAQItem: Identifiable {
    let id = UUID()
    let section: String
    let question: String
    let answer: String
    var isPro: Bool = false
}

struct HelpView: View {
    @State private var searchText = ""

    private var groupedSearchResults: [(section: String, items: [FAQItem])] {
        guard !searchText.isEmpty else { return [] }
        let matches = Self.allFAQs.filter {
            $0.question.localizedCaseInsensitiveContains(searchText) || $0.answer.localizedCaseInsensitiveContains(searchText)
        }

        var groups: [(section: String, items: [FAQItem])] = []
        for item in matches {
            if let index = groups.firstIndex(where: { $0.section == item.section }) {
                groups[index].items.append(item)
            } else {
                groups.append((section: item.section, items: [item]))
            }
        }
        return groups
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                gettingStartedSection
                widgetsSection
                feedingStatusSection
                notesSection
                foodStockSection
                feedingRemindersSection
                siriSection
                icloudSection
                notificationsSection
            } else if groupedSearchResults.isEmpty {
                Text("No results for \"\(searchText)\"")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(groupedSearchResults, id: \.section) { group in
                    Section(group.section) {
                        ForEach(group.items) { item in
                            FAQRow(question: item.question, answer: item.answer, isPro: item.isPro, startExpanded: true)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search Help")
        .navigationTitle("Help & FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var gettingStartedSection: some View {
        Section("Getting Started") {
            FAQRow(
                question: "How do I add a dog?",
                answer: "Tap the + button on the dashboard, or go to Settings -> Dogs -> Add Dog. Enter your dog's name. Birthday and photo are optional — flip the Add Birthday toggle only if you want a birthday alert each year."
            )
            FAQRow(
                question: "How do I log a feeding?",
                answer: "Tap the green Log Meal button on any dog's card. Choose the meal type — Breakfast, Lunch, Dinner, Morning, Afternoon, Evening, Snack, Treat, or Custom — and confirm. The card updates immediately."
            )
            FAQRow(
                question: "Can I log a meal for a past time?",
                answer: "Yes. When logging a meal, turn on the 'Set custom time' toggle to choose the exact date and time the feeding happened."
            )
            FAQRow(
                question: "Can I log a meal for all dogs at once?",
                answer: "Yes. When you have 2 or more dogs, a fork icon appears in the top-right of the dashboard next to the + button. Tap it to open the Feed All Dogs sheet and log the same meal for everyone in one tap.",
                isPro: true
            )
            FAQRow(
                question: "Can I undo a meal I just logged?",
                answer: "Yes. After logging a meal, an Undo banner appears at the bottom of the screen with a shrinking green bar showing how much time you have left. Tap Undo before the bar runs out to remove the entry and restore any food portion that was deducted."
            )
            FAQRow(
                question: "How do I show my name next to feedings I log?",
                answer: "Go to Settings -> Profile and type your name. It will appear next to every feeding you log so family members can see who fed the dog. If no name is set, the app uses your device model name (e.g. iPhone)."
            )
            FAQRow(
                question: "Can I choose a breed photo for my dog?",
                answer: "Yes. When adding or editing a dog, tap the photo area to open the avatar picker. Choose from 18 illustrated breed avatars or upload your own photo from your library. If no photo is set, the app automatically picks a default breed avatar for the dog."
            )
            FAQRow(
                question: "Can I change the app's appearance?",
                answer: "Yes. Go to Settings -> Appearance and pick Light, Dark, or System. System follows your iPhone's display setting. The change applies immediately, including while you're in Settings."
            )
            FAQRow(
                question: "How do I edit a dog's info?",
                answer: "Go to Settings -> Dogs and tap the dog's name to open the edit sheet. You can update their name, birthday, photo, and food stock count."
            )
            FAQRow(
                question: "How do I delete a dog?",
                answer: "In Settings -> Dogs, swipe left on the dog's name and tap Delete. This also removes all of their feeding history."
            )
        }
    }

    private var widgetsSection: some View {
        Section("Widgets & Quick Actions") {
            FAQRow(
                question: "How do I add a home screen widget?",
                answer: "Long-press your iPhone or iPad home screen, tap the + button in the top corner, and search for \"Did I Feed the Dog?\". The widget shows each dog's last fed time and overdue status at a glance.",
                isPro: true
            )
            FAQRow(
                question: "What widget sizes are available?",
                answer: "There are six layouts: Small (shows your most-overdue dog), Medium (shows up to 3 dogs side by side), Large (shows up to 6 dogs in a list), and three Lock Screen variants — Circular (fed count out of total), Rectangular (most-overdue dog with relative time), and Inline (a short summary line). Long-press your Lock Screen and tap Customize to add the lock screen widgets.",
                isPro: true
            )
            FAQRow(
                question: "Can I tap the widget to log a meal?",
                answer: "Yes. Tapping any dog on the small or medium widget opens the Log Meal sheet for that dog directly. You don't need to navigate to the dashboard first.",
                isPro: true
            )
            FAQRow(
                question: "Why isn't my widget updating?",
                answer: "The widget refreshes automatically every hour and immediately any time you log a meal inside the app. If it looks stale, open the app and log a feeding — the widget will update right away.",
                isPro: true
            )
            FAQRow(
                question: "How do I use quick actions from the home screen?",
                answer: "Long-press the Did I Feed the Dog? app icon on your home screen. A menu appears with a shortcut to log a meal for each of your dogs — no need to open the app first.",
                isPro: true
            )
            FAQRow(
                question: "How do I assign the Action Button to log a feeding?",
                answer: "On supported iPhones, go to iPhone Settings -> Action Button -> Shortcuts, then choose \"Log Feeding\" from the Did I Feed the Dog? shortcuts list. Press the Action Button from anywhere — even when the screen is off — to instantly log a meal.",
                isPro: true
            )
            FAQRow(
                question: "How do I add a Control Center button?",
                answer: "Go to iPhone Settings -> Control Center, scroll down, and tap + next to \"Log Feeding\" under Did I Feed the Dog?. Once added, tap that button from anywhere — even on the lock screen — to open the app and quickly log a meal.",
                isPro: true
            )
        }
    }

    private var feedingStatusSection: some View {
        Section("Feeding Status") {
            FAQRow(
                question: "What does overdue mean?",
                answer: "A dog is marked overdue — their Last Fed badge turns red — when they're past due for a feeding. If you have a feeding reminder schedule set up, overdue is based on your schedule: a dog is overdue as soon as a scheduled meal time has passed without a feeding logged since then. If reminders are off, you can set a manual time limit in Settings -> Alerts & Reminders -> Notification Settings ->Overdue After (default 12 hours)."
            )
            FAQRow(
                question: "How far back does the history go?",
                answer: "All feeding events are kept forever. The card shows the 3 most recent feedings. Tap the dog's name or photo to see the full history."
            )
            FAQRow(
                question: "Can I edit or delete a feeding entry?",
                answer: "Yes. Tap a dog's card header to open their history, then swipe left on any entry. You'll see an Edit option to change the meal type and notes, and Delete options to remove the entry (and optionally restore the food portion that was deducted)."
            )
            FAQRow(
                question: "Can I delete multiple feedings at once?",
                answer: "Yes. In the feeding history, tap Select in the top-right corner. Tap any meals you want to remove — a checkmark appears on each selected row. When you're ready, tap the red Delete button at the bottom of the screen and confirm. If you have food stock tracking on, you can also choose Delete & Restore Portions to add back the portions that were deducted when those meals were logged."
            )
            FAQRow(
                question: "Can I filter or sort my feeding history?",
                answer: "Yes. Tap the filter icon (three lines) in the top-right corner of the feeding history. You can filter by meal type, logged by (shown when more than one person has logged feedings), and a date range. You can also switch between newest-first and oldest-first sort order. The filter icon fills in when any filter is active. Tap Clear All to reset everything."
            )
            FAQRow(
                question: "Can I see when the next meal is due?",
                answer: "Yes, if you have feeding reminders set up. In Per Dog mode, each card shows a 'Next meal' row with the upcoming scheduled time. In All Dogs mode, a single line appears above all cards on the dashboard."
            )
            FAQRow(
                question: "What is Fasting Mode?",
                answer: "Fasting Mode is used when your dog shouldn't eat — for example, before a vet visit or due to illness. It displays a \"Do Not Feed\" warning on the card, prevents accidental logging, and pauses all feeding reminders and overdue alerts for that dog. Turn it on by long-pressing a dog's card on the dashboard, or in Settings -> Dogs -> [dog's name] -> Health."
            )
            FAQRow(
                question: "How do I silence notifications for one dog?",
                answer: "Go to Settings -> Dogs -> [dog's name] -> Alerts & Reminders and turn on Mute Notifications. All push alerts for that dog — feeding reminders, overdue, low stock, and birthday — are silenced until you turn it off. The card still shows their overdue status and history as normal; only the push notifications are muted."
            )
            FAQRow(
                question: "Can I track my dog's medications and supplements?",
                answer: "Yes. Tap a dog's card to open their history, then switch to the Medications tab. Tap + or Add Medication to get started. Enter the name, optional dose, and how often it needs to be given (3 times daily, twice daily, daily, every 2 days, every 3 days, weekly, or monthly). When a dose is due, a purple 💊 banner appears on your dog's card — tap it to log the dose. Pro users can enable a Dose Reminder push notification. By default it fires at the interval after your last logged dose (e.g. 24 hours later for a daily med), but you can also set a fixed time of day — for example, always remind at 8 AM."
            )
        }
    }

    private var notesSection: some View {
        Section("Feeding Notes") {
            FAQRow(
                question: "Can I add a note when logging a feeding?",
                answer: "Yes. The Log Meal sheet has an optional notes field below the meal picker. Use it for anything useful — gave medication, only ate half, used a different food, etc. Tap the notes field and the app will suggest notes you've used before as tappable chips — tap any chip to fill it in instantly."
            )
            FAQRow(
                question: "Where do I see the notes I added?",
                answer: "Notes appear in italic under the meal type in the feeding history. Tap a dog's card header to open their history."
            )
            FAQRow(
                question: "Can I edit a note after saving?",
                answer: "Yes. Tap any row in the feeding history to open the Edit Note sheet. The existing note is pre-filled -- update it and tap Save."
            )
        }
    }

    private var feedingRemindersSection: some View {
        Section("Alerts & Reminders") {
            FAQRow(
                question: "How do I set up feeding reminders?",
                answer: "Go to Settings -> Alerts & Reminders. Choose a schedule mode: Off, All Dogs, or Per Dog. Then add one or more daily reminder times."
            )
            FAQRow(
                question: "What is All Dogs mode?",
                answer: "One set of reminder times applies to every dog. You get a single notification at each time reminding you to feed all your dogs."
            )
            FAQRow(
                question: "What is Per Dog mode?",
                answer: "Each dog has their own reminder schedule. Tap the dog's name in Settings -> Alerts & Reminders (or tap the dog's name in Settings -> Dogs) to set their individual times.",
                isPro: true
            )
            FAQRow(
                question: "How many reminder times can I set?",
                answer: "Free users can set 1 daily reminder time. Pro users can set up to 3 per schedule. Most households need a morning and evening reminder, but a midday one is available too.",
                isPro: true
            )
            FAQRow(
                question: "Will reminders stop firing if I already fed my dog?",
                answer: "Yes. When you log a feeding, the next scheduled reminder for that dog is automatically cancelled. Any later reminders that day still fire as normal. Reminders are fully restored the next time you open the app."
            )
        }
    }

    private var foodStockSection: some View {
        Section("Food Stock") {
            FAQRow(
                question: "How do I track food portions?",
                answer: "Go to Settings -> Food Stock and choose a tracking mode: Per Dog, Shared Pool, or Not Tracked. Portions decrease automatically when you log a meal.",
                isPro: true
            )
            FAQRow(
                question: "What is Per Dog mode?",
                answer: "Each dog has their own food count. Every time you log a meal for a dog, their count decreases by one portion. Snack and Treat meals are the exception — they don't reduce the count. Set each dog's starting count in Settings -> Food Stock or by tapping the food stock cell on their card.",
                isPro: true
            )
            FAQRow(
                question: "What is Shared Pool mode?",
                answer: "One bag of food shared across all dogs. The pool decreases by one portion each time any dog is fed a meal. Snack and Treat logs do not reduce the shared count. Set the starting count in Settings -> Food Stock.",
                isPro: true
            )
            FAQRow(
                question: "What is Not Tracked?",
                answer: "Food stock tracking is turned off. No counts are shown and nothing is subtracted when you log a meal.",
                isPro: true
            )
            FAQRow(
                question: "Do Snack or Treat meals count against the food stock?",
                answer: "Snack and Treat do not reduce the portion count. All standard meal types (Morning, Breakfast, Lunch, Afternoon, Dinner, Evening) reduce the count by one. Custom meals reduce the count by default — but you can turn off the \"Deduct a portion\" toggle when logging a custom meal (e.g. Medication or Water) to skip the deduction.",
                isPro: true
            )
            FAQRow(
                question: "How do I restock?",
                answer: "Tap the Food Stock cell or the Low Food Stock banner on any dog's card to open the edit sheet and update the count directly. If a Feed All Dogs action drops several dogs to zero at once, the app shows a single restock sheet listing each affected dog so you can adjust them all from one screen.",
                isPro: true
            )
            FAQRow(
                question: "Why did the app ask me to update stock after logging a meal?",
                answer: "When a feeding drops your stock to zero, the app pops up an alert offering to update your portions — useful when you've just opened a new bag. Tap \"Update Stock Now\" to add portions, or \"Remind Me Later\" to dismiss. If you keep feeding while stock stays at zero, the prompt reappears every fourth feeding so you don't forget. You can turn this off entirely in Settings -> Food Stock.",
                isPro: true
            )
            FAQRow(
                question: "What is the Low Stock Threshold?",
                answer: "When a dog's stock drops to or below this number, a warning banner appears on their card and a push notification is sent (if enabled). Adjust it in Settings -> Alerts & Reminders -> Notification Settings.",
                isPro: true
            )
        }
    }

    private var siriSection: some View {
        Section("Siri & Shortcuts") {
            FAQRow(
                question: "How do I log a feeding with Siri?",
                answer: "Say \"Log a meal in Fed The Dog?\", \"I fed the dog in Fed The Dog?\", or \"Feed my dog in Fed The Dog?\". With one dog, Siri logs for them automatically. With multiple dogs, Siri asks which one. Then Siri asks the meal type — say or tap your choice. Siri will tell you the remaining food stock afterward.",
                isPro: true
            )
            FAQRow(
                question: "Can I feed all my dogs at once with Siri?",
                answer: "Yes. Say \"Feed all dogs in Fed The Dog?\", \"Mark all dogs as fed in Fed The Dog?\", or \"I fed all the dogs in Fed The Dog?\". Fasting dogs are automatically skipped.",
                isPro: true
            )
            FAQRow(
                question: "Why does Siri ask which dog instead of just doing what I said?",
                answer: "For accuracy. Siri now asks \"Which dog?\" so you can confirm the right one. If you only have one dog, Siri handles it automatically, so you'll only be asked if you have multiple dogs.",
                isPro: true
            )
            FAQRow(
                question: "Does Siri ask me which meal type when I log a feeding?",
                answer: "Yes. After Siri picks the dog (or asks which one), it asks \"What type of meal is this?\" and presents all the options — Breakfast, Lunch, Dinner, Morning, Afternoon, Evening, Snack, and Treat. Just say or tap the one you want.",
                isPro: true
            )
            FAQRow(
                question: "Will Siri recognize a new dog I just added?",
                answer: "Yes. As soon as you save or rename a dog, Siri learns their name and will show them as an option the next time you ask. The same applies if a family member adds a dog to your shared home, as long as you open the app once so Siri sees them.",
                isPro: true
            )
            FAQRow(
                question: "How do I check if my dog has been fed?",
                answer: "Say \"Did I feed the dog in Fed The Dog?\", \"Has the dog been fed in Fed The Dog?\", or \"When was my dog last fed in Fed The Dog?\". With one dog, Siri answers right away. With multiple, Siri asks which one.",
                isPro: true
            )
            FAQRow(
                question: "How do I check food stock with Siri?",
                answer: "Say \"Check food stock in Fed The Dog?\", \"How much dog food is left in Fed The Dog?\", or \"Is my dog's food running low in Fed The Dog?\". Siri reports the remaining count — or tells you that your dog is out of food when stock has hit zero. With multiple dogs in individual stock mode, Siri asks which dog.",
                isPro: true
            )
            FAQRow(
                question: "How do I update food stock with Siri?",
                answer: "Say \"Add dog food in Fed The Dog?\", \"I bought more dog food in Fed The Dog?\", or \"Update food stock in Fed The Dog?\". Siri asks which dog (in individual mode) and how many portions you added.",
                isPro: true
            )
            FAQRow(
                question: "Can I add these as shortcuts in the Shortcuts app?",
                answer: "Yes. Open the Shortcuts app, tap the + button, and search for Fed The Dog? to see all available actions. You can also go to iPhone Settings -> Apps -> Fed The Dog? to manage them.",
                isPro: true
            )
            FAQRow(
                question: "Do I always have to say the full app name with Siri?",
                answer: "Yes — include \"in Fed The Dog?\" so Siri knows which app to use. With repeated use, Siri Suggestions may surface the shortcut on your lock screen or Spotlight for a quick tap, but spoken commands should always include the app name.",
                isPro: true
            )
        }
    }

    private var icloudSection: some View {
        Section("iCloud Sync & Family") {
            FAQRow(
                question: "Does my data sync across devices?",
                answer: "Yes. If everyone in your household is signed into the same iCloud account, feedings, food stock, and dog info stay updated across all iPhones automatically. Changes usually appear within about a minute."
            )
            FAQRow(
                question: "How do I know which family member fed the dog?",
                answer: "Each feeding in the history shows the name of the person who logged it, next to the time. Make sure everyone in your household sets their name in Settings -> Profile so their feedings are clearly attributed."
            )
            FAQRow(
                question: "How do I know if my family's changes are updating?",
                answer: "A small spinner appears next to the gear icon on the dashboard while the app is updating data. If a feeding from a family member hasn't appeared yet, just wait a moment for the spinner to disappear."
            )
            FAQRow(
                question: "What if two people log a feeding at the same time?",
                answer: "Both feedings are saved. You may see two entries close together in the history — that's the accurate record of what happened."
            )
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            FAQRow(
                question: "What is the Low Stock Notification?",
                answer: "An alert sent to your phone when a dog's food stock drops to or below your warning level. If you have the app open, you'll see an orange warning on the dog's card instead.",
                isPro: true
            )
            FAQRow(
                question: "What is the Birthday Notification?",
                answer: "If you set a birthday for your dog, the app sends a celebration alert each year on that day. The field is optional — if you didn't add a birthday, no birthday alert fires.",
                isPro: true
            )
            FAQRow(
                question: "What is the In-App Low Stock Banner?",
                answer: "An orange banner that appears on the dog's card when stock is low. This is separate from the push notification — it shows while you're actively using the app.",
                isPro: true
            )
            FAQRow(
                question: "What is the Overdue Notification?",
                answer: "An alert sent when a dog hasn't been fed and is past due (default 12 hours). It only alerts you once, and goes away automatically when you log a meal. Turn it off in Settings -> Alerts & Reminders -> Notification Settings ->Overdue Notification.",
                isPro: true
            )
            FAQRow(
                question: "What is the App Icon Badge?",
                answer: "The red number shown on the app's icon on your home screen. It shows how many of your dogs are currently overdue for a meal. It updates automatically when you open the app or log a feeding. Turn it off in Settings -> Alerts & Reminders -> Notification Settings ->App Icon Badge.",
                isPro: true
            )
            FAQRow(
                question: "How do I set up a Water Bowl Cleaning Reminder?",
                answer: "Go to Settings -> Health & Hygiene and enable the Water Bowl Reminder. You can choose the day of the week and time you'd like to be reminded to clean and refill the bowl. The reminder fires weekly.",
                isPro: true
            )
            FAQRow(
                question: "I'm not receiving notifications. What should I check?",
                answer: "Open the app's Settings -> Alerts & Reminders -> Notification Settings. If your phone's notifications are disabled, an orange warning banner appears — tap it to jump straight to your iPhone Settings and turn them on. Your preferences inside the app will automatically turn back on once permission is restored."
            )
        }
    }

    private static let allFAQs: [FAQItem] = [
            .init(section: "Getting Started", question: "How do I add a dog?", answer: "Tap the + button on the dashboard, or go to Settings -> Dogs -> Add Dog. Enter your dog's name. Birthday and photo are optional — flip the Add Birthday toggle only if you want a birthday alert each year."),
            .init(section: "Getting Started", question: "How do I log a feeding?", answer: "Tap the green Log Meal button on any dog's card. Choose the meal type — Breakfast, Lunch, Dinner, Morning, Afternoon, Evening, Snack, Treat, or Custom — and confirm. The card updates immediately."),
            .init(section: "Getting Started", question: "Can I log a meal for a past time?", answer: "Yes. When logging a meal, turn on the 'Set custom time' toggle to choose the exact date and time the feeding happened."),
            .init(section: "Getting Started", question: "Can I log a meal for all dogs at once?", answer: "Yes. When you have 2 or more dogs, a fork icon appears in the top-right of the dashboard next to the + button. Tap it to open the Feed All Dogs sheet and log the same meal for everyone in one tap.", isPro: true),
            .init(section: "Getting Started", question: "Can I undo a meal I just logged?", answer: "Yes. After logging a meal, an Undo banner appears at the bottom of the screen with a shrinking green bar showing how much time you have left. Tap Undo before the bar runs out to remove the entry and restore any food portion that was deducted."),
            .init(section: "Getting Started", question: "How do I show my name next to feedings I log?", answer: "Go to Settings -> Profile and type your name. It will appear next to every feeding you log so family members can see who fed the dog. If no name is set, the app uses your device model name (e.g. iPhone)."),
            .init(section: "Getting Started", question: "Can I choose a breed photo for my dog?", answer: "Yes. When adding or editing a dog, tap the photo area to open the avatar picker. Choose from 18 illustrated breed avatars or upload your own photo from your library. If no photo is set, the app automatically picks a default breed avatar for the dog."),
            .init(section: "Getting Started", question: "Can I change the app's appearance?", answer: "Yes. Go to Settings -> Appearance and pick Light, Dark, or System. System follows your iPhone's display setting. The change applies immediately, including while you're in Settings."),
            .init(section: "Getting Started", question: "How do I edit a dog's info?", answer: "Go to Settings -> Dogs and tap the dog's name to open the edit sheet. You can update their name, birthday, photo, and food stock count."),
            .init(section: "Getting Started", question: "How do I delete a dog?", answer: "In Settings -> Dogs, swipe left on the dog's name and tap Delete. This also removes all of their feeding history."),
            .init(section: "Widgets & Quick Actions", question: "How do I add a home screen widget?", answer: "Long-press your iPhone or iPad home screen, tap the + button in the top corner, and search for \"Did I Feed the Dog?\". The widget shows each dog's last fed time and overdue status at a glance.", isPro: true),
            .init(section: "Widgets & Quick Actions", question: "What widget sizes are available?", answer: "There are six layouts: Small (shows your most-overdue dog), Medium (shows up to 3 dogs side by side), Large (shows up to 6 dogs in a list), and three Lock Screen variants — Circular (fed count out of total), Rectangular (most-overdue dog with relative time), and Inline (a short summary line). Long-press your Lock Screen and tap Customize to add the lock screen widgets.", isPro: true),
            .init(section: "Widgets & Quick Actions", question: "Can I tap the widget to log a meal?", answer: "Yes. Tapping any dog on the small or medium widget opens the Log Meal sheet for that dog directly. You don't need to navigate to the dashboard first.", isPro: true),
            .init(section: "Widgets & Quick Actions", question: "Why isn't my widget updating?", answer: "The widget refreshes automatically every hour and immediately any time you log a meal inside the app. If it looks stale, open the app and log a feeding — the widget will update right away.", isPro: true),
            .init(section: "Widgets & Quick Actions", question: "How do I use quick actions from the home screen?", answer: "Long-press the Did I Feed the Dog? app icon on your home screen. A menu appears with a shortcut to log a meal for each of your dogs — no need to open the app first.", isPro: true),
            .init(section: "Widgets & Quick Actions", question: "How do I assign the Action Button to log a feeding?", answer: "On supported iPhones, go to iPhone Settings -> Action Button -> Shortcuts, then choose \"Log Feeding\" from the Did I Feed the Dog? shortcuts list. Press the Action Button from anywhere — even when the screen is off — to instantly log a meal.", isPro: true),
            .init(section: "Widgets & Quick Actions", question: "How do I add a Control Center button?", answer: "Go to iPhone Settings -> Control Center, scroll down, and tap + next to \"Log Feeding\" under Did I Feed the Dog?. Once added, tap that button from anywhere — even on the lock screen — to open the app and quickly log a meal.", isPro: true),
            .init(section: "Feeding Status", question: "What does overdue mean?", answer: "A dog is marked overdue — their Last Fed badge turns red — when they're past due for a feeding. If you have a feeding reminder schedule set up, overdue is based on your schedule: a dog is overdue as soon as a scheduled meal time has passed without a feeding logged since then. If reminders are off, you can set a manual time limit in Settings -> Alerts & Reminders -> Notification Settings ->Overdue After (default 12 hours)."),
            .init(section: "Feeding Status", question: "How far back does the history go?", answer: "All feeding events are kept forever. The card shows the 3 most recent feedings. Tap the dog's name or photo to see the full history."),
            .init(section: "Feeding Status", question: "Can I edit or delete a feeding entry?", answer: "Yes. Tap a dog's card header to open their history, then swipe left on any entry. You'll see an Edit option to change the meal type and notes, and Delete options to remove the entry (and optionally restore the food portion that was deducted)."),
            .init(section: "Feeding Status", question: "Can I delete multiple feedings at once?", answer: "Yes. In the feeding history, tap Select in the top-right corner. Tap any meals you want to remove — a checkmark appears on each selected row. When you're ready, tap the red Delete button at the bottom of the screen and confirm. If you have food stock tracking on, you can also choose Delete & Restore Portions to add back the portions that were deducted when those meals were logged."),
            .init(section: "Feeding Status", question: "Can I filter or sort my feeding history?", answer: "Yes. Tap the filter icon (three lines) in the top-right corner of the feeding history. You can filter by meal type, logged by (shown when more than one person has logged feedings), and a date range. You can also switch between newest-first and oldest-first sort order. The filter icon fills in when any filter is active. Tap Clear All to reset everything."),
            .init(section: "Feeding Status", question: "Can I see when the next meal is due?", answer: "Yes, if you have feeding reminders set up. In Per Dog mode, each card shows a 'Next meal' row with the upcoming scheduled time. In All Dogs mode, a single line appears above all cards on the dashboard."),
            .init(section: "Feeding Status", question: "What is Fasting Mode?", answer: "Fasting Mode is used when your dog shouldn't eat — for example, before a vet visit or due to illness. It displays a \"Do Not Feed\" warning on the card, prevents accidental logging, and pauses all feeding reminders and overdue alerts for that dog. Turn it on by long-pressing a dog's card on the dashboard, or in Settings -> Dogs -> [dog's name] -> Health."),
            .init(section: "Feeding Status", question: "How do I silence notifications for one dog?", answer: "Go to Settings -> Dogs -> [dog's name] -> Alerts & Reminders and turn on Mute Notifications. All push alerts for that dog — feeding reminders, overdue, low stock, and birthday — are silenced until you turn it off. The card still shows their overdue status and history as normal; only the push notifications are muted."),
            .init(section: "Feeding Status", question: "Can I track my dog's medications and supplements?", answer: "Yes. Tap a dog's card to open their history, then switch to the Medications tab. Tap + or Add Medication to get started. Enter the name, optional dose, and how often it needs to be given (3 times daily, twice daily, daily, every 2 days, every 3 days, weekly, or monthly). When a dose is due, a purple 💊 banner appears on your dog's card — tap it to log the dose. Pro users can enable a Dose Reminder push notification. By default it fires at the interval after your last logged dose (e.g. 24 hours later for a daily med), but you can also set a fixed time of day — for example, always remind at 8 AM."),
            .init(section: "Feeding Notes", question: "Can I add a note when logging a feeding?", answer: "Yes. The Log Meal sheet has an optional notes field below the meal picker. Use it for anything useful — gave medication, only ate half, used a different food, etc. Tap the notes field and the app will suggest notes you've used before as tappable chips — tap any chip to fill it in instantly."),
            .init(section: "Feeding Notes", question: "Where do I see the notes I added?", answer: "Notes appear in italic under the meal type in the feeding history. Tap a dog's card header to open their history."),
            .init(section: "Feeding Notes", question: "Can I edit a note after saving?", answer: "Yes. Tap any row in the feeding history to open the Edit Note sheet. The existing note is pre-filled -- update it and tap Save."),
            .init(section: "Food Stock", question: "How do I track food portions?", answer: "Go to Settings -> Food Stock and choose a tracking mode: Per Dog, Shared Pool, or Not Tracked. Portions decrease automatically when you log a meal.", isPro: true),
            .init(section: "Food Stock", question: "What is Per Dog mode?", answer: "Each dog has their own food count. Every time you log a meal for a dog, their count decreases by one portion. Snack and Treat meals are the exception — they don't reduce the count. Set each dog's starting count in Settings -> Food Stock or by tapping the food stock cell on their card.", isPro: true),
            .init(section: "Food Stock", question: "What is Shared Pool mode?", answer: "One bag of food shared across all dogs. The pool decreases by one portion each time any dog is fed a meal. Snack and Treat logs do not reduce the shared count. Set the starting count in Settings -> Food Stock.", isPro: true),
            .init(section: "Food Stock", question: "What is Not Tracked?", answer: "Food stock tracking is turned off. No counts are shown and nothing is subtracted when you log a meal.", isPro: true),
            .init(section: "Food Stock", question: "Do Snack or Treat meals count against the food stock?", answer: "Snack and Treat do not reduce the portion count. All standard meal types (Morning, Breakfast, Lunch, Afternoon, Dinner, Evening) reduce the count by one. Custom meals reduce the count by default — but you can turn off the \"Deduct a portion\" toggle when logging a custom meal (e.g. Medication or Water) to skip the deduction.", isPro: true),
            .init(section: "Food Stock", question: "How do I restock?", answer: "Tap the Food Stock cell or the Low Food Stock banner on any dog's card to open the edit sheet and update the count directly. If a Feed All Dogs action drops several dogs to zero at once, the app shows a single restock sheet listing each affected dog so you can adjust them all from one screen.", isPro: true),
            .init(section: "Food Stock", question: "Why did the app ask me to update stock after logging a meal?", answer: "When a feeding drops your stock to zero, the app pops up an alert offering to update your portions — useful when you've just opened a new bag. Tap \"Update Stock Now\" to add portions, or \"Remind Me Later\" to dismiss. If you keep feeding while stock stays at zero, the prompt reappears every fourth feeding so you don't forget. You can turn this off entirely in Settings -> Food Stock.", isPro: true),
            .init(section: "Food Stock", question: "What is the Low Stock Threshold?", answer: "When a dog's stock drops to or below this number, a warning banner appears on their card and a push notification is sent (if enabled). Adjust it in Settings -> Alerts & Reminders -> Notification Settings.", isPro: true),
            .init(section: "Alerts & Reminders", question: "How do I set up feeding reminders?", answer: "Go to Settings -> Alerts & Reminders. Choose a schedule mode: Off, All Dogs, or Per Dog. Then add one or more daily reminder times."),
            .init(section: "Alerts & Reminders", question: "What is All Dogs mode?", answer: "One set of reminder times applies to every dog. You get a single notification at each time reminding you to feed all your dogs."),
            .init(section: "Alerts & Reminders", question: "What is Per Dog mode?", answer: "Each dog has their own reminder schedule. Tap the dog's name in Settings -> Alerts & Reminders (or tap the dog's name in Settings -> Dogs) to set their individual times.", isPro: true),
            .init(section: "Alerts & Reminders", question: "How many reminder times can I set?", answer: "Free users can set 1 daily reminder time. Pro users can set up to 3 per schedule. Most households need a morning and evening reminder, but a midday one is available too.", isPro: true),
            .init(section: "Alerts & Reminders", question: "Will reminders stop firing if I already fed my dog?", answer: "Yes. When you log a feeding, the next scheduled reminder for that dog is automatically cancelled. Any later reminders that day still fire as normal. Reminders are fully restored the next time you open the app."),
            .init(section: "Siri & Shortcuts", question: "How do I log a feeding with Siri?", answer: "Say \"Log a meal in Fed The Dog?\", \"I fed the dog in Fed The Dog?\", or \"Feed my dog in Fed The Dog?\". With one dog, Siri logs for them automatically. With multiple dogs, Siri asks which one. Then Siri asks the meal type — say or tap your choice. Siri will tell you the remaining food stock afterward.", isPro: true),
            .init(section: "Siri & Shortcuts", question: "Can I feed all my dogs at once with Siri?", answer: "Yes. Say \"Feed all dogs in Fed The Dog?\", \"Mark all dogs as fed in Fed The Dog?\", or \"I fed all the dogs in Fed The Dog?\". Fasting dogs are automatically skipped.", isPro: true),
            .init(section: "Siri & Shortcuts", question: "Why does Siri ask which dog instead of just doing what I said?", answer: "For accuracy. Siri now asks \"Which dog?\" so you can confirm the right one. If you only have one dog, Siri handles it automatically, so you'll only be asked if you have multiple dogs.", isPro: true),
            .init(section: "Siri & Shortcuts", question: "Does Siri ask me which meal type when I log a feeding?", answer: "Yes. After Siri picks the dog (or asks which one), it asks \"What type of meal is this?\" and presents all the options — Breakfast, Lunch, Dinner, Morning, Afternoon, Evening, Snack, and Treat. Just say or tap the one you want.", isPro: true),
            .init(section: "Siri & Shortcuts", question: "Will Siri recognize a new dog I just added?", answer: "Yes. As soon as you save or rename a dog, Siri learns their name and will show them as an option the next time you ask. The same applies if a family member adds a dog to your shared home, as long as you open the app once so Siri sees them.", isPro: true),
            .init(section: "Siri & Shortcuts", question: "How do I check if my dog has been fed?", answer: "Say \"Did I feed the dog in Fed The Dog?\", \"Has the dog been fed in Fed The Dog?\", or \"When was my dog last fed in Fed The Dog?\". With one dog, Siri answers right away. With multiple, Siri asks which one.", isPro: true),
            .init(section: "Siri & Shortcuts", question: "How do I check food stock with Siri?", answer: "Say \"Check food stock in Fed The Dog?\", \"How much dog food is left in Fed The Dog?\", or \"Is my dog's food running low in Fed The Dog?\". Siri reports the remaining count — or tells you that your dog is out of food when stock has hit zero. With multiple dogs in individual stock mode, Siri asks which dog.", isPro: true),
            .init(section: "Siri & Shortcuts", question: "How do I update food stock with Siri?", answer: "Say \"Add dog food in Fed The Dog?\", \"I bought more dog food in Fed The Dog?\", or \"Update food stock in Fed The Dog?\". Siri asks which dog (in individual mode) and how many portions you added.", isPro: true),
            .init(section: "Siri & Shortcuts", question: "Can I add these as shortcuts in the Shortcuts app?", answer: "Yes. Open the Shortcuts app, tap the + button, and search for Fed The Dog? to see all available actions. You can also go to iPhone Settings -> Apps -> Fed The Dog? to manage them.", isPro: true),
            .init(section: "Siri & Shortcuts", question: "Do I always have to say the full app name with Siri?", answer: "Yes — include \"in Fed The Dog?\" so Siri knows which app to use. With repeated use, Siri Suggestions may surface the shortcut on your lock screen or Spotlight for a quick tap, but spoken commands should always include the app name.", isPro: true),
            .init(section: "iCloud Sync & Family", question: "Does my data sync across devices?", answer: "Yes. If everyone in your household is signed into the same iCloud account, feedings, food stock, and dog info stay updated across all iPhones automatically. Changes usually appear within about a minute."),
            .init(section: "iCloud Sync & Family", question: "How do I know which family member fed the dog?", answer: "Each feeding in the history shows the name of the person who logged it, next to the time. Make sure everyone in your household sets their name in Settings -> Profile so their feedings are clearly attributed."),
            .init(section: "iCloud Sync & Family", question: "How do I know if my family's changes are updating?", answer: "A small spinner appears next to the gear icon on the dashboard while the app is updating data. If a feeding from a family member hasn't appeared yet, just wait a moment for the spinner to disappear."),
            .init(section: "iCloud Sync & Family", question: "What if two people log a feeding at the same time?", answer: "Both feedings are saved. You may see two entries close together in the history — that's the accurate record of what happened."),
            .init(section: "Notifications", question: "What is the Low Stock Notification?", answer: "An alert sent to your phone when a dog's food stock drops to or below your warning level. If you have the app open, you'll see an orange warning on the dog's card instead.", isPro: true),
            .init(section: "Notifications", question: "What is the Birthday Notification?", answer: "If you set a birthday for your dog, the app sends a celebration alert each year on that day. The field is optional — if you didn't add a birthday, no birthday alert fires.", isPro: true),
            .init(section: "Notifications", question: "What is the In-App Low Stock Banner?", answer: "An orange banner that appears on the dog's card when stock is low. This is separate from the push notification — it shows while you're actively using the app.", isPro: true),
            .init(section: "Notifications", question: "What is the Overdue Notification?", answer: "An alert sent when a dog hasn't been fed and is past due (default 12 hours). It only alerts you once, and goes away automatically when you log a meal. Turn it off in Settings -> Alerts & Reminders -> Notification Settings ->Overdue Notification.", isPro: true),
            .init(section: "Notifications", question: "What is the App Icon Badge?", answer: "The red number shown on the app's icon on your home screen. It shows how many of your dogs are currently overdue for a meal. It updates automatically when you open the app or log a feeding. Turn it off in Settings -> Alerts & Reminders -> Notification Settings ->App Icon Badge.", isPro: true),
            .init(section: "Notifications", question: "How do I set up a Water Bowl Cleaning Reminder?", answer: "Go to Settings -> Health & Hygiene and enable the Water Bowl Reminder. You can choose the day of the week and time you'd like to be reminded to clean and refill the bowl. The reminder fires weekly.", isPro: true),
            .init(section: "Notifications", question: "I'm not receiving notifications. What should I check?", answer: "Open the app's Settings -> Alerts & Reminders -> Notification Settings. If your phone's notifications are disabled, an orange warning banner appears — tap it to jump straight to your iPhone Settings and turn them on. Your preferences inside the app will automatically turn back on once permission is restored."),
        ]
}

private struct FAQRow: View {
    @Environment(EntitlementManager.self) private var entitlements
    let question: String
    let answer: String
    var isPro: Bool = false
    var startExpanded: Bool = false
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(answer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Text(question)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                if isPro && !entitlements.isPro {
                    Text("PRO")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .onAppear { if startExpanded { expanded = true } }
    }
}
