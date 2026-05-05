import SwiftUI
import SwiftData

struct ContentView: View {
    @Binding var deepLinkPetId: UUID?
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("hasCompletedFirstLaunch") private var hasCompletedFirstLaunch = false
    @Query private var pets: [Pet]

    @State private var showOnboarding = false

    var body: some View {
        DashboardView(deepLinkPetId: $deepLinkPetId)
            .onAppear { appearanceMode.apply() }
            .onChange(of: appearanceMode) { _, new in new.apply() }
            .task {
                // Only show onboarding the first time the user opens the app.
                // Without the persisted flag, a fresh install on a second
                // device (where CloudKit hasn't synced pets yet) would briefly
                // see pets.isEmpty and trigger onboarding before sync arrives.
                if !hasCompletedFirstLaunch && pets.isEmpty {
                    showOnboarding = true
                } else {
                    hasCompletedFirstLaunch = true
                    await NotificationManager.shared.requestAuthorization()
                }
            }
            .fullScreenCover(isPresented: $showOnboarding, onDismiss: {
                hasCompletedFirstLaunch = true
            }) {
                OnboardingView()
            }
    }
}

#Preview {
    ContentView(deepLinkPetId: .constant(nil))
        .modelContainer(for: [Pet.self, FeedingEvent.self], inMemory: true)
}
