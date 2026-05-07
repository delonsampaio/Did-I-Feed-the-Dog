import SwiftUI
import SwiftData

struct FeedAllDogsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Retained only for the undo path — we need to know which counter to
    // restore. The service owns the live decrement.
    @AppStorage("stockMode", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))        private var stockMode: StockMode = .individual
    @AppStorage("sharedFoodStock", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))  private var sharedFoodStock = 0

    let pets: [Pet]
    var onLogged: ((FeedingLogService.BatchResult, @escaping () -> Void) -> Void)? = nil

    @State private var selectedMealType: MealType = .morning
    @State private var customLabel = ""
    @State private var showCustomField = false
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var showCustomTime = false
    @State private var logDate = Date()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                mealPicker

                if showCustomField {
                    TextField("Meal name (e.g. Medication)", text: $customLabel)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    Toggle("Set custom time", isOn: $showCustomTime.animation())
                        .tint(.green)
                    
                    if showCustomTime {
                        DatePicker("Time", selection: $logDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    }
                }
                .padding(.horizontal)

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
        Button(action: logForAll) {
            Label("Log Meal for All Dogs", systemImage: "checkmark.circle.fill")
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

    private func logForAll() {
        guard !isSubmitting else { return }
        isSubmitting = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let shouldDecrementStock = showCustomField || selectedMealType.decrementsStock

        // Capture stock snapshot for undo BEFORE the service decrements.
        let capturedStockMode = stockMode
        let stocksBefore: [(Pet, Int)] = shouldDecrementStock && stockMode == .individual
            ? pets.map { ($0, $0.foodStockCount) }
            : []
        let sharedStockBefore = sharedFoodStock

        let result = FeedingLogService.logFeedingForAll(
            pets: pets,
            mealLabel: resolvedMealLabel,
            deductsStock: shouldDecrementStock,
            timestamp: showCustomTime ? logDate : .now,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            logger: LoggedBy.current,
            in: modelContext
        )

        if result.didTriggerLowStock {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }

        let context = modelContext
        let createdEvents = result.events
        let undo: () -> Void = {
            for event in createdEvents { context.delete(event) }
            if shouldDecrementStock {
                switch capturedStockMode {
                case .individual:
                    for (pet, original) in stocksBefore { pet.foodStockCount = original }
                case .shared:
                    AppSettings.sharedFoodStock = sharedStockBefore
                case .none:
                    break
                }
            }
            WidgetDataWriter.write(from: context)
        }

        onLogged?(result, undo)
        dismiss()
    }
}
