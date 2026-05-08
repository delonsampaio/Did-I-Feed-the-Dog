// DidIFeedTheDogWidget/LargeWidgetView.swift
import SwiftUI
import UIKit
import WidgetKit

// BISECT STEP 4: Large widget redacts on home screen even after every
// per-row layout constraint was removed (commit a068c70). Medium widget
// renders fine with all the same constraints + width measurements, so
// the difference must be one of:
//   1. prefix(6) vs prefix(3) — too many rows
//   2. .padding(.vertical, 6) vs Medium's 4 — too much vertical space
//   3. URL force-unwrap vs Medium's WidgetDeepLink helper
//
// This file is now a verbatim copy of MediumWidgetView with three diffs:
//   - struct name + the literal "3" replaced with "6"
//   - .padding(.vertical) value matched to Medium's 4 (was 6)
//   - URL construction matched to Medium's WidgetDeepLink helper
//
// If this build renders on home screen → all of #2 and #3 (and any
// subtle difference) are eliminated, but it just confirms prefix(6)
// works. If still redacted → prefix(6) itself is the cause and we'll
// need to render fewer rows or use Grid layout.

struct LargeWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if entry.pets.isEmpty {
                emptyRow
            } else {
                ForEach(Array(entry.pets.prefix(6).enumerated()), id: \.offset) { index, pet in
                    if index > 0 { divider }
                    petRow(pet, badgeTextWidth: maxBadgeTextWidth, statusTextWidth: maxStatusTextWidth)
                }
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidgetColors.background)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var header: some View {
        HStack {
            Text("MY DOGS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
            Spacer()
        }
        .padding(.bottom, 10)
    }

    private func petRow(_ pet: PetSnapshot, badgeTextWidth: CGFloat, statusTextWidth: CGFloat) -> some View {
        Link(destination: WidgetDeepLink.url(for: pet.id)) {
            HStack(spacing: 10) {
                avatarView(pet: pet)
                Text(pet.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    Text(statusText(for: pet))
                        .font((pet.isFasting || pet.isFeedingOverdue) ? .caption.bold() : .caption)
                        .foregroundStyle(statusColor(for: pet))
                        .lineLimit(1)
                        .frame(width: statusTextWidth, alignment: .leading)
                    lastFedBadge(pet: pet, textWidth: badgeTextWidth)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(WidgetColors.divider)
            .frame(height: 1)
            .padding(.leading, 40)
    }

    private var emptyRow: some View {
        HStack {
            Text("🐾  Add a dog to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Text("Fed The Dog?")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private func avatarView(pet: PetSnapshot) -> some View {
        Group {
            if let data = pet.photoData,
               let uiImage = WidgetImage.downsample(data: data, toPointSize: CGSize(width: 30, height: 30)) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else if let thumb = UIImage(named: DefaultAvatars.defaultFor(id: pet.id))?
                .preparingThumbnail(of: CGSize(width: 30 * 3, height: 30 * 3)) {
                Image(uiImage: thumb).resizable().scaledToFill()
            } else {
                Image(DefaultAvatars.defaultFor(id: pet.id))
                    .resizable().scaledToFill()
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
    }

    private func lastFedBadge(pet: PetSnapshot, textWidth: CGFloat) -> some View {
        let (icon, _, color) = badgeDetails(for: pet)
        return HStack(spacing: 4) {
            Image(systemName: icon)
            Text(relativeTime(pet.lastFedDate))
                .lineLimit(1)
                .frame(width: textWidth, alignment: .center)
        }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 7))
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
        return .secondary
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

    // Measures the widest time string across the currently-shown pets so
    // every badge can be sized to that width — keeps badges visually
    // aligned regardless of whether the times are "5m ago" or "12mo ago".
    private static let badgeFont = UIFont.systemFont(ofSize: 11, weight: .semibold)

    private var maxBadgeTextWidth: CGFloat {
        let widths = entry.pets.prefix(6).map {
            (relativeTime($0.lastFedDate) as NSString)
                .size(withAttributes: [.font: Self.badgeFont]).width
        }
        return ceil(widths.max() ?? 0)
    }

    // Same idea for status text. Bold weight is used for Overdue/Fasting
    // and regular for Fed, so each row is measured against its own actual
    // font weight before we take the max — otherwise a bold "Fasting"
    // would be undersized when measured with the regular font.
    private static let statusFontRegular = UIFont.systemFont(ofSize: 12, weight: .regular)
    private static let statusFontBold = UIFont.systemFont(ofSize: 12, weight: .bold)

    private var maxStatusTextWidth: CGFloat {
        let widths = entry.pets.prefix(6).map { pet -> CGFloat in
            let font = (pet.isFasting || pet.isFeedingOverdue) ? Self.statusFontBold : Self.statusFontRegular
            return (statusText(for: pet) as NSString)
                .size(withAttributes: [.font: font]).width
        }
        return ceil(widths.max() ?? 0)
    }
}
