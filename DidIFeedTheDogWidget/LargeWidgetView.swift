// DidIFeedTheDogWidget/LargeWidgetView.swift
import SwiftUI
import UIKit
import WidgetKit

struct LargeWidgetView: View {
    static let maxRows = 6

    let entry: WidgetEntry

    var body: some View {
        if !entry.isPro {
            lockedView
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                if entry.pets.isEmpty {
                    emptyRow
                } else {
                    ForEach(Array(entry.pets.prefix(Self.maxRows).enumerated()), id: \.offset) { index, pet in
                        if index > 0 { divider }
                        petRow(pet, badgeTextWidth: maxBadgeTextWidth)
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
    }

    private var lockedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("Did I Feed the Dog? Pro")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("Upgrade in the app to unlock widgets")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidgetColors.background)
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

    private func petRow(_ pet: PetSnapshot, badgeTextWidth: CGFloat) -> some View {
        Link(destination: WidgetDeepLink.url(for: pet.id)) {
            HStack(spacing: 10) {
                PetAvatarView(pet: pet)
                Text(pet.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    Text(pet.statusText)
                        .font((pet.isFasting || pet.isFeedingOverdue) ? .caption.bold() : .caption)
                        .foregroundStyle(pet.statusColor)
                        .fixedSize(horizontal: true, vertical: false)
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
            Text(entry.isPro ? "Fed The Dog?" : "Add more dogs with Pro")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private func lastFedBadge(pet: PetSnapshot, textWidth: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: pet.badgeIcon)
            Text(pet.relativeLastFed())
                .lineLimit(1)
                .frame(width: textWidth, alignment: .center)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(pet.badgeColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(pet.badgeColor.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .fixedSize(horizontal: true, vertical: false)
    }

    // Measures the widest time string across the currently-shown pets so
    // every badge can be sized to that width — keeps badges visually
    // aligned regardless of whether the times are "5m ago" or "12mo ago".
    private static let badgeFont = UIFont.systemFont(ofSize: 11, weight: .semibold)

    private var maxBadgeTextWidth: CGFloat {
        let widths = entry.pets.prefix(Self.maxRows).map {
            ($0.relativeLastFed() as NSString)
                .size(withAttributes: [.font: Self.badgeFont]).width
        }
        return ceil(widths.max() ?? 0)
    }

    // maxStatusTextWidth removed — status text now uses fixedSize instead of a
    // measured frame, so "Overdue" can't be clipped at larger Dynamic Type sizes.
}
