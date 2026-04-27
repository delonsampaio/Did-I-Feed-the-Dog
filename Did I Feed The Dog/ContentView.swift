import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        DashboardView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Pet.self, FeedingEvent.self], inMemory: true)
}
