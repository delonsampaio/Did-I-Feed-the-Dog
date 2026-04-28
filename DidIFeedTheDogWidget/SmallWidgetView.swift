// DidIFeedTheDogWidget/SmallWidgetView.swift
import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: WidgetEntry

    private let deepLinkBase = "didfeedthedog://log?petId="

    var body: some View {
        if let pet = entry.mostOverdue {
            Link(destination: URL(string: deepLinkBase + pet.id.uuidString)!) {
                filledView(pet: pet)
            }
        } else {
            emptyView
        }
    }

    private func filledView(pet: PetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                avatarView(photoData: pet.photoData)
                Spacer()
                lastFedBadge(pet: pet)
            }
            Spacer()
            Text(pet.name)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(pet.isFeedingOverdue ? "Needs feeding" : "Fed recently")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 2)
            Spacer()
            Text("Did I Feed The Dog?")
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

    private func avatarView(photoData: Data?) -> some View {
        Group {
            if let data = photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.gradient)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    private func lastFedBadge(pet: PetSnapshot) -> some View {
        VStack(spacing: 2) {
            Text("Fed")
                .font(.system(size: 9, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(pet.isFeedingOverdue ? .red : .green)
            Text(relativeTime(pet.lastFedDate))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            pet.isFeedingOverdue
                ? Color.red.opacity(0.2)
                : Color.green.opacity(0.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
