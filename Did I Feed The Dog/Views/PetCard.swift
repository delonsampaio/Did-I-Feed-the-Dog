import SwiftUI
import SwiftData

struct PetCard: View {
    @AppStorage("lowStockUIWarning", store: .sharedGroup) private var lowStockUIWarning = true
    @AppStorage("lowStockThreshold", store: .sharedGroup) private var lowStockThreshold = 5
    @AppStorage("stockMode", store: .sharedGroup)         private var stockMode: StockMode = .individual
    @AppStorage("sharedFoodStock", store: .sharedGroup)   private var sharedFoodStock = 0
    @AppStorage("reminderMode", store: .sharedGroup)      private var reminderMode: ReminderMode = .none

    @Environment(\.modelContext) private var modelContext
    @Environment(EntitlementManager.self) private var entitlements

    let pet: Pet
    var undoVersion: Int = 0
    var onFed: ((FeedingEvent, @escaping () -> Void) -> Void)? = nil
    @State private var showFeedSheet = false
    @State private var showOverdueTease = false
    @State private var showPaywall = false
    @State private var showEditSheet = false
    @State private var showQuickStockSheet = false
    @State private var showStockOutAlert = false
    @State private var showStockOutRestockSheet = false
    @State private var showMedicationSheet = false

    private var recentEvents: [FeedingEvent] {
        pet.recentFeedings(limit: 3)
    }

    private var lastFedBadgeColor: Color {
        pet.isFeedingOverdue ? Color(.systemRed).opacity(0.15) : Color(.systemGreen).opacity(0.15)
    }

    private var lastFedTextColor: Color {
        pet.isFeedingOverdue ? .red : .green
    }

