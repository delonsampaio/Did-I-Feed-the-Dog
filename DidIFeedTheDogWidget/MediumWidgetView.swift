// DidIFeedTheDogWidget/MediumWidgetView.swift
import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: WidgetEntry

    private let deepLinkBase = "didfeedthedog://log?petId="

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if entry.pets.isEmpty {
                emptyRow
            } else {
                ForEach(Array(entry.pets.prefix(3).enumerated()), id: \.offset) { index, pet in
                    if index > 0 { divider }
                    petRow(pet)
                }
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
    }

    private var header: some View {
        HStack {
            Text("MY DOGS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .kerning(0.5)
            Spacer()
        }
        .padding(.bottom, 10)
    }

    private func petRow(_ pet: PetSnapshot) -> some View {
        Link(destination: deepLinkURL(for: pet.id)) {
            HStack(spacing: 10) {
                avatarView(photoData: pet.photoData)
                Text(pet.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                lastFedBadge(pet: pet)
            }
            .padding(.vertical, 4)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 40)
    }

    private var emptyRow: some View {
        HStack {
            Text("🐾  Add a dog to get started")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Text("Fed The Dog?")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.2))
            Spacer()
        }
    }

    private func avatarView(photoData: Data?) -> some View {
        Group {
            if let data = photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.gradient)
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
    }

    private func lastFedBadge(pet: PetSnapshot) -> some View {
        let (icon, _, color) = badgeDetails(for: pet)
        return HStack(spacing: 4) {
            Image(systemName: icon)
            Text(relativeTime(pet.lastFedDate))
        }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 7))
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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    private func deepLinkURL(for petId: UUID) -> URL {
        URL(string: deepLinkBase + petId.uuidString)!
    }
}
