import SwiftUI
import SwiftData
import WidgetKit

struct PetCard: View {
    @AppStorage("lowStockUIWarning") private var lowStockUIWarning = true
    @AppStorage("lowStockThreshold") private var lowStockThreshold = 5
    @AppStorage("stockMode")         private var stockMode: StockMode = .individual
    @AppStorage("sharedFoodStock")   private var sharedFoodStock = 0
    @AppStorage("reminderMode")      private var reminderMode: ReminderMode = .none

    @Environment(\.modelContext) private var modelContext

    let pet: Pet
    @State private var showFeedSheet = false
    @State private var showEditSheet = false
    @State private var showSharedStockSheet = false
    @State private var lastLoggedEvent: FeedingEvent? = nil
    @State private var showUndoToast = false

    private var recentEvents: [FeedingEvent] {
        (pet.feedingEvents ?? [])
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(3)
            .map { $0 }
    }

    private var lastFedBadgeColor: Color {
        pet.isFeedingOverdue ? Color(.systemRed).opacity(0.15) : Color(.systemGreen).opacity(0.15)
    }

    private var lastFedTextColor: Color {
        pet.isFeedingOverdue ? .red : .green
    }

    private var lastFedLabel: String {
        guard let last = pet.lastFeedingEvent else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: last.timestamp, relativeTo: .now)
    }

    private var currentStockCount: Int {
        stockMode == .shared ? sharedFoodStock : pet.foodStockCount
    }

    private var isLowStock: Bool {
        guard lowStockUIWarning, stockMode != .none else { return false }
        return currentStockCount <= lowStockThreshold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: pet) { headerRow }
                .buttonStyle(.plain)

            if isLowStock {
                Button {
                    if stockMode == .shared { showSharedStockSheet = true } else { showEditSheet = true }
                } label: { lowStockBanner }
                .buttonStyle(.plain)
            }

            statsRow

            if !recentEvents.isEmpty {
                NavigationLink(value: pet) { miniHistory }
                    .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            feedButton
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
        .overlay(alignment: .bottom) {
            if showUndoToast {
                UndoToast(message: "Meal logged") {
                    // Undo action
                    if let event = lastLoggedEvent {
                        if event.resolvedMealType.decrementsStock {
                            switch stockMode {
                            case .individual: pet.foodStockCount += 1
                            case .shared:
                                let current = UserDefaults.standard.integer(forKey: "sharedFoodStock")
                                UserDefaults.standard.set(current + 1, forKey: "sharedFoodStock")
                            case .none: break
                            }
                        }
                        modelContext.delete(event)
                        WidgetDataWriter.write(from: modelContext)
                    }
                    showUndoToast = false
                    lastLoggedEvent = nil
                } onDismiss: {
                    showUndoToast = false
                    lastLoggedEvent = nil
                }
                .padding(.bottom, 80)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(), value: showUndoToast)
            }
        }
        .sheet(isPresented: $showFeedSheet) {
            LogFeedingSheet(pet: pet, onLogged: { event in
                lastLoggedEvent = event
                showUndoToast = true
            })
        }
        .sheet(isPresented: $showEditSheet) {
            AddEditPetSheet(pet: pet)
        }
        .sheet(isPresented: $showSharedStockSheet) {
            SharedStockSheet(sharedFoodStock: $sharedFoodStock)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            petAvatar
            VStack(alignment: .leading, spacing: 2) {
                Text(pet.name ?? "Unknown")
                    .font(.title3).fontWeight(.bold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(pet.ageString)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            lastFedBadge
        }
        .padding(16)
    }

    private var petAvatar: some View {
        Group {
            if let data = pet.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFill()
            } else {
                Image(DefaultAvatars.defaultFor(id: pet.id))
                    .resizable().scaledToFill()
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }

    private var lastFedBadge: some View {
        VStack(spacing: 2) {
            Text("Last Fed")
                .font(.caption2).fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundStyle(lastFedTextColor)
            Text(lastFedLabel)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(lastFedBadgeColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var lowStockBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Low Food Stock")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.orange)
                Text("Only \(currentStockCount) portion\(currentStockCount == 1 ? "" : "s") remaining — tap to restock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var nextMealInfo: (value: String, unit: String)? {
        guard reminderMode == .perDog else { return nil }
        return nextMealLabel(from: pet.feedingScheduleTimes)
    }

    private var statsRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if stockMode != .none {
                    Button {
                        if stockMode == .shared { showSharedStockSheet = true } else { showEditSheet = true }
                    } label: {
                        statCell(
                            title: stockMode == .shared ? "House Stock" : "Food Stock",
                            value: "\(currentStockCount)",
                            unit: "portions",
                            accent: isLowStock ? .red : .primary
                        )
                    }
                    .buttonStyle(.plain)
                }
                statCell(
                    title: "Today's Meals",
                    value: "\(pet.todaysFeedingCount)",
                    unit: "meals",
                    accent: .primary
                )
            }
            if let info = nextMealInfo {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Next meal · \(info.value) · \(info.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func statCell(title: String, value: String, unit: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2).fontWeight(.semibold)
                .textCase(.uppercase).foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value).font(.title2).fontWeight(.bold).foregroundStyle(accent)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var miniHistory: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.caption2).fontWeight(.semibold)
                .textCase(.uppercase).foregroundStyle(.secondary)
            ForEach(recentEvents) { event in
                HStack {
                    Text(MealType.emoji(for: event.mealType ?? "") + " " + (event.mealType ?? "Feeding"))
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(abbreviatedRelative(event.timestamp))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var feedButton: some View {
        Button {
            showFeedSheet = true
        } label: {
            Label("Log Meal", systemImage: "fork.knife")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func abbreviatedRelative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: .now)
    }


}

private struct SharedStockSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var sharedFoodStock: Int

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Text("\(sharedFoodStock)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("portions remaining")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 24) {
                    Button {
                        if sharedFoodStock > 0 { sharedFoodStock -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        if sharedFoodStock < 9999 { sharedFoodStock += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                    }
                }

                Stepper("Adjust by 10", value: $sharedFoodStock, in: 0...9999, step: 10)
                    .labelsHidden()
                    .padding(.horizontal, 40)

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Shared Food Stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
