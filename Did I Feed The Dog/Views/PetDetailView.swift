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
    @State private var showFilters = false
    @State private var filterMealTypes: Set<String> = []
    @State private var filterLoggedBy: Set<String> = []
    @State private var filterStartDate: Date? = nil
    @State private var filterEndDate: Date? = nil
    @State private var sortAscending = false

    private enum HistoryTab { case meals, medications }

    // MARK: - Feeding

    private var availableMealTypes: [String] {
        let types = (pet.feedingEvents ?? []).compactMap { $0.mealType }.filter { !$0.isEmpty }
        return Array(Set(types)).sorted()
    }

    private var availableLoggers: [String] {
        let loggers = (pet.feedingEvents ?? []).compactMap { $0.loggedBy }.filter { !$0.isEmpty }
        return Array(Set(loggers)).sorted()
    }

    private var activeFilterCount: Int {
        (filterMealTypes.isEmpty ? 0 : 1) +
        (filterLoggedBy.isEmpty ? 0 : 1) +
        (filterStartDate != nil || filterEndDate != nil ? 1 : 0)
    }

    private var filteredGroupedEvents: [(date: Date, events: [FeedingEvent])] {
        var events = pet.feedingEvents ?? []
        if !filterMealTypes.isEmpty {
            events = events.filter { filterMealTypes.contains($0.mealType ?? "") }
        }
        if !filterLoggedBy.isEmpty {
            events = events.filter { filterLoggedBy.contains($0.loggedBy ?? "") }
        }
        if let start = filterStartDate {
            events = events.filter { $0.timestamp >= Calendar.current.startOfDay(for: start) }
        }
        if let end = filterEndDate {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end
            events = events.filter { $0.timestamp < endOfDay }
        }
        events.sort { sortAscending ? $0.timestamp < $1.timestamp : $0.timestamp > $1.timestamp }
        let grouped = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.timestamp) }
        return grouped.sorted { sortAscending ? $0.key < $1.key : $0.key > $1.key }.map { (date: $0.key, events: $0.value) }
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
            ToolbarItem(placement: .topBarTrailing) {
                if selectedTab == .meals {
                    Button { showFilters = true } label: {
                        Image(systemName: activeFilterCount > 0
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                        .foregroundStyle(activeFilterCount > 0 ? Color.accentColor : .primary)
                    }
                    .accessibilityLabel(activeFilterCount > 0 ? "Filters active — \(activeFilterCount)" : "Filter meals")
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
        .sheet(isPresented: $showFilters) {
            MealFilterSheet(
                filterMealTypes: $filterMealTypes,
                filterLoggedBy: $filterLoggedBy,
                filterStartDate: $filterStartDate,
                filterEndDate: $filterEndDate,
                sortAscending: $sortAscending,
                availableMealTypes: availableMealTypes,
                availableLoggers: availableLoggers
            )
        }
    }

    // MARK: - Meals tab

    @ViewBuilder
    private var mealsContent: some View {
        let groups = filteredGroupedEvents
        let hasAnyEvents = !(pet.feedingEvents ?? []).isEmpty
        if groups.isEmpty && !hasAnyEvents {
            ContentUnavailableView(
                "No Meals Yet",
                systemImage: "fork.knife",
                description: Text("Tap Log Meal on \(pet.name ?? "Unknown")'s card to get started.")
            )
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        } else if groups.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("No meals match the current filters.")
            )
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        } else {
            ForEach(groups, id: \.date) { group in
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

// MARK: - Filter sheet

private struct MealFilterSheet: View {
    @Binding var filterMealTypes: Set<String>
    @Binding var filterLoggedBy: Set<String>
    @Binding var filterStartDate: Date?
    @Binding var filterEndDate: Date?
    @Binding var sortAscending: Bool
    let availableMealTypes: [String]
    let availableLoggers: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var hasStartDate = false
    @State private var hasEndDate = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var endDate = Date()

    private var isClean: Bool {
        filterMealTypes.isEmpty && filterLoggedBy.isEmpty &&
        filterStartDate == nil && filterEndDate == nil && !sortAscending
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort Order") {
                    Picker("Sort", selection: $sortAscending) {
                        Text("Newest First").tag(false)
                        Text("Oldest First").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if !availableMealTypes.isEmpty {
                    Section("Meal Type") {
                        ForEach(availableMealTypes, id: \.self) { type in
                            Toggle(type, isOn: Binding(
                                get: { filterMealTypes.contains(type) },
                                set: { if $0 { filterMealTypes.insert(type) } else { filterMealTypes.remove(type) } }
                            ))
                        }
                    }
                }

                if availableLoggers.count > 1 {
                    Section("Logged By") {
                        ForEach(availableLoggers, id: \.self) { logger in
                            Toggle(logger, isOn: Binding(
                                get: { filterLoggedBy.contains(logger) },
                                set: { if $0 { filterLoggedBy.insert(logger) } else { filterLoggedBy.remove(logger) } }
                            ))
                        }
                    }
                }

                Section("Date Range") {
                    Toggle("From date", isOn: $hasStartDate.animation())
                    if hasStartDate {
                        DatePicker("From", selection: $startDate, in: ...Date(), displayedComponents: .date)
                            .onChange(of: startDate) { _, v in filterStartDate = v }
                    }
                    Toggle("To date", isOn: $hasEndDate.animation())
                    if hasEndDate {
                        DatePicker("To", selection: $endDate, in: ...Date(), displayedComponents: .date)
                            .onChange(of: endDate) { _, v in filterEndDate = v }
                    }
                }
            }
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear All") {
                        filterMealTypes = []
                        filterLoggedBy = []
                        filterStartDate = nil
                        filterEndDate = nil
                        sortAscending = false
                        hasStartDate = false
                        hasEndDate = false
                    }
                    .disabled(isClean)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            hasStartDate = filterStartDate != nil
            hasEndDate = filterEndDate != nil
            if let s = filterStartDate { startDate = s }
            if let e = filterEndDate { endDate = e }
        }
        .onChange(of: hasStartDate) { _, show in
            filterStartDate = show ? startDate : nil
        }
        .onChange(of: hasEndDate) { _, show in
            filterEndDate = show ? endDate : nil
        }
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
