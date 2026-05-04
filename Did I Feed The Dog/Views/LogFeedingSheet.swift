import SwiftUI
import SwiftData

struct LogFeedingSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lowStockPushEnabled")     private var lowStockPushEnabled = true
    @AppStorage("lowStockThreshold")       private var lowStockThreshold = 5
    @AppStorage("stockMode")               private var stockMode: StockMode = .individual
    @AppStorage("sharedFoodStock")         private var sharedFoodStock = 0
    @AppStorage("reminderMode")            private var reminderMode: ReminderMode = .none
    @AppStorage("allDogsReminderTimesRaw") private var allDogsReminderTimesRaw = ""

    private var allDogsReminderTimes: [Int] {
        allDogsReminderTimesRaw.split(separator: ",").compactMap { Int($0) }
    }

    let pet: Pet
    var onLogged: ((FeedingEvent) -> Void)? = nil
    @State private var selectedMealType: MealType = .morning
    @State private var customLabel = ""
    @State private var showCustomField = false
    @State private var notes = ""
    @State private var deductPortion = true
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                mealPicker

                if showCustomField {
                    TextField("Meal name (e.g. Medication)", text: $customLabel)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    Toggle("Deduct a portion", isOn: $deductPortion)
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
            .navigationTitle(pet.name ?? "Unknown")
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
            deductPortion = true
        } label: {
            VStack(spacing: 4) {
                Text(meal.emoji).font(.title2).accessibilityHidden(true)
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
        .accessibilityLabel(meal.label)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var customChip: some View {
        Button {
            showCustomField = true
            selectedMealType = .custom("")
        } label: {
            VStack(spacing: 4) {
                Text("✏️").font(.title2).accessibilityHidden(true)
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
        .accessibilityLabel("Custom meal")
        .accessibilityValue(showCustomField ? "Selected" : "")
    }

    private var confirmButton: some View {
        Button(action: logFeeding) {
            Label("Log Meal", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canConfirm ? Color.green : Color.gray.opacity(0.3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!canConfirm || isSubmitting)
    }

    private var canConfirm: Bool {
        if showCustomField { return !customLabel.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private var resolvedMealLabel: String {
        showCustomField ? customLabel.trimmingCharacters(in: .whitespaces) : selectedMealType.label
    }

    private func logFeeding() {
        guard !isSubmitting else { return }
        isSubmitting = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let event = FeedingEvent(
            timestamp: .now,
            mealType: resolvedMealLabel,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            loggedBy: LoggedBy.current,
            pet: pet
        )
        modelContext.insert(event)

        NotificationManager.shared.scheduleOverdueNotification(for: pet, lastFedDate: event.timestamp)

        let shouldDecrementStock = showCustomField ? deductPortion : selectedMealType.decrementsStock
        if shouldDecrementStock {
            switch stockMode {
            case .individual:
                pet.decrementStock()
                if pet.foodStockCount <= lowStockThreshold {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    if lowStockPushEnabled {
                        NotificationManager.shared.scheduleLowStockNotification(for: pet)
                    }
                }
            case .shared:
                sharedFoodStock = max(0, sharedFoodStock - 1)
                if sharedFoodStock <= lowStockThreshold {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    if lowStockPushEnabled {
                        NotificationManager.shared.scheduleSharedLowStockNotification(stockCount: sharedFoodStock)
                    }
                }
            case .none:
                break
            }
        }

        WidgetDataWriter.write(from: modelContext)
        NotificationManager.shared.suppressNextUpcomingReminder(
            reminderMode: reminderMode,
            for: pet,
            allDogsReminderTimes: allDogsReminderTimes
        )
        onLogged?(event)
        dismiss()
    }
}