    private var lastFedLabel: String {
        guard let lastDate = pet.lastFeedingDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastDate, relativeTo: .now)
    }

    private var currentStockCount: Int {
        stockMode == .shared ? sharedFoodStock : pet.foodStockCount
    }

    private var isLowStock: Bool {
        guard entitlements.isPro, lowStockUIWarning, stockMode != .none else { return false }
        return currentStockCount <= lowStockThreshold
    }

    private var dueMedications: [Medication] {
        (pet.medications ?? []).filter { $0.isDue }
    }

    private var hasDueMedications: Bool { !dueMedications.isEmpty }

    private var medicationBannerTitle: String {
        let due = dueMedications
        if due.count == 1 { return due[0].name }
        return "\(due.count) meds due"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: pet) { headerRow }
                .buttonStyle(.plain)

            if isLowStock || hasDueMedications {
                let bothVisible = isLowStock && hasDueMedications
                HStack(spacing: 8) {
                    if isLowStock {
                        Button { showQuickStockSheet = true } label: { lowStockBanner(compact: bothVisible) }
                            .buttonStyle(.plain)
                    }
                    if hasDueMedications {
                        Button { showMedicationSheet = true } label: { medicationBanner(compact: bothVisible) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            statsRow

            if !recentEvents.isEmpty {
                NavigationLink(value: pet) { miniHistory }
                    .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if showOverdueTease && !entitlements.isPro {
                Button { showPaywall = true } label: { overdueTeaseBanner }
                    .buttonStyle(.plain)
            }

            // Fasting Mode Banner (Item #22)
            if pet.isFasting {
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

            feedButton
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
        
        .contextMenu {
            Button(role: pet.isFasting ? .none : .destructive) {
                pet.isFasting.toggle()
                if pet.isFasting {
                    NotificationManager.shared.removeOverdueNotification(for: pet)
                    NotificationManager.shared.removePerDogReminders(for: pet)
                }
                // Triggers RemindersCoordinator on next dashboard appearance
                // so "All Dogs" reminder body excludes the fasting pet.
                AppSettings.needsReminderReschedule = true
                WidgetDataWriter.write(from: modelContext)
            } label: {
                Label(pet.isFasting ? "End Fasting" : "Start Fasting",
                      systemImage: pet.isFasting ? "fork.knife" : "exclamationmark.octagon")
            }

            Button {
                showEditSheet = true
            } label: {
                Label("Edit Dog", systemImage: "pencil")
            }
        }
        
        .sheet(isPresented: $showFeedSheet) {
            LogFeedingSheet(pet: pet, onLogged: { result in
                // Restore only what was actually deducted — not whatever the
                // meal type would notionally deduct. Custom meals with the
                // "Deduct a portion" toggle off must NOT credit a portion.
                let event = result.event
                let portionsToRestore = event.deductedPortionCount
                let undo: () -> Void = {
                    if portionsToRestore > 0 {
                        switch stockMode {
                        case .individual:
                            pet.foodStockCount = min(AppConstants.perPetStockCap, pet.foodStockCount + portionsToRestore)
                        case .shared:
                            AppSettings.sharedFoodStock = min(AppConstants.sharedStockCap, AppSettings.sharedFoodStock + portionsToRestore)
                        case .none: break
                        }
                    }
                    modelContext.delete(event)
                    pet.recomputeFeedingCache(excluding: [event])
                    NotificationManager.shared.rescheduleOverdueNotification(for: pet)
                    WidgetDataWriter.write(from: modelContext)
                    let allPets = (try? modelContext.fetch(FetchDescriptor<Pet>())) ?? []
                    NotificationManager.shared.updateBadgeCount(pets: allPets)
                }
                onFed?(event, undo)
                if entitlements.isPro && result.shouldPromptStockOut && AppSettings.stockOutPromptEnabled {
                    showStockOutAlert = true
                }
            })
        }
        .sheet(isPresented: $showEditSheet) {
            AddEditPetSheet(pet: pet)
        }
        .sheet(isPresented: $showQuickStockSheet) {
            if stockMode == .shared {
                QuickStockSheet(stockCount: $sharedFoodStock, title: "Shared Food Stock", petId: nil)
            } else {
                QuickStockSheet(stockCount: Binding(
                    get: { pet.foodStockCount },
                    set: { pet.foodStockCount = $0 }
                ), title: "\(pet.name ?? "Dog")'s Stock", petId: pet.id)
            }
        }
        .sheet(isPresented: $showStockOutRestockSheet) {
            if stockMode == .shared {
                QuickStockSheet(stockCount: $sharedFoodStock, title: "Shared Food Stock", petId: nil)
            } else {
                QuickStockSheet(stockCount: Binding(
                    get: { pet.foodStockCount },
                    set: { pet.foodStockCount = $0 }
                ), title: "\(pet.name ?? "Dog")'s Stock", petId: pet.id)
            }
        }
        .sheet(isPresented: $showMedicationSheet) {
            LogMedicationSheet(pet: pet, dueMedications: dueMedications)
        }
        .alert("Meal logged", isPresented: $showStockOutAlert) {
            Button("Update Stock Now") { showStockOutRestockSheet = true }
            Button("Remind Me Later", role: .cancel) { }
        } message: {
            Text("It looks like you're out of food — did you just open a new bag?")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(source: "overdueCard")
        }
        .onAppear { checkOverdueTease() }
        .onChange(of: pet.isFeedingOverdue) { _, isOverdue in
            if isOverdue { checkOverdueTease() }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            petAvatar
            VStack(alignment: .leading, spacing: 2) {
                Text(pet.name ?? "Unknown")
                    .font(.title3).fontWeight(.bold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                let age = pet.ageString
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

    private var petAvatar: some View {
        Group {
            if let data = pet.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFill()
            } else {
                Image(DefaultAvatars.defaultFor(id: pet.id))
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
        .accessibilityLabel(pet.isFeedingOverdue
            ? "Last fed \(lastFedLabel), overdue"
            : "Last fed \(lastFedLabel)")
    }

    private func lowStockBanner(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            if compact {
                Text("Low Stock")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Low Food Stock")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.orange)
                    Text("Only \(currentStockCount) portion\(currentStockCount == 1 ? "" : "s") remaining")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 12 : 10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func medicationBanner(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Text("💊").font(.subheadline).accessibilityHidden(true)
            if compact {
                Text(medicationBannerTitle)
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.purple)
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(medicationBannerTitle)
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.purple)
                    Text("Tap to log")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 12 : 10)
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var nextMealInfo: (value: String, unit: String)? {
        guard reminderMode == .perDog else { return nil }
        return nextMealLabel(from: pet.feedingScheduleTimes)
    }

    private var statsRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if entitlements.isPro && stockMode != .none {
                    Button {
                        showQuickStockSheet = true
                    } label: {
                        statCell(
                            title: stockMode == .shared ? "House Stock" : "Food Stock",
                            value: "\(currentStockCount)",
                            unit: "portions",
                            accent: isLowStock ? .red : .primary,
                            statusLabel: isLowStock ? "low stock" : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double tap to edit food stock")
                }
                NavigationLink(value: pet) {
                    statCell(
                        title: "Today's Meals",
                        value: "\(pet.todaysFeedingCount)",
                        unit: "meals",
                        accent: .primary
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Double tap to view meal history")
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
            ForEach(recentEvents) { event in
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

    private var feedButton: some View {
        Button {
            showFeedSheet = true
        } label: {
            Label(
                pet.isFasting ? "Fasting" : "Log Meal",
                systemImage: pet.isFasting ? "exclamationmark.octagon" : "fork.knife"
            )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(pet.isFasting ? Color.gray.opacity(0.3) : Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(pet.isFasting)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var overdueTeaseBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Want a notification next time?")
                    .font(.subheadline).fontWeight(.semibold)
                Text("Unlock Pro to get overdue alerts delivered to your phone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func checkOverdueTease() {
        guard !entitlements.isPro,
              pet.isFeedingOverdue,
              AppSettings.seenOverdueTeaseAt == nil else { return }
        AppSettings.seenOverdueTeaseAt = .now
        showOverdueTease = true
    }

    private func abbreviatedRelative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: .now)
    }
}

