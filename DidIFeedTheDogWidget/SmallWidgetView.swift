// DidIFeedTheDogWidget/SmallWidgetView.swift
import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        if !entry.isPro {
            lockedView
        } else if let pet = entry.mostOverdue {
            Link(destination: WidgetDeepLink.url(for: pet.id)) {
                filledView(pet: pet)
            }
        } else {
            emptyView
        }
    }

    private var lockedView: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Pro Feature")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("Upgrade in app")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidgetColors.background)
    }

    private func filledView(pet: PetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                PetAvatarView(pet: pet, size: 36)
                Spacer()
                lastFedBadge(pet: pet)
            }
            Spacer()
            Text(pet.name)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(pet.statusText)
                .font((pet.isFasting || pet.isFeedingOverdue) ? .caption.bold() : .caption2)
                .foregroundStyle(pet.statusColor)
            Spacer()
            Text(entry.isPro ? "Fed The Dog?" : "Add more dogs with Pro")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidgetColors.background)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
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

    private func lastFedBadge(pet: PetSnapshot) -> some View {
        VStack(spacing: 2) {
            Image(systemName: pet.badgeIcon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(pet.badgeColor)
            Text(pet.relativeLastFed())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(pet.badgeColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(pet.badgeColor.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .fixedSize(horizontal: true, vertical: false)
    }
}
