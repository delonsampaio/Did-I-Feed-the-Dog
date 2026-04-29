import SwiftUI
import SwiftData

// Observes FeedingEvent changes for the full app lifetime so the widget file
// stays current when meals are logged or deleted (including CloudKit sync from
// family members). Pet-list changes are handled directly in DashboardView.
struct WidgetRefresher: View {
    @Query private var pets: [Pet]
    @Query private var feedingEvents: [FeedingEvent]

    var body: some View {
        Color.clear
            .onChange(of: feedingEvents) { _, _ in
                WidgetDataWriter.write(pets)
            }
    }
}
