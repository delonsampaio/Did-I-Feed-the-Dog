import SwiftUI
import SwiftData

struct PetCard: View {
    @AppStorage("lowStockUIWarning") private var lowStockUIWarning = true
    @AppStorage("lowStockThreshold") private var lowStockThreshold = 5
    @AppStorage("stockMode")         private var stockMode: StockMode = .individual
    @AppStorage("sharedFoodStock")   private var sharedFoodStock = 0

    let pet: Pet
    @State private var showFeedSheet = false
    @State private var showEditSheet = false

    private var recentEvents: [FeedingEvent] {
        pet.feedingEvents
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
        formatter.unitsStyle = .full
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
                Button { showEditSheet = true } label: { lowStockBanner }
                    .buttonStyle(.plain)
            }

            statsRow

            if !recentEvents.isEmpty {
                NavigationLink(value: pet) { miniHistory }
                    .buttonStyle(.plain)
            }

            feedButton
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
        .sheet(isPresented: $showFeedSheet) {
            LogFeedingSheet(pet: pet)
        }
        .sheet(isPresented: $showEditSheet) {
            AddEditPetSheet(pet: pet)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            petAvatar
            VStack(alignment: .leading, spacing: 2) {
                Text(pet.name)
                    .font(.title3).fontWeight(.bold)
                Text(pet.ageString)
                    .font(.caption).foregroundStyle(.secondary)
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
                Image(systemName: "pawprint.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.gradient)
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

    private var statsRow: some View {
        HStack(spacing: 12) {
            if stockMode != .none {
                Button { showEditSheet = true } label: {
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
                unit: "feedings",
                accent: .primary
            )
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
                    Text(emojiForMeal(event.mealType) + " " + event.mealType)
                        .font(.subheadline)
                    Spacer()
                    Text(RelativeDateTimeFormatter().localizedString(for: event.timestamp, relativeTo: .now))
                        .font(.caption).foregroundStyle(.secondary)
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
            Label("Log Feeding", systemImage: "fork.knife")
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

    private func emojiForMeal(_ mealType: String) -> String {
        switch mealType {
        case "Morning":   return "🌅"
        case "Evening":   return "🌙"
        case "Breakfast": return "🍳"
        case "Lunch":     return "🥗"
        case "Dinner":    return "🍽️"
        case "Snack":     return "🦴"
        default:          return "✏️"
        }
    }
}
