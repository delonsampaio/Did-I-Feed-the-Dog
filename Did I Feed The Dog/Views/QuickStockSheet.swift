import SwiftUI

struct QuickStockSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var stockCount: Int
    let title: String
    /// Pet whose stock this sheet edits, or nil for the shared pool.
    /// Used to reset the stock-out prompt counter when stock leaves 0.
    let petId: UUID?

    init(stockCount: Binding<Int>, title: String, petId: UUID? = nil) {
        self._stockCount = stockCount
        self.title = title
        self.petId = petId
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Text("\(stockCount)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("portions remaining")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 24) {
                    Button {
                        if stockCount > 0 { stockCount -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Decrease stock by 1")
                    Button {
                        if stockCount < 9999 { stockCount += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                    }
                    .accessibilityLabel("Increase stock by 1")
                }

                Stepper("Adjust by 10", value: $stockCount, in: 0...9999, step: 10)
                    .padding(.horizontal, 40)

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: stockCount) { oldValue, newValue in
                if oldValue == 0 && newValue > 0 {
                    AppSettings.resetStockOutCount(petId: petId)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
