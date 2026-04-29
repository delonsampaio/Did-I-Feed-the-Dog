import SwiftUI
import SwiftData

// Invisible view that keeps widget UserDefaults in sync with SwiftData.
// Placed as a background on the root ContentView so it observes changes
// for the full app lifetime, including CloudKit sync arrivals.
struct WidgetRefresher: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var pets: [Pet]
    @Query private var feedingEvents: [FeedingEvent]

    var body: some View {
        Color.clear
            .onAppear {
                WidgetDataWriter.write(from: modelContext)
            }
            .onChange(of: pets) { _, _ in
                WidgetDataWriter.write(from: modelContext)
            }
            .onChange(of: feedingEvents) { _, _ in
                WidgetDataWriter.write(from: modelContext)
            }
    }
}
