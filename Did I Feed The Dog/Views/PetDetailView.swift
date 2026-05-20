import SwiftUI
import SwiftData

struct PetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let pet: Pet

    @Environment(EntitlementManager.self) private var entitlements

    @AppStorage("stockMode", store: .sharedGroup)       private var stockMode: StockMode = .individual
    @AppStorage("sharedFoodStock", store: .sharedGroup) private var sharedFoodStock = 0

    @State private var selectedTab: HistoryTab = .meals
    @State private var editingEvent: FeedingEvent?
    @State private var showAddMedication = false
    @State private var editingMedication: Medication?
    @State private var pendingDeleteMedId: UUID?
    @State private var deleteTask: Task<Void, Never>?

    private enum HistoryTab { case meals, medications }

    // MARK: - Feeding

    private var groupedEvents: [(date: Date, events: [FeedingEvent])] {
        let sorted = (pet.feedingEvents ?? []).sorted { $0.timestamp > $1.timestamp }
        let grouped = Dictionary(grouping: sorted) {
            Calendar.current.startOfDay(for: $0.timestamp)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, events: $0.value) }
    }

    // MARK: - Medication logs

    private var allMedLogs: [(date: Date, logs: [MedicationLog])] {
        let logs = (pet.medications ?? [])
            .flatMap { $0.logs ?? [] }
            .sorted { $0.timestamp > $1.timestamp }
        let grouped = Dictionary(grouping: logs) {
            Calendar.current.startOfDay(for: $0.timestamp)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, logs: $0.value) }
    }

    // MARK: - Formatters

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let sectionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    // MARK: - Body

    var body: some View {
        List {
            if selectedTab == .meals {
                mealsContent
            } else {
                medicationsContent
            }
        }
        .navigationTitle(pet.name ?? "Unknown")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("History", selection: $selectedTab) {
                    Text("Meals").tag(HistoryTab.meals)
                    Text("Medications").tag(HistoryTab.medications)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if selectedTab == .meals {
                    EditButton()
                } else {
                    Button { showAddMedication = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $editingEvent) { event in
            EditEventSheet(event: event)
        }
        .sheet(isPresented: $showAddMedication) {
            AddEditMedicationSheet(pet: pet, medication: nil)
        }
        .sheet(item: $editingMedication) { med in
            AddEditMedicationSheet(pet: pet, medication: med)
        }
    }

    // MARK: - Meals tab

    @ViewBuilder
    private var mealsContent: some View {
        if groupedEvents.isEmpty {
            ContentUnavailableView(
                "No Meals Yet",
                systemImage: "fork.knife",
                description: Text("Tap Log Meal on \(pet.name ?? "Unknown")'s card to get started.")
            )
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        } else {
            ForEach(groupedEvents, id: \.date) { group in
                Section(header: Text(sectionTitle(for: group.date))) {
                    ForEach(group.events) { event in
                        Button { editingEvent = event } label: {
                            eventRow(event)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(event.mealType ?? "Feeding"), \(Self.timeFormatter.string(from: event.timestamp))\((event.loggedBy ?? "").isEmpty ? "" : ", by \(event.loggedBy!)")")
                        .accessibilityHint("Double tap to edit note")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteEvent(event, restoreStock: false)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            if entitlements.isPro && stockMode != .none && event.actuallyDeductedStock {
                                Button {
                                    deleteEvent(event, restoreStock: true)
                                } label: {
                                    Label("Delete & Restore Portion", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.blue)
                            }
                            Button {
                                editingEvent = event
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                    .onDelete { offsets in
                        deleteEvents(group.events, at: offsets)
                    }
                }
            }
        }
    }

    // MARK: - Medications tab

    @ViewBuilder
    private var medicationsContent: some View {
        let medications = (pet.medications ?? []).filter { $0.id != pendingDeleteMedId }

        Section("Medications") {
            ForEach(medications) { med in
                Button { editingMedication = med } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(med.name)
                                .foregroundStyle(.primary)
                            Text(med.dose.isEmpty ? med.frequencyLabel : "\(med.dose) · \(med.frequencyLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        scheduleMedicationDelete(med)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            if let id = pendingDeleteMedId,
               let name = (pet.medications ?? []).first(where: { $0.id == id })?.name {
                HStack {
                    Text("\"\(name)\" will be deleted")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Undo") {
                        deleteTask?.cancel()
                        pendingDeleteMedId = nil
                    }
                    .foregroundStyle(.purple)
                    .fontWeight(.semibold)
                }
            }
            Button { showAddMedication = true } label: {
                Label("Add Medication", systemImage: "plus.circle.fill")
            }
        }

        ForEach(allMedLogs, id: \.date) { group in
            Section(header: Text(sectionTitle(for: group.date))) {
                ForEach(group.logs) { log in
                    medLogRow(log)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteMedLog(log)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func scheduleMedicationDelete(_ med: Medication) {
        deleteTask?.cancel()
        pendingDeleteMedId = med.id
        deleteTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            NotificationManager.shared.removeMedicationReminder(for: med)
            modelContext.delete(med)
            try? modelContext.save()
            pendingDeleteMedId = nil
        }
    }

    // MARK: - Row views

    private func eventRow(_ event: FeedingEvent) -> some View {
        HStack(spacing: 12) {
            Text(MealType.emoji(for: event.mealType ?? ""))
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.mealType ?? "Feeding")
                    .font(.subheadline).fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(Self.timeFormatter.string(from: event.timestamp))
                    if let by = event.loggedBy, !by.isEmpty {
                        Text("·")
                        Text("by \(by)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !event.notes.isEmpty {
                    Text(event.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            Spacer()
            Text(Self.relativeFormatter.localizedString(for: event.timestamp, relativeTo: .now))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func medLogRow(_ log: MedicationLog) -> some View {
        HStack(spacing: 12) {
            Text("💊")
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(log.medication?.name ?? "Medication")
                        .font(.subheadline).fontWeight(.medium)
                    if let dose = log.medication?.dose, !dose.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(dose)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Text(Self.timeFormatter.string(from: log.timestamp))
                    if !log.loggedBy.isEmpty {
                        Text("·")
                        Text("by \(log.loggedBy)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !log.notes.isEmpty {
                    Text(log.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            Spacer()
            Text(Self.relativeFormatter.localizedString(for: log.timestamp, relativeTo: .now))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date)     { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return Self.sectionDateFormatter.string(from: date)
    }

    private func deleteEvent(_ event: FeedingEvent, restoreStock: Bool) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if restoreStock, event.actuallyDeductedStock {
            switch stockMode {
            case .individual:
                pet.foodStockCount = min(AppConstants.perPetStockCap, pet.foodStockCount + 1)
            case .shared:
                sharedFoodStock = min(AppConstants.sharedStockCap, sharedFoodStock + 1)
            case .none:
                break
            }
        }
        modelContext.delete(event)
        pet.recomputeFeedingCache(excluding: [event])
        NotificationManager.shared.rescheduleOverdueNotification(for: pet)
        WidgetDataWriter.write(from: modelContext)
        refreshBadge()
    }

    private func deleteEvents(_ events: [FeedingEvent], at offsets: IndexSet) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let toDelete = offsets.map { events[$0] }
        for event in toDelete { modelContext.delete(event) }
        pet.recomputeFeedingCache(excluding: toDelete)
        NotificationManager.shared.rescheduleOverdueNotification(for: pet)
        WidgetDataWriter.write(from: modelContext)
        refreshBadge()
    }

    private func deleteMedLog(_ log: MedicationLog) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let med = log.medication {
            // Roll back lastGivenDate to the previous log's timestamp if this was the most recent
            let remaining = (med.logs ?? []).filter { $0.id != log.id }.sorted { $0.timestamp > $1.timestamp }
            med.lastGivenDate = remaining.first?.timestamp
        }
        modelContext.delete(log)
    }

    private func refreshBadge() {
        let pets = (try? modelContext.fetch(FetchDescriptor<Pet>())) ?? []
        NotificationManager.shared.updateBadgeCount(pets: pets)
    }
}

// MARK: - Edit event sheet

private struct EditEventSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let event: FeedingEvent

    @State private var noteText = ""
    @State private var mealType: MealType = .custom("")
    @State private var customMealText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Type") {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.presets, id: \.label) { type in
                            Text(type.label).tag(type)
                        }
                        Text("Custom").tag(MealType.custom(customMealText))
                    }
                    .pickerStyle(.menu)

                    if case .custom = mealType {
                        TextField("Custom Meal Name", text: $customMealText)
                            .onChange(of: customMealText) { _, newText in
                                mealType = .custom(newText)
                            }
                    }
                }

                Section("Notes") {
                    TextField("Add a note (optional)", text: $noteText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Feeding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newLabel = mealType.label.trimmingCharacters(in: .whitespacesAndNewlines)
                        event.mealType = newLabel.isEmpty ? "Feeding" : newLabel
                        event.notes = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        WidgetDataWriter.write(from: modelContext)
                        dismiss()
                    }
                }
            }
            .onAppear {
                noteText = event.notes
                let currentLabel = event.mealType ?? "Feeding"
                let matchedPreset = MealType.presets.first { $0.label == currentLabel }
                if let preset = matchedPreset {
                    mealType = preset
                } else {
                    customMealText = currentLabel
                    mealType = .custom(currentLabel)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
