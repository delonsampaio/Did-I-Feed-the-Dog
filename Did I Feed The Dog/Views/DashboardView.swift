import AppIntents
import SwiftUI
import SwiftData

struct DashboardView: View {
    @Binding var deepLinkPetId: UUID?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pet.name) private var pets: [Pet]

    @AppStorage("reminderMode")            private var reminderMode: ReminderMode = .none
    @AppStorage("allDogsReminderTimesRaw") private var allDogsReminderTimesRaw = ""

    @State private var showAddPet = false
    @State private var showSettings = false
    @State private var deepLinkFeedingPet: Pet? = nil

    private var allDogsReminderTimes: [Int] {
        allDogsReminderTimesRaw.split(separator: ",").compactMap { Int($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(pets) { pet in
                        PetCard(pet: pet)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("My Dogs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddPet = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill").font(.title3)
                    }
                }
            }
            .navigationDestination(for: Pet.self) { pet in PetDetailView(pet: pet) }
            .sheet(isPresented: $showAddPet) { AddEditPetSheet() }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
            .sheet(item: $deepLinkFeedingPet) { pet in LogFeedingSheet(pet: pet) }
            .overlay {
                if pets.isEmpty {
                    ContentUnavailableView(
                        "No Dogs Yet",
                        systemImage: "pawprint.fill",
                        description: Text("Tap + to add your first dog.")
                    )
                }
            }
        }
        .onChange(of: deepLinkPetId) { _, newId in
            guard let id = newId else { return }
            deepLinkFeedingPet = pets.first { $0.id == id }
            deepLinkPetId = nil
        }
        .onAppear {
            NotificationManager.shared.rescheduleIfNeeded(
                reminderMode: reminderMode,
                allDogsReminderTimes: allDogsReminderTimes,
                pets: pets
            )
            DogFoodShortcuts.updateAppShortcutParameters()
        }
    }
}
