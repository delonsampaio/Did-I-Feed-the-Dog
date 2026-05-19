import SwiftUI
import SwiftData

struct LogFeedingSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let pet: Pet
    var onLogged: ((FeedingLogService.LogResult) -> Void)? = nil
    @State private var selectedMealType: MealType = .morning
    @State private var customLabel = ""
    @State private var showCustomField = false
    @State private var notes = ""
    @State private var deductPortion = true
    @State private var isSubmitting = false
    @State private var showCustomTime = false
    @State private var logDate = Date()
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

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
            .navigationTitle(pet.name ?? "Unknown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
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

        let shouldDecrementStock = showCustomField ? deductPortion : selectedMealType.decrementsStock

        do {
            let result = try FeedingLogService.logFeeding(
                for: pet,
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

            onLogged?(result)
            dismiss()
        } catch {
            saveErrorMessage = "Failed to save meal: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
