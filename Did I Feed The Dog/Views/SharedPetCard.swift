import CloudKit
import SwiftUI

/// Read-only dashboard card for a dog shared with the user (Phase 1 foundation).
/// Logging into shared dogs arrives with the Phase 2 sync engine.
struct SharedPetCard: View {
    let dog: any DogDisplayable

    #if DEBUG
    @State private var shareToPresent: CKShare?
    #endif

    var body: some View {
        HStack(spacing: 12) {
            // Reuse the app's avatar rendering if a shared helper exists; else a placeholder.
            Image(systemName: "pawprint.circle.fill")
                .resizable().frame(width: 44, height: 44)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(dog.displayName).font(.headline)
                    Image(systemName: "person.2.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel("Shared dog")
                }
                if let last = dog.lastFeedingDate {
                    Text("Last fed \(last.formatted(.relative(presentation: .named)))")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("No meals yet").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        #if DEBUG
        .contextMenu {
            if SharingFeatureFlag.isFoundationEnabled, let pet = dog as? SharedPet {
                Button("Share this dog") {
                    Task { shareToPresent = try? await ShareController.makeShare(forRoot: pet) }
                }
                Button("Stop sharing", role: .destructive) {
                    Task { await ShareController.stopSharing(forRoot: pet) }
                }
            }
        }
        .sheet(item: $shareToPresent) { share in
            CloudSharingView(share: share)
        }
        #endif
    }
}
