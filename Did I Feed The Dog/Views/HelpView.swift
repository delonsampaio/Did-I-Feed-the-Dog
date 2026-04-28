import SwiftUI

struct HelpView: View {
    var body: some View {
        List {
            gettingStartedSection
            feedingStatusSection
            notesSection
            foodStockSection
            feedingRemindersSection
            widgetSection
            notificationsSection
        }
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
                answer: "Tap the green Log Feeding button on any dog's card. Choose the meal type (Morning, Evening, etc.) and confirm. The card updates immediately."
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
                answer: "A dog is marked overdue when their last recorded feeding was more than 12 hours ago. Their card shows a red Last Fed badge as a reminder."
            )
            FAQRow(
                question: "How far back does the history go?",
                answer: "All feeding events are stored indefinitely. The card shows the 3 most recent feedings. Tap the dog's name or photo to see the full history."
            )
            FAQRow(
                question: "Can I delete a feeding entry?",
                answer: "Yes. Tap a dog's card header to open their history, then swipe left on any entry and tap Delete."
            )
        }
    }

    private var notesSection: some View {
        Section("Feeding Notes") {
            FAQRow(
                question: "Can I add a note when logging a feeding?",
                answer: "Yes. The Log Feeding sheet has an optional notes field below the meal picker. Use it for anything useful — gave medication, only ate half, used a different food, etc."
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
                answer: "Each dog has their own food count. Every time you log a feeding for a dog, their count decreases by one portion. Set each dog's starting count in Settings -> Food Stock or by tapping the food stock cell on their card."
            )
            FAQRow(
                question: "What is Shared Pool mode?",
                answer: "One bag of food shared across all dogs. The pool decreases by one portion each time any dog is fed. Set the starting count in Settings -> Food Stock."
            )
            FAQRow(
                question: "What is Not Tracked?",
                answer: "Food stock tracking is turned off. No counts are shown and nothing is decremented when you log a feeding."
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
                answer: "The small and medium widgets open the Log Feeding sheet for the tapped dog directly. The lock screen widgets open the app dashboard."
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
                answer: "Go to iPhone Settings -> Notifications -> Did I Feed The Dog and make sure notifications are allowed. Also confirm the toggles are on in the app's Settings -> Notifications."
            )
        }
    }
}

private struct FAQRow: View {
    let question: String
    let answer: String
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
    }
}
