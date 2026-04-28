import SwiftUI
import SwiftData

struct ContentView: View {
    @Binding var deepLinkPetId: UUID?

    var body: some View {
        DashboardView(deepLinkPetId: $deepLinkPetId)
    }
}

#Preview {
    ContentView(deepLinkPetId: .constant(nil))
        .modelContainer(for: [Pet.self, FeedingEvent.self], allowsSave: false)
}
