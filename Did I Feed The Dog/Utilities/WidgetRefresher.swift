import SwiftUI
import SwiftData

// Observes FeedingEvent changes so the widget file updates when meals are
// logged or deleted (including CloudKit sync from family members).
// Pet-list changes are handled in DashboardView.onChange(of: pets).
struct WidgetRefresher: View {
    @Query private var pets: [Pet]
    @Query private var feedingEvents: [FeedingEvent]

    var body: some View {
        Color.clear
            .onChange(of: feedingEvents) { _, _ in
                // Guard: don't overwrite the file with empty pets if @Query
                // hasn't loaded yet in this background view.
                if !pets.isEmpty { WidgetDataWriter.write(pets) }
            }
    }
}
