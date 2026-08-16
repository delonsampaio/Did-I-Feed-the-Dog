import CloudKit
import CoreData
import SwiftData
import SwiftUI

/// Dashboard card for a dog shared with the user. Log Meal / Log Medication / Update Stock are
/// available to any participant; Share/Stop-sharing stay owner-gated (Phase 5).
struct SharedPetCard: View {
    @Environment(\.modelContext) private var modelContext
    let dog: any DogDisplayable

    @State private var shareToPresent: CKShare?
    @State private var isBusy = false
    @State private var showStopSharingConfirm = false
    @State private var showShareError = false
    @State private var shareErrorMessage = ""
    @State private var showLogFeeding = false
    @State private var showLogMedication = false
    @State private var showRestockSheet = false

    private var sharedPet: SharedPet? { dog as? SharedPet }

    private var isOwner: Bool {
        guard SharingFeatureFlag.isFoundationEnabled, let pet = sharedPet else { return false }
        let zoneName = CKRecordMapper.zoneID(forRoot: pet).zoneName
        return SharedSyncEngine.shared.isOwner(ofZoneNamed: zoneName)
    }

    private var medications: [SharedMedication] {
        Array((sharedPet?.medications as? Set<SharedMedication>) ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
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

            if SharingFeatureFlag.isFoundationEnabled, sharedPet != nil {
                HStack(spacing: 8) {
                    Button {
                        showLogFeeding = true
                    } label: {
                        Label("Log Meal", systemImage: "fork.knife")
                            .font(.subheadline).fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if !medications.isEmpty {
                        Button {
                            showLogMedication = true
                        } label: {
                            Label("Log Medication", systemImage: "pill")
                                .font(.subheadline).fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.purple)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            if sharedPet != nil {
                Button {
                    showRestockSheet = true
                } label: {
                    Label("Update Food Stock", systemImage: "shippingbox")
                }
            }
            if let pet = sharedPet, isOwner {
                Button {
                    Task { await manageSharing(for: pet) }
                } label: {
                    Label("Share this dog", systemImage: "person.2.badge.plus")
                }
                Button("Stop sharing", role: .destructive) {
                    showStopSharingConfirm = true
                }
            }
        }
        .confirmationDialog("Stop sharing this dog?", isPresented: $showStopSharingConfirm, titleVisibility: .visible) {
            Button("Stop Sharing", role: .destructive) {
                if let pet = sharedPet { Task { await stopSharing(pet) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll keep this dog and its history. Anyone you shared it with will lose access.")
        }
        .sheet(item: $shareToPresent) { share in
            CloudSharingView(share: share)
        }
        .sheet(isPresented: $showLogFeeding) {
            if let pet = sharedPet {
                LogSharedFeedingSheet(pet: pet)
            }
        }
        .sheet(isPresented: $showLogMedication) {
            if let pet = sharedPet {
                LogSharedMedicationSheet(pet: pet, medications: medications)
            }
        }
        .sheet(isPresented: $showRestockSheet) {
            if let pet = sharedPet {
                SharedRestockSheet(pet: pet)
            }
        }
        .alert("Couldn't share this dog", isPresented: $showShareError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareErrorMessage)
        }
    }

    private func manageSharing(for pet: SharedPet) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if let existing = try await ShareController.fetchShare(forRoot: pet) {
                shareToPresent = existing
            } else {
                shareToPresent = try await ShareController.makeShare(forRoot: pet)
            }
        } catch {
            shareErrorMessage = error.localizedDescription
            showShareError = true
        }
    }

    private func stopSharing(_ pet: SharedPet) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try SharePreparationController.migrateToOwned(sharedPet: pet, modelContext: modelContext)
            try await ShareController.stopSharing(forRoot: pet)
        } catch {
            shareErrorMessage = error.localizedDescription
            showShareError = true
        }
    }
}
