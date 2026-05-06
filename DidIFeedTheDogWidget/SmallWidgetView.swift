// DidIFeedTheDogWidget/SmallWidgetView.swift
import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        if let pet = entry.mostOverdue {
            Link(destination: WidgetDeepLink.url(for: pet.id)) {
                filledView(pet: pet)
            }
        } else {
            emptyView
        }
    }

    private func filledView(pet: PetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                avatarView(pet: pet)
                Spacer()
                lastFedBadge(pet: pet)
            }
            Spacer()
            Text(pet.name)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(statusText(for: pet))
                .font(pet.isFasting ? .caption.bold() : .caption2)
                .foregroundStyle(statusColor(for: pet))
            Spacer()
            Text("Fed The Dog?")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Text("🐾").font(.largeTitle)
            Text("Add a dog\nto get started")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func avatarView(pet: PetSnapshot) -> some View {
        Group {
            if let data = pet.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                Image(DefaultAvatars.defaultFor(id: pet.id))
                    .resizable().scaledToFill()
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    private func lastFedBadge(pet: PetSnapshot) -> some View {
        let (icon, _, color) = badgeDetails(for: pet)
        return VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
            Text(relativeTime(pet.lastFedDate))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func badgeDetails(for pet: PetSnapshot) -> (icon: String, text: String, color: Color) {
        if pet.isFasting {
            return ("exclamationmark.octagon.fill", "Fasting", .orange)
        }
        if pet.isFeedingOverdue {
            return ("exclamationmark.triangle.fill", "Overdue", .red)
        }
        return ("checkmark.circle.fill", "Fed", .green)
    }

    private func statusText(for pet: PetSnapshot) -> String {
        if pet.isFasting { return "Fasting" }
        return pet.isFeedingOverdue ? "Overdue" : "Fed"
    }

    private func statusColor(for pet: PetSnapshot) -> Color {
        if pet.isFasting { return .orange }
        if pet.isFeedingOverdue { return .red }
        return .white.opacity(0.55)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
    }
}
