// DidIFeedTheDogWidget/LockScreenWidgetViews.swift
import SwiftUI
import WidgetKit

// MARK: - Circular (.accessoryCircular)

struct CircularWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Text("🐾").font(.system(size: 18))
                if entry.pets.isEmpty {
                    // "0/0" looks broken — use an em dash placeholder until
                    // the user actually has dogs.
                    Text("—")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .accessibilityLabel("No dogs added yet")
                } else {
                    Text("\(entry.fedCount)/\(entry.pets.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .accessibilityLabel("\(entry.fedCount) of \(entry.pets.count) dogs fed")
                }
            }
        }
    }
}

// MARK: - Rectangular (.accessoryRectangular)

struct RectangularWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        if let pet = entry.mostOverdue {
            Link(destination: WidgetDeepLink.url(for: pet.id)) {
                HStack(spacing: 8) {
                    Text("🐾").font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        if pet.isFasting {
                            Text("\(pet.name) is fasting")
                                .font(.system(size: 12, weight: .bold))
                        } else {
                            Text(pet.isFeedingOverdue ? "\(pet.name) needs feeding" : "\(pet.name) is fed")
                                .font(.system(size: 12, weight: .bold))
                        }
                        HStack(spacing: 6) {
                            Text(relativeTime(pet.lastFedDate))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if pet.hasMedicationDue {
                                Label("Meds due", systemImage: "pill.fill")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                }
            }
        } else {
            Text("🐾  Add a dog to get started")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "Never fed" }
        return "Last fed " + Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
    }
}

// MARK: - Inline (.accessoryInline)

struct InlineWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        if entry.pets.isEmpty {
            Text("🐾 No dogs added yet")
        } else {
            Text("🐾 \(entry.fedCount) of \(entry.pets.count) dogs fed")
        }
    }
}
