import CloudKit
import CoreData
import SwiftData
import SwiftUI

/// Dashboard card for a dog shared with the user. Mirrors PetCard's layout (photo, Last Fed
/// badge, Low Food Stock / due-medication banners, stats, recent history, fasting banner) so a
/// dog looks the same before and after sharing. Logging, restocking, editing, the fasting
/// toggle, and history navigation are all available to any participant regardless of their own
/// Pro status — only the owner needed Pro to create the share in the first place. Only "Share
/// this dog"/"Stop sharing" stay owner-gated.
struct SharedPetCard: View {
    @AppStorage("lowStockUIWarning", store: .sharedGroup) private var lowStockUIWarning = true
    @AppStorage("lowStockThreshold", store: .sharedGroup) private var lowStockThreshold = 5
    @AppStorage("reminderMode", store: .sharedGroup)      private var reminderMode: ReminderMode = .none

    @Environment(\.modelContext) private var modelContext
    let dog: any DogDisplayable

    @State private var shareToPresent: CKShare?
    @State private var isBusy = false
    @State private var showStopSharingConfirm = false
    @State private var showShareError = false
    @State private var shareErrorMessage = ""
    @State private var showLogFeeding = false
    @State private var showLogMedication = false
    @State private var showRestockSheet = false
    @State private var showEditSheet = false

    private var sharedPet: SharedPet? { dog as? SharedPet }

    private var isOwner: Bool {
        guard SharingFeatureFlag.isFoundationEnabled, let pet = sharedPet else { return false }
        let zoneName = CKRecordMapper.zoneID(forRoot: pet).zoneName
        return SharedSyncEngine.shared.isOwner(ofZoneNamed: zoneName)
    }

    private var medications: [SharedMedication] {
        Array((sharedPet?.medications as? Set<SharedMedication>) ?? [])
    }

    private var dueMedications: [SharedMedication] {
        medications.filter(\.isDue)
    }

    private var hasDueMedications: Bool { !dueMedications.isEmpty }

    private var medicationBannerTitle: String {
        let due = dueMedications
        if due.count == 1 { return due[0].name }
        return "\(due.count) meds due"
    }

    private var recentEvents: [SharedFeedingEvent] {
        let events = (sharedPet?.feedingEvents as? Set<SharedFeedingEvent>) ?? []
        return Array(events.sorted { $0.timestamp > $1.timestamp }.prefix(3))
    }

    private var currentStockCount: Int {
        sharedPet?.effectiveFoodStockCount ?? 0
    }

    private var isLowStock: Bool {
        guard lowStockUIWarning, sharedPet != nil else { return false }
        return currentStockCount <= lowStockThreshold
    }

    private var lastFedBadgeColor: Color {
        dog.isFeedingOverdue ? Color(.systemRed).opacity(0.15) : Color(.systemGreen).opacity(0.15)
    }

    private var lastFedTextColor: Color {
        dog.isFeedingOverdue ? .red : .green
    }

