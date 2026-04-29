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
            .onChange(of: feedingEvents) { _, newEvents in
                guard !pets.isEmpty else { return }
                WidgetDataWriter.write(pets, events: newEvents)
            }
            .onChange(of: pets) { _, newPets in
                guard !newPets.isEmpty else { return }
                UserDefaults(suiteName: WidgetDataWriter.groupID)?
                    .set(newPets.count, forKey: "debugPetsCount_refresher")
                WidgetDataWriter.write(newPets, events: feedingEvents)
            }
    }
}
