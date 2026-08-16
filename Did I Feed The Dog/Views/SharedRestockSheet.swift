import CoreData
import SwiftUI

/// Sets a new stock baseline for a shared dog. Unlike QuickStockSheet (owned dogs, live
/// Binding<Int>), this commits explicitly on "Done" — writing foodStockCount and
/// foodStockBaselineDate together in one save, rather than pushing a CloudKit record on every
/// +/-1 tap.
struct SharedRestockSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pet: SharedPet
    @State private var newCount: Int
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    init(pet: SharedPet) {
        self.pet = pet
        _newCount = State(initialValue: pet.effectiveFoodStockCount)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Text("\(newCount)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("portions remaining")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 24) {
                    Button {
                        if newCount > 0 { newCount -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Decrease stock by 1")
                    Button {
                        if newCount < 9999 { newCount += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                    }
                    .accessibilityLabel("Increase stock by 1")
                }

                Stepper("Adjust by 10", value: $newCount, in: 0...9999, step: 10)
                    .padding(.horizontal, 40)

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("\(pet.name ?? "Dog")'s Stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commitAndDismiss() }
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
        .presentationDetents([.medium])
    }

    private func commitAndDismiss() {
        pet.foodStockCount = Int64(newCount)
        pet.foodStockBaselineDate = .now
        do {
            try pet.managedObjectContext?.save()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to save stock count: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
