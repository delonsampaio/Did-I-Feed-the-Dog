import SwiftUI
import SwiftData
import StoreKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @Query(sort: \Pet.name) private var pets: [Pet]

    @AppStorage("lowStockUIWarning")    private var lowStockUIWarning = true
    @AppStorage("lowStockPushEnabled")  private var lowStockPushEnabled = true
    @AppStorage("birthdayPushEnabled")  private var birthdayPushEnabled = true
    @AppStorage("lowStockThreshold")    private var lowStockThreshold = 5
    @AppStorage("stockMode")            private var stockMode: StockMode = .individual
    @AppStorage("sharedFoodStock")      private var sharedFoodStock = 0

    @State private var editingPet: Pet?
    @State private var showAddPet = false

    var body: some View {
        Form {
            petsSection
            foodStockSection
            notificationsSection
            safetySection
            supportSection
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
        Section("Food Stock") {
            Picker("Tracking Mode", selection: $stockMode) {
                ForEach(StockMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            if stockMode == .individual {
                ForEach(pets) { pet in
                    Stepper(value: Binding(
                        get: { pet.foodStockCount },
                        set: { pet.foodStockCount = max(0, $0) }
                    ), in: 0...999) {
                        HStack {
                            Text(pet.name)
                            Spacer()
                            Text("\(pet.foodStockCount) portions")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } else if stockMode == .shared {
                Stepper(value: $sharedFoodStock, in: 0...9999) {
                    HStack {
                        Text("Shared Pool")
                        Spacer()
                        Text("\(sharedFoodStock) portions")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Low Stock UI Warning", isOn: $lowStockUIWarning)
            Toggle("Low Stock Push Alert", isOn: $lowStockPushEnabled)
            Toggle("Birthday Push Alert", isOn: $birthdayPushEnabled)
            Stepper(value: $lowStockThreshold, in: 1...50) {
                HStack {
                    Text("Low Stock Threshold")
                    Spacer()
                    Text("\(lowStockThreshold) portions")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var safetySection: some View {
        Section {
            NavigationLink(destination: SafetyGuideView()) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.red)
                            .frame(width: 36, height: 36)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Toxic Foods Guide")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text("23 foods to keep away from your dog")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Safety Guide")
        } footer: {
            Text("Your two-for-one: a feeding tracker and a pet safety reference — all in one app.")
        }
    }

    private var supportSection: some View {
        Section("Support") {
            Button {
                requestReview()
            } label: {
                Label("Rate the App", systemImage: "star.fill")
                    .foregroundStyle(.orange)
            }

            ShareLink(
                item: URL(string: "https://apps.apple.com/app/id0")!,
                message: Text("Track your dog's feedings and keep them safe with Did I Feed the Dog?")
            ) {
                Label("Invite Family Member", systemImage: "person.badge.plus")
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
