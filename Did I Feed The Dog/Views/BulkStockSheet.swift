import SwiftUI

struct BulkStockSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pets: [Pet]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(pets, id: \.id) { pet in
                        BulkStockRow(pet: pet)
                    }
                } header: {
                    Text("Add portions for each dog")
                } footer: {
                    Text("Tap + or - to adjust. Changes save automatically.")
                }
            }
            .navigationTitle("Restock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct BulkStockRow: View {
    @Bindable var pet: Pet

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pet.name ?? "Unknown")
                    .font(.headline)
                Text("\(pet.foodStockCount) portion\(pet.foodStockCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(pet.foodStockCount == 0 ? .red : .secondary)
            }
            Spacer()
            Button {
                if pet.foodStockCount > 0 { pet.foodStockCount -= 1 }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease \(pet.name ?? "dog") stock by 1")

            Button {
                if pet.foodStockCount < AppConstants.perPetStockCap {
                    pet.foodStockCount += 1
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase \(pet.name ?? "dog") stock by 1")
        }
        .padding(.vertical, 4)
        .onChange(of: pet.foodStockCount) { oldValue, newValue in
            if oldValue == 0 && newValue > 0 {
                AppSettings.resetStockOutCount(petId: pet.id)
            }
        }
    }
}
