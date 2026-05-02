import SwiftUI
import SwiftData

struct ContentView: View {
    @Binding var deepLinkPetId: UUID?
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @Query private var pets: [Pet]

    @State private var showOnboarding = false

    var body: some View {
        DashboardView(deepLinkPetId: $deepLinkPetId)
            .onAppear { appearanceMode.apply() }
            .onChange(of: appearanceMode) { _, new in new.apply() }
            .task {
                if pets.isEmpty {
                    showOnboarding = true
                } else {
                    await NotificationManager.shared.requestAuthorization()
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView()
            }
    }
}

#Preview {
    ContentView(deepLinkPetId: .constant(nil))
        .modelContainer(for: [Pet.self, FeedingEvent.self], inMemory: true)
}
