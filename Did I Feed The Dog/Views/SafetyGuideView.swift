import SwiftUI

struct SafetyGuideView: View {
    @State private var searchText = ""

    private var emergencyFoods: [SafetyEntry] {
        toxicFoods
            .filter { $0.level == .emergency }
            .filter { matches($0) }
    }

    private var warningFoods: [SafetyEntry] {
        toxicFoods
            .filter { $0.level == .warning }
            .filter { matches($0) }
    }

    private func matches(_ entry: SafetyEntry) -> Bool {
        guard !searchText.isEmpty else { return true }
        return entry.name.localizedCaseInsensitiveContains(searchText) ||
               entry.danger.localizedCaseInsensitiveContains(searchText)
    }

    var body: some View {
        List {
            if !emergencyFoods.isEmpty {
                Section {
                    ForEach(emergencyFoods) { entry in
                        safetyRow(entry)
                    }
                } header: {
                    Label("Emergency — Immediately Life-Threatening", systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                        .textCase(nil)
                }
            }

            if !warningFoods.isEmpty {
                Section {
                    ForEach(warningFoods) { entry in
                        safetyRow(entry)
                    }
                } header: {
                    Label("Warning — Dangerous With Exposure", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textCase(nil)
                }
            }

            if emergencyFoods.isEmpty && warningFoods.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Safety Guide")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search foods…")
    }

    private func safetyRow(_ entry: SafetyEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.level.emoji)
                    .font(.body)
                    .accessibilityHidden(true)
                Text(entry.name)
                    .font(.headline)
            }
            Text(entry.danger)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
