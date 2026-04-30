import SwiftUI
import SwiftData

struct FeedAllDogsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("stockMode")             private var stockMode: StockMode = .individual
    @AppStorage("sharedFoodStock")       private var sharedFoodStock = 0
    @AppStorage("lowStockPushEnabled")   private var lowStockPushEnabled = true
    @AppStorage("lowStockThreshold")     private var lowStockThreshold = 5
    @AppStorage("reminderMode")          private var reminderMode: ReminderMode = .none
    @AppStorage("allDogsReminderTimesRaw") private var allDogsReminderTimesRaw = ""

    private var allDogsReminderTimes: [Int] {
        allDogsReminderTimesRaw.split(separator: ",").compactMap { Int($0) }
    }

    let pets: [Pet]
    @State private var selectedMealType: MealType = .morning
    @State private var customLabel = ""
    @State private var showCustomField = false
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                mealPicker

                if showCustomField {
                    TextField("Meal name (e.g. Medication)", text: $customLabel)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                }

                TextField("Add a note (optional)", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...3)
                    .padding(.horizontal)

                Spacer()
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .safeAreaInset(edge: .bottom) {
                confirmButton
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.bottom)
            }
            .navigationTitle("Feed All Dogs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationSizing(.page)
        .presentationDetents([.fraction(0.65), .large])
    }

    private var mealPicker: some View {
        let columns = [GridItem(.adaptive(minimum: 110))]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(MealType.presets, id: \.label) { meal in
                mealChip(meal)
            }
            customChip
        }
        .padding(.horizontal)
    }

    private func mealChip(_ meal: MealType) -> some View {
        let isSelected = selectedMealType == meal && !showCustomField
        return Button {
            selectedMealType = meal
            showCustomField = false
        } label: {
            VStack(spacing: 4) {
                Text(meal.emoji).font(.title2)
                Text(meal.label).font(.caption).fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.green.opacity(0.2) : Color(.secondarySystemBackground))
            .foregroundStyle(isSelected ? .green : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.green : .clear, lineWidth: 2)
            )
        }
    }

    private var customChip: some View {
        Button {
            showCustomField = true
            selectedMealType = .custom("")
        } label: {
            VStack(spacing: 4) {
                Text("✏️").font(.title2)
                Text("Custom").font(.caption).fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(showCustomField ? Color.blue.opacity(0.2) : Color(.secondarySystemBackground))
            .foregroundStyle(showCustomField ? .blue : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(showCustomField ? Color.blue : .clear, lineWidth: 2)
            )
        }
    }

    private var confirmButton: some View {
        Button(action: logForAll) {
            Label("Log Meal for All Dogs", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canConfirm ? Color.green : Color.gray.opacity(0.3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!canConfirm)
    }

    private var canConfirm: Bool {
        if showCustomField { return !customLabel.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private var resolvedMealLabel: String {
        showCustomField ? customLabel.trimmingCharacters(in: .whitespaces) : selectedMealType.label
    }

    private func logForAll() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let mealLabel = resolvedMealLabel
        let noteText = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let logger = LoggedBy.current
        let shouldDecrementStock = showCustomField || selectedMealType.decrementsStock

        for pet in pets {
            let event = FeedingEvent(mealType: mealLabel, notes: noteText, loggedBy: logger, pet: pet)
            modelContext.insert(event)

            if shouldDecrementStock {
                switch stockMode {
                case .individual:
                    pet.decrementStock()
                    if lowStockPushEnabled && pet.foodStockCount <= lowStockThreshold {
                        NotificationManager.shared.scheduleLowStockNotification(for: pet)
                    }
                case .shared:
                    sharedFoodStock = max(0, sharedFoodStock - 1)
                    if lowStockPushEnabled && sharedFoodStock <= lowStockThreshold {
                        NotificationManager.shared.scheduleLowStockNotification(for: pet, stockCount: sharedFoodStock)
                    }
                case .none:
                    break
                }
            }
        }

        NotificationManager.shared.suppressNextUpcomingReminder(
            reminderMode: reminderMode,
            for: pets.first!,
            allDogsReminderTimes: allDogsReminderTimes
        )

        WidgetDataWriter.write(from: modelContext)
        dismiss()
    }
}
