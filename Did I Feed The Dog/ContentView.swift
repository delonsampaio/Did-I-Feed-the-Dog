import SwiftUI
import SwiftData

struct ContentView: View {
    @Binding var deepLinkPetId: UUID?
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    var body: some View {
        DashboardView(deepLinkPetId: $deepLinkPetId)
            .onAppear { appearanceMode.apply() }
            .onChange(of: appearanceMode) { _, new in new.apply() }
    }
}

#Preview {
    ContentView(deepLinkPetId: .constant(nil))
        .modelContainer(for: [Pet.self, FeedingEvent.self], inMemory: true)
}
