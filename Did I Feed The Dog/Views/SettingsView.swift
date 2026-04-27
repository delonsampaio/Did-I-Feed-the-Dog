import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pet.name) private var pets: [Pet]

    @AppStorage("lowStockUIWarning")    private var lowStockUIWarning = true
    @AppStorage("lowStockPushEnabled")  private var lowStockPushEnabled = true
    @AppStorage("birthdayPushEnabled")  private var birthdayPushEnabled = true
    @AppStorage("lowStockThreshold")    private var lowStockThreshold = 5

    @State private var editingPet: Pet?
    @State private var showAddPet = false

    var body: some View {
        Form {
            petsSection
            foodStockSection
            notificationsSection
            safetySection
            aboutSection
        }
        .navigationTitle("Settings")
        .sheet(item: $editingPet) { pet in
            AddEditPetSheet(pet: pet)
        }
        .sheet(isPresented: $showAddPet) {
            AddEditPetSheet()
        }
    }

    private var petsSection: some View {
        Section("Dogs") {
            ForEach(pets) { pet in
                Button {
                    editingPet = pet
                } label: {
                    HStack {
                        Text(pet.name).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .onDelete(perform: deletePets)

            Button {
                showAddPet = true
            } label: {
                Label("Add Dog", systemImage: "plus.circle.fill")
            }
        }
    }

    private var foodStockSection: some View {
        Section("Food Stock Override") {
            ForEach(pets) { pet in
                HStack {
                    Text(pet.name)
                    Spacer()
                    Stepper("\(pet.foodStockCount) portions", value: Binding(
                        get: { pet.foodStockCount },
                        set: { pet.foodStockCount = max(0, $0) }
                    ), in: 0...999)
                }
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Low Stock UI Warning", isOn: $lowStockUIWarning)
            Toggle("Low Stock Push Alert", isOn: $lowStockPushEnabled)
            Toggle("Birthday Push Alert", isOn: $birthdayPushEnabled)
            HStack {
                Text("Low Stock Threshold")
                Spacer()
                Stepper("\(lowStockThreshold) portions", value: $lowStockThreshold, in: 1...50)
            }
        }
    }

    private var safetySection: some View {
        Section {
            NavigationLink(destination: SafetyGuideView()) {
                Label("Toxic Foods Guide", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deletePets(at offsets: IndexSet) {
        for index in offsets {
            let pet = pets[index]
            NotificationManager.shared.removeBirthdayNotification(for: pet)
            modelContext.delete(pet)
        }
    }
}
