import SwiftUI
import SwiftData
import WidgetKit

struct LogFeedingSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lowStockPushEnabled") private var lowStockPushEnabled = true
    @AppStorage("lowStockThreshold")  private var lowStockThreshold = 5
    @AppStorage("stockMode")          private var stockMode: StockMode = .individual
    @AppStorage("sharedFoodStock")    private var sharedFoodStock = 0

    let pet: Pet
    @State private var selectedMealType: MealType = .morning
    @State private var customLabel = ""
    @State private var showCustomField = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("What meal is this?")
                    .font(.headline)
                    .padding(.horizontal)

                mealPicker

                if showCustomField {
                    TextField("Meal name (e.g. Medication)", text: $customLabel)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                }

                Spacer()

                confirmButton
                    .padding(.horizontal)
                    .padding(.bottom)
            }
            .padding(.top, 24)
            .navigationTitle("Log Feeding — \(pet.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var mealPicker: some View {
        let columns = [GridItem(.adaptive(minimum: 90))]
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
        Button(action: logFeeding) {
            Label("Log Feeding", systemImage: "checkmark.circle.fill")
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

    private func logFeeding() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let event = FeedingEvent(mealType: resolvedMealLabel, pet: pet)
        modelContext.insert(event)

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

        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }
}
