import SwiftUI

private struct FAQItem: Identifiable {
    let id = UUID()
    let section: String
    let question: String
    let answer: String
}

struct HelpView: View {
    @State private var searchText = ""

    private var filteredFAQs: [FAQItem] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return allFAQs.filter {
            $0.question.lowercased().contains(q) || $0.answer.lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                gettingStartedSection
                feedingStatusSection
                notesSection
                foodStockSection
                feedingRemindersSection
                widgetSection
                siriSection
                icloudSection
                notificationsSection
            } else if filteredFAQs.isEmpty {
                Text("No results for \"\(searchText)\"")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filteredFAQs) { item in
                    Section(item.section) {
                        FAQRow(question: item.question, answer: item.answer, startExpanded: true)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search Help")
        .navigationTitle("Help & FAQ")
        .navigationBarTitleDisplayMode(.large)
    }

    private var gettingStartedSection: some View {
        Section("Getting Started") {
            FAQRow(
                question: "How do I add a dog?",
                answer: "Tap the + button on the dashboard, or go to Settings -> Dogs -> Add Dog. Enter your dog's name, birthday, and an optional photo."
            )
            FAQRow(
                question: "How do I log a feeding?",
                answer: "Tap the green Log Meal button on any dog's card. Choose the meal type — Breakfast, Lunch, Dinner, Morning, Afternoon, Evening, Snack, Treat, or Custom — and confirm. The card updates immediately."
            )
            FAQRow(
                question: "Can I log a meal for all dogs at once?",
                answer: "Yes. When you have 2 or more dogs, a fork icon appears in the top-right of the dashboard next to the + button. Tap it to open the Feed All Dogs sheet and log the same meal for everyone in one tap."
            )
            FAQRow(
                question: "Can I undo a meal I just logged?",
                answer: "Yes. After logging a meal, a brief Undo banner appears at the bottom of the card. Tap Undo within a few seconds to remove the entry and restore any food portion that was deducted."
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

    private var feedingStatusSection: some View {
        Section("Feeding Status") {
            FAQRow(
                question: "What does overdue mean?",
                answer: "A dog is marked overdue when their last recorded feeding was longer ago than your overdue threshold. The default is 12 hours but you can adjust it in Settings -> Notifications -> Overdue After. Their card shows a red Last Fed badge as a reminder."
            )
            FAQRow(
                question: "How far back does the history go?",
                answer: "All feeding events are kept forever. The card shows the 3 most recent feedings. Tap the dog's name or photo to see the full history."
            )
            FAQRow(
                question: "Can I delete a feeding entry?",
                answer: "Yes. Tap a dog's card header to open their history, then swipe left on any entry. You'll see two options — Delete removes the entry only, and Delete & Restore Portion removes the entry and adds one portion back to the food stock."
            )
            FAQRow(
                question: "Can I see when the next meal is due?",
                answer: "Yes, if you have feeding reminders set up. In Per Dog mode, each card shows a 'Next meal' row with the upcoming scheduled time. In All Dogs mode, a single line appears above all cards on the dashboard."
            )
        }
    }

    private var notesSection: some View {
        Section("Feeding Notes") {
            FAQRow(
                question: "Can I add a note when logging a feeding?",
                answer: "Yes. The Log Meal sheet has an optional notes field below the meal picker. Use it for anything useful — gave medication, only ate half, used a different food, etc."
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
        Section("Feeding Reminders") {
            FAQRow(
                question: "How do I set up feeding reminders?",
                answer: "Go to Settings -> Feeding Reminders. Choose a schedule mode: Off, All Dogs, or Per Dog. Then add one or more daily reminder times."
            )
            FAQRow(
                question: "What is All Dogs mode?",
                answer: "One set of reminder times applies to every dog. You get a single notification at each time reminding you to feed all your dogs."
            )
            FAQRow(
                question: "What is Per Dog mode?",
                answer: "Each dog has their own reminder schedule. Tap the dog's name in Settings -> Feeding Reminders (or tap the dog's name in Settings -> Dogs) to set their individual times."
            )
            FAQRow(
                question: "How many reminder times can I set?",
                answer: "Up to 3 daily reminder times per schedule. Most households need a morning and evening reminder, but a midday one is available too."
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
                question: "What is Per Dog mode?",
                answer: "Each dog has their own food count. Every time you log a meal for a dog, their count decreases by one portion. Snack and Treat meals are the exception — they don't reduce the count. Set each dog's starting count in Settings -> Food Stock or by tapping the food stock cell on their card."
            )
            FAQRow(
                question: "What is Shared Pool mode?",
                answer: "One bag of food shared across all dogs. The pool decreases by one portion each time any dog is fed a meal. Snack and Treat logs do not reduce the shared count. Set the starting count in Settings -> Food Stock."
            )
            FAQRow(
                question: "What is Not Tracked?",
                answer: "Food stock tracking is turned off. No counts are shown and nothing is decremented when you log a meal."
            )
            FAQRow(
                question: "Do Snack or Treat meals count against the food stock?",
                answer: "No. Snack and Treat are logged in the history for reference but do not reduce the portion count. All other meal types (Morning, Evening, Breakfast, Lunch, Afternoon, Dinner, and Custom) do reduce the count by one."
            )
            FAQRow(
                question: "How do I restock?",
                answer: "Tap the Food Stock cell or the Low Food Stock banner on any dog's card to open the edit sheet and update the count directly."
            )
            FAQRow(
                question: "What is the Low Stock Threshold?",
                answer: "When a dog's stock drops to or below this number, a warning banner appears on their card and a push notification is sent (if enabled). Adjust it in Settings -> Notifications."
            )
        }
    }

    private var widgetSection: some View {
        Section("Widget") {
            FAQRow(
                question: "How do I add the widget?",
                answer: "Long-press the home screen until icons wiggle, tap the + button in the top-left corner, search for Did I Feed The Dog, choose a size, and tap Add Widget."
            )
            FAQRow(
                question: "What do the widget sizes show?",
                answer: "Small: your most overdue dog with their last-fed time. Medium: up to 3 dogs with fed/overdue status. Lock screen widgets show a quick count or the most overdue dog."
            )
            FAQRow(
                question: "Why does the widget show old data?",
                answer: "The widget refreshes automatically every hour. When you log a feeding in the app, the widget updates immediately."
            )
            FAQRow(
                question: "What happens when I tap the widget?",
                answer: "The small and medium widgets open the Log Meal sheet for the tapped dog directly. The lock screen widgets open the app dashboard."
            )
        }
    }

    private var siriSection: some View {
        Section("Siri & Shortcuts") {
            FAQRow(
                question: "How do I log a feeding with Siri?",
                answer: "Say \"Log [dog's name]'s feeding in Did I Feed\". Siri will confirm the meal and log it instantly — no need to open the app."
            )
            FAQRow(
                question: "How do I check if my dog has been fed?",
                answer: "Say \"Did I feed [dog's name] in Did I Feed\". Siri will tell you when they were last fed and whether they're overdue."
            )
            FAQRow(
                question: "How do I update food stock with Siri?",
                answer: "Say \"Update [dog's name]'s food stock in Did I Feed\". Siri will ask how many portions you added and update the count."
            )
            FAQRow(
                question: "Can I add these as shortcuts in the Shortcuts app?",
                answer: "Yes. Open the Shortcuts app, tap the + button, and search for Did I Feed to see all available actions. You can also go to iPhone Settings -> Siri & Search -> Did I Feed to manage them."
            )
        }
    }

    private var icloudSection: some View {
        Section("iCloud Sync") {
            FAQRow(
                question: "Does my data sync across devices?",
                answer: "Yes. If everyone in your household is signed into the same iCloud account, feedings, food stock, and dog info stay in sync across all your iPhones automatically. Changes usually appear within about a minute."
            )
            FAQRow(
                question: "What if two people log a feeding at the same time?",
                answer: "Both feedings are saved. You may see two entries close together in the history — that's the accurate record of what happened."
            )
            FAQRow(
                question: "Does the widget stay in sync too?",
                answer: "Yes. The widget shows the same data as the app, so it reflects the most recent feeding logged by anyone in the household."
            )
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            FAQRow(
                question: "What is the Low Stock Push Alert?",
                answer: "A notification sent when a dog's food stock drops to or below the Low Stock Threshold after logging a feeding."
            )
            FAQRow(
                question: "What is the Birthday Push Alert?",
                answer: "A notification sent on your dog's birthday each year, based on the birthday you entered when adding them."
            )
            FAQRow(
                question: "What is the Low Stock UI Warning?",
                answer: "An orange banner that appears on the dog's card when stock is low. This is separate from the push notification."
            )
            FAQRow(
                question: "I'm not receiving notifications. What should I check?",
                answer: "Go to iPhone Settings -> Notifications -> Did I Feed and make sure notifications are allowed. Also confirm the toggles are on in the app's Settings -> Notifications."
            )
        }
    }

    private var allFAQs: [FAQItem] {
        [
            .init(section: "Getting Started", question: "How do I add a dog?", answer: "Tap the + button on the dashboard, or go to Settings -> Dogs -> Add Dog. Enter your dog's name, birthday, and an optional photo."),
            .init(section: "Getting Started", question: "How do I log a feeding?", answer: "Tap the green Log Meal button on any dog's card. Choose the meal type — Breakfast, Lunch, Dinner, Morning, Afternoon, Evening, Snack, Treat, or Custom — and confirm. The card updates immediately."),
            .init(section: "Getting Started", question: "Can I log a meal for all dogs at once?", answer: "Yes. When you have 2 or more dogs, a fork icon appears in the top-right of the dashboard next to the + button. Tap it to open the Feed All Dogs sheet and log the same meal for everyone in one tap."),
            .init(section: "Getting Started", question: "Can I undo a meal I just logged?", answer: "Yes. After logging a meal, a brief Undo banner appears at the bottom of the card. Tap Undo within a few seconds to remove the entry and restore any food portion that was deducted."),
            .init(section: "Getting Started", question: "How do I edit a dog's info?", answer: "Go to Settings -> Dogs and tap the dog's name to open the edit sheet. You can update their name, birthday, photo, and food stock count."),
            .init(section: "Getting Started", question: "How do I delete a dog?", answer: "In Settings -> Dogs, swipe left on the dog's name and tap Delete. This also removes all of their feeding history."),
            .init(section: "Feeding Status", question: "What does overdue mean?", answer: "A dog is marked overdue when their last recorded feeding was longer ago than your overdue threshold. The default is 12 hours but you can adjust it in Settings -> Notifications -> Overdue After. Their card shows a red Last Fed badge as a reminder."),
            .init(section: "Feeding Status", question: "How far back does the history go?", answer: "All feeding events are kept forever. The card shows the 3 most recent feedings. Tap the dog's name or photo to see the full history."),
            .init(section: "Feeding Status", question: "Can I delete a feeding entry?", answer: "Yes. Tap a dog's card header to open their history, then swipe left on any entry. You'll see two options — Delete removes the entry only, and Delete & Restore Portion removes the entry and adds one portion back to the food stock."),
            .init(section: "Feeding Status", question: "Can I see when the next meal is due?", answer: "Yes, if you have feeding reminders set up. In Per Dog mode, each card shows a 'Next meal' row with the upcoming scheduled time. In All Dogs mode, a single line appears above all cards on the dashboard."),
            .init(section: "Feeding Notes", question: "Can I add a note when logging a feeding?", answer: "Yes. The Log Meal sheet has an optional notes field below the meal picker. Use it for anything useful — gave medication, only ate half, used a different food, etc."),
            .init(section: "Feeding Notes", question: "Where do I see the notes I added?", answer: "Notes appear in italic under the meal type in the feeding history. Tap a dog's card header to open their history."),
            .init(section: "Feeding Notes", question: "Can I edit a note after saving?", answer: "Yes. Tap any row in the feeding history to open the Edit Note sheet. The existing note is pre-filled -- update it and tap Save."),
            .init(section: "Food Stock", question: "What is Per Dog mode?", answer: "Each dog has their own food count. Every time you log a meal for a dog, their count decreases by one portion. Snack and Treat meals are the exception — they don't reduce the count. Set each dog's starting count in Settings -> Food Stock or by tapping the food stock cell on their card."),
            .init(section: "Food Stock", question: "What is Shared Pool mode?", answer: "One bag of food shared across all dogs. The pool decreases by one portion each time any dog is fed a meal. Snack and Treat logs do not reduce the shared count. Set the starting count in Settings -> Food Stock."),
            .init(section: "Food Stock", question: "What is Not Tracked?", answer: "Food stock tracking is turned off. No counts are shown and nothing is decremented when you log a meal."),
            .init(section: "Food Stock", question: "Do Snack or Treat meals count against the food stock?", answer: "No. Snack and Treat are logged in the history for reference but do not reduce the portion count. All other meal types (Morning, Evening, Breakfast, Lunch, Afternoon, Dinner, and Custom) do reduce the count by one."),
            .init(section: "Food Stock", question: "How do I restock?", answer: "Tap the Food Stock cell or the Low Food Stock banner on any dog's card to open the edit sheet and update the count directly."),
            .init(section: "Food Stock", question: "What is the Low Stock Threshold?", answer: "When a dog's stock drops to or below this number, a warning banner appears on their card and a push notification is sent (if enabled). Adjust it in Settings -> Notifications."),
            .init(section: "Feeding Reminders", question: "How do I set up feeding reminders?", answer: "Go to Settings -> Feeding Reminders. Choose a schedule mode: Off, All Dogs, or Per Dog. Then add one or more daily reminder times."),
            .init(section: "Feeding Reminders", question: "What is All Dogs mode?", answer: "One set of reminder times applies to every dog. You get a single notification at each time reminding you to feed all your dogs."),
            .init(section: "Feeding Reminders", question: "What is Per Dog mode?", answer: "Each dog has their own reminder schedule. Tap the dog's name in Settings -> Feeding Reminders (or tap the dog's name in Settings -> Dogs) to set their individual times."),
            .init(section: "Feeding Reminders", question: "How many reminder times can I set?", answer: "Up to 3 daily reminder times per schedule. Most households need a morning and evening reminder, but a midday one is available too."),
            .init(section: "Feeding Reminders", question: "Will reminders stop firing if I already fed my dog?", answer: "Yes. When you log a feeding, the next scheduled reminder for that dog is automatically cancelled. Any later reminders that day still fire as normal. Reminders are fully restored the next time you open the app."),
            .init(section: "Widget", question: "How do I add the widget?", answer: "Long-press the home screen until icons wiggle, tap the + button in the top-left corner, search for Did I Feed, choose a size, and tap Add Widget."),
            .init(section: "Widget", question: "What do the widget sizes show?", answer: "Small: your most overdue dog with their last-fed time. Medium: up to 3 dogs with fed/overdue status. Lock screen widgets show a quick count or the most overdue dog."),
            .init(section: "Widget", question: "Why does the widget show old data?", answer: "The widget refreshes automatically every hour. When you log a feeding in the app, the widget updates immediately."),
            .init(section: "Widget", question: "What happens when I tap the widget?", answer: "The small and medium widgets open the Log Meal sheet for the tapped dog directly. The lock screen widgets open the app dashboard."),
            .init(section: "Siri & Shortcuts", question: "How do I log a feeding with Siri?", answer: "Say \"Log [dog's name]'s feeding in Did I Feed\". Siri will confirm the meal and log it instantly — no need to open the app."),
            .init(section: "Siri & Shortcuts", question: "How do I check if my dog has been fed?", answer: "Say \"Did I feed [dog's name] in Did I Feed\". Siri will tell you when they were last fed and whether they're overdue."),
            .init(section: "Siri & Shortcuts", question: "How do I update food stock with Siri?", answer: "Say \"Update [dog's name]'s food stock in Did I Feed\". Siri will ask how many portions you added and update the count."),
            .init(section: "Siri & Shortcuts", question: "Can I add these as shortcuts in the Shortcuts app?", answer: "Yes. Open the Shortcuts app, tap the + button, and search for Did I Feed to see all available actions. You can also go to iPhone Settings -> Siri & Search -> Did I Feed to manage them."),
            .init(section: "iCloud Sync", question: "Does my data sync across devices?", answer: "Yes. If everyone in your household is signed into the same iCloud account, feedings, food stock, and dog info stay in sync across all your iPhones automatically. Changes usually appear within about a minute."),
            .init(section: "iCloud Sync", question: "What if two people log a feeding at the same time?", answer: "Both feedings are saved. You may see two entries close together in the history — that's the accurate record of what happened."),
            .init(section: "iCloud Sync", question: "Does the widget stay in sync too?", answer: "Yes. The widget shows the same data as the app, so it reflects the most recent feeding logged by anyone in the household."),
            .init(section: "Notifications", question: "What is the Low Stock Push Alert?", answer: "A notification sent when a dog's food stock drops to or below the Low Stock Threshold after logging a feeding."),
            .init(section: "Notifications", question: "What is the Birthday Push Alert?", answer: "A notification sent on your dog's birthday each year, based on the birthday you entered when adding them."),
            .init(section: "Notifications", question: "What is the Low Stock UI Warning?", answer: "An orange banner that appears on the dog's card when stock is low. This is separate from the push notification."),
            .init(section: "Notifications", question: "I'm not receiving notifications. What should I check?", answer: "Go to iPhone Settings -> Notifications -> Did I Feed and make sure notifications are allowed. Also confirm the toggles are on in the app's Settings -> Notifications."),
        ]
    }
}

private struct FAQRow: View {
    let question: String
    let answer: String
    var startExpanded: Bool = false
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(answer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        } label: {
            Text(question)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .onAppear { if startExpanded { expanded = true } }
    }
}
