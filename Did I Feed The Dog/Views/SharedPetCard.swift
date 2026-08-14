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

#if DEBUG
// `.sheet(item:)` requires `Identifiable`. SDK-header grep confirmed CKShare/CKRecord
// declare no such conformance (CKShare.h: `@interface CKShare : CKRecord <NSSecureCoding,
// NSCopying>`), and a build attempt without this extension confirmed it at compile time
// ("requires that 'CKShare' conform to 'Identifiable'"). A first attempt at
// `extension CKShare: Identifiable { var id: String { ... } }` alone failed with an
// ambiguous-witness error against the stdlib's `Identifiable where Self: AnyObject`
// default (`id: ObjectIdentifier`); pinning `ID` explicitly resolves the ambiguity.
extension CKShare: @retroactive Identifiable {
    public typealias ID = String
    public var id: String { recordID.recordName }
}
#endif
