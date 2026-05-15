import SwiftUI
import SwiftData

struct ContentView: View {
    @Binding var deepLinkPetId: UUID?
    @AppStorage("appearanceMode", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog")) private var appearanceMode: AppearanceMode = .system
    @AppStorage("hasCompletedFirstLaunch", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog")) private var hasCompletedFirstLaunch = false
    @Query private var pets: [Pet]
    @Environment(EntitlementManager.self) private var entitlements

    @State private var showOnboarding = false

    var body: some View {
        DashboardView(deepLinkPetId: $deepLinkPetId)
            .onAppear { appearanceMode.apply() }
            .onChange(of: appearanceMode) { _, new in new.apply() }
            .task {
                // Free users always see onboarding so they get the pro pitch.
                // Pro users with synced dogs can skip it — they're reinstalling.
                if !hasCompletedFirstLaunch && (pets.isEmpty || !entitlements.isPro) {
                    showOnboarding = true
                } else {
                    hasCompletedFirstLaunch = true
                    await NotificationManager.shared.requestAuthorization()
                }
            }
            .onChange(of: pets) { _, newPets in
                // If CloudKit syncs dogs while onboarding is showing, only
                // auto-dismiss for Pro users — free users still need the pro pitch.
                if showOnboarding && !newPets.isEmpty && entitlements.isPro {
                    showOnboarding = false
                    hasCompletedFirstLaunch = true
                    Task { await NotificationManager.shared.requestAuthorization() }
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
