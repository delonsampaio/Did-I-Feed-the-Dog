import SwiftUI
import SwiftData

struct ContentView: View {
    @Binding var deepLinkPetId: UUID?
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    private var resolvedColorScheme: ColorScheme {
        switch appearanceMode {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
        }
    }

    var body: some View {
        DashboardView(deepLinkPetId: $deepLinkPetId)
            .preferredColorScheme(resolvedColorScheme)
    }
}

#Preview {
    ContentView(deepLinkPetId: .constant(nil))
        .modelContainer(for: [Pet.self, FeedingEvent.self], inMemory: true)
}
