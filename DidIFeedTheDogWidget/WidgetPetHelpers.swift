// DidIFeedTheDogWidget/WidgetPetHelpers.swift
import SwiftUI
import UIKit

// MARK: - PetSnapshot display helpers

extension PetSnapshot {
    var statusText: String {
        if isFasting { return "Fasting" }
        return isFeedingOverdue ? "Overdue" : "Fed"
    }

    var statusColor: Color {
        if isFasting { return .orange }
        if isFeedingOverdue { return .red }
        return .secondary
    }

    var badgeIcon: String {
        if isFasting { return "exclamationmark.octagon.fill" }
        if isFeedingOverdue { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    var badgeColor: Color {
        if isFasting { return .orange }
        if isFeedingOverdue { return .red }
        return .green
    }

    func relativeLastFed(relativeTo now: Date = .now) -> String {
        guard let lastFedDate else { return "Never" }
        return WidgetFormatters.relative.localizedString(for: lastFedDate, relativeTo: now)
    }
}

// MARK: - Shared formatter

enum WidgetFormatters {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - Shared avatar view

struct PetAvatarView: View {
    let pet: PetSnapshot
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let data = pet.photoData,
               let uiImage = WidgetImage.downsample(data: data, toPointSize: CGSize(width: size, height: size)) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else if let thumb = UIImage(named: DefaultAvatars.defaultFor(id: pet.id))?
                .preparingThumbnail(of: CGSize(width: size * 3, height: size * 3)) {
                Image(uiImage: thumb).resizable().scaledToFill()
            } else {
                Image(DefaultAvatars.defaultFor(id: pet.id))
                    .resizable().scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
