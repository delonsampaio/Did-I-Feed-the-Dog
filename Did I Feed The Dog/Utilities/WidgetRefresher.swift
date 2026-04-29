import SwiftUI
import SwiftData

// Observes FeedingEvent changes (CloudKit sync of feedings from other family members)
// and keeps the widget file up to date. Pet changes are handled in DashboardView.
struct WidgetRefresher: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var feedingEvents: [FeedingEvent]

    var body: some View {
        Color.clear
            .onChange(of: feedingEvents) { _, _ in
                WidgetDataWriter.write(from: modelContext)
            }
    }
}