    private var lastFedLabel: String {
        guard let lastDate = dog.lastFeedingDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastDate, relativeTo: .now)
    }

    private var nextMealInfo: (value: String, unit: String)? {
        guard reminderMode == .perDog else { return nil }
        return nextMealLabel(from: dog.feedingScheduleTimes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let pet = sharedPet {
                NavigationLink(value: pet) { headerRow }
                    .buttonStyle(.plain)
            } else {
                headerRow
            }

            if isLowStock || hasDueMedications {
                VStack(spacing: 6) {
                    if isLowStock {
                        Button { showRestockSheet = true } label: { lowStockBanner }
                            .buttonStyle(.plain)
                    }
                    if hasDueMedications {
                        Button { showLogMedication = true } label: { medicationBanner }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            statsRow

            if !recentEvents.isEmpty {
                if let pet = sharedPet {
                    NavigationLink(value: pet) { miniHistory }
                        .buttonStyle(.plain)
                } else {
                    miniHistory
                }
            }

            if dog.isFasting {
                HStack {
                    Image(systemName: "exclamationmark.octagon.fill")
                    Text("DO NOT FEED — FASTING")
                        .font(.caption).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            if SharingFeatureFlag.isFoundationEnabled, sharedPet != nil {
                actionButtons
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
        .contextMenu {
            if let pet = sharedPet {
                Button {
                    pet.isFasting.toggle()
                    try? pet.managedObjectContext?.save()
                } label: {
                    Label(pet.isFasting ? "End Fasting" : "Start Fasting",
                          systemImage: pet.isFasting ? "fork.knife" : "exclamationmark.octagon")
                }
                Button {
                    showEditSheet = true
                } label: {
                    Label("Edit Dog", systemImage: "pencil")
                }
                Button {
                    showRestockSheet = true
                } label: {
                    Label("Update Food Stock", systemImage: "shippingbox")
                }
            }
            if let pet = sharedPet, isOwner {
                Button {
                    Task { await manageSharing(for: pet) }
                } label: {
                    Label("Share this dog", systemImage: "person.2.badge.plus")
                }
                Button("Stop sharing", role: .destructive) {
                    showStopSharingConfirm = true
                }
            }
        }
        .confirmationDialog("Stop sharing this dog?", isPresented: $showStopSharingConfirm, titleVisibility: .visible) {
            Button("Stop Sharing", role: .destructive) {
                if let pet = sharedPet { Task { await stopSharing(pet) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll keep this dog and its history. Anyone you shared it with will lose access.")
        }
        .sheet(item: $shareToPresent) { share in
            CloudSharingView(share: share)
        }
        .sheet(isPresented: $showLogFeeding) {
            if let pet = sharedPet {
                LogSharedFeedingSheet(pet: pet)
            }
        }
        .sheet(isPresented: $showLogMedication) {
            if let pet = sharedPet {
                LogSharedMedicationSheet(pet: pet, medications: medications)
            }
        }
        .sheet(isPresented: $showRestockSheet) {
            if let pet = sharedPet {
                SharedRestockSheet(pet: pet)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let pet = sharedPet {
                EditSharedPetSheet(pet: pet)
            }
        }
        .alert("Couldn't share this dog", isPresented: $showShareError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareErrorMessage)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(dog.displayName)
                        .font(.title3).fontWeight(.bold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "person.2.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel("Shared dog")
                }
                let age = dog.ageString
                if !age.isEmpty {
                    Text(age)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            lastFedBadge
        }
        .padding(16)
    }

    private var avatar: some View {
        Group {
            if let data = dog.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFill()
            } else {
                Image(DefaultAvatars.defaultFor(id: dog.id))
                    .resizable().scaledToFill()
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var lastFedBadge: some View {
        VStack(spacing: 2) {
            Text("Last Fed")
                .font(.caption2).fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundStyle(lastFedTextColor)
            Text(lastFedLabel)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(lastFedBadgeColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dog.isFeedingOverdue
            ? "Last fed \(lastFedLabel), overdue"
            : "Last fed \(lastFedLabel)")
    }

    private var lowStockBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Low Food Stock")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.orange)
                Text("Only \(currentStockCount) portion\(currentStockCount == 1 ? "" : "s") remaining · Tap to restock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var medicationBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pill.fill")
                .foregroundStyle(.purple)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(medicationBannerTitle)
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.purple)
                Text("Tap to log dose")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var statsRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if sharedPet != nil {
                    Button {
                        showRestockSheet = true
                    } label: {
                        statCell(
                            title: "Food Stock",
                            value: "\(currentStockCount)",
                            unit: "portions",
                            accent: isLowStock ? .red : .primary,
                            statusLabel: isLowStock ? "low stock" : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double tap to edit food stock")
                }
                if let pet = sharedPet {
                    NavigationLink(value: pet) {
                        statCell(
                            title: "Today's Meals",
                            value: "\(dog.todaysFeedingCount)",
                            unit: "meals",
                            accent: .primary
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double tap to view meal history")
                } else {
                    statCell(
                        title: "Today's Meals",
                        value: "\(dog.todaysFeedingCount)",
                        unit: "meals",
                        accent: .primary
                    )
                }
            }
            if let info = nextMealInfo {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Next meal · \(info.value) · \(info.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func statCell(title: String, value: String, unit: String, accent: Color, statusLabel: String? = nil) -> some View {
        let label = statusLabel.map { "\(title): \(value) \(unit), \($0)" } ?? "\(title): \(value) \(unit)"
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2).fontWeight(.semibold)
                .textCase(.uppercase).foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value).font(.title2).fontWeight(.bold).foregroundStyle(accent)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var miniHistory: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.caption2).fontWeight(.semibold)
                .textCase(.uppercase).foregroundStyle(.secondary)
            ForEach(recentEvents, id: \.objectID) { event in
                HStack {
                    Text(MealType.emoji(for: event.mealType ?? "") + " " + (event.mealType ?? "Feeding"))
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(abbreviatedRelative(event.timestamp))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                showLogFeeding = true
            } label: {
                Label("Log Meal", systemImage: "fork.knife")
                    .font(.subheadline).fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if !medications.isEmpty {
                Button {
                    showLogMedication = true
                } label: {
                    Label("Log Medication", systemImage: "pill")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.purple)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func abbreviatedRelative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: .now)
    }

    private func manageSharing(for pet: SharedPet) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if let existing = try await ShareController.fetchShare(forRoot: pet) {
                shareToPresent = existing
            } else {
                shareToPresent = try await ShareController.makeShare(forRoot: pet)
            }
        } catch {
            shareErrorMessage = error.localizedDescription
            showShareError = true
        }
    }

    private func stopSharing(_ pet: SharedPet) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try SharePreparationController.migrateToOwned(sharedPet: pet, modelContext: modelContext)
            try await ShareController.stopSharing(forRoot: pet)
        } catch {
            shareErrorMessage = error.localizedDescription
            showShareError = true
        }
    }
}
