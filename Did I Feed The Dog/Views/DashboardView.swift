import AppIntents
import SwiftUI
import SwiftData

struct DashboardView: View {
    @Binding var deepLinkPetId: UUID?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pet.name) private var pets: [Pet]

    @AppStorage("reminderMode", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))            private var reminderMode: ReminderMode = .none
    @AppStorage("allDogsReminderTimesRaw", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog")) private var allDogsReminderTimesRaw = ""
    @AppStorage("appearanceMode", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))          private var appearanceMode: AppearanceMode = .system

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var columns: [GridItem] {
        horizontalSizeClass == .regular
            ? [GridItem(.adaptive(minimum: 320), spacing: 16)]
            : [GridItem(.flexible())]
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 32 : 16
    }

    @State private var syncMonitor = CloudKitSyncMonitor()
    @State private var showAddPet = false
    @State private var showSettings = false
    @State private var showFeedAll = false
    @State private var deepLinkFeedingPet: Pet? = nil
    @State private var showUndoToast = false
    @State private var undoAction: (() -> Void)? = nil
    @State private var toastMessage = "Meal logged"
    @State private var toastId = UUID()

    private var allDogsReminderTimes: [Int] {
        allDogsReminderTimesRaw.split(separator: ",").compactMap { Int($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if reminderMode == .allDogs, let info = nextMealLabel(from: allDogsReminderTimes) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text("Next meal for all dogs · \(info.value) \(info.unit)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    }
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(pets) { pet in
                            PetCard(pet: pet, onFed: { _, undo in
                                triggerToast(message: "Meal logged", undo: undo)
                            })
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 12)
            }
            .refreshable {
                WidgetDataWriter.write(from: modelContext)
                try? await Task.sleep(for: .milliseconds(AppConstants.pullToRefreshSettleMilliseconds))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("My Dogs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddPet = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .accessibilityLabel("Add dog")
                }
                if pets.filter({ !$0.isFasting }).count >= 2 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showFeedAll = true } label: {
                            Image(systemName: "fork.knife.circle.fill").font(.title3)
                        }
                        .accessibilityLabel("Feed all dogs")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 10) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill").font(.title3)
                        }
                        .accessibilityLabel("Settings")
                        if syncMonitor.isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                                .accessibilityLabel("Syncing with iCloud")
                        } else if syncMonitor.lastError != nil {
                            Image(systemName: "exclamationmark.icloud")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                                .accessibilityLabel("iCloud sync issue — your data may not be up to date")
                        }
                    }
                }
            }
            .navigationDestination(for: Pet.self) { pet in PetDetailView(pet: pet) }
            .sheet(isPresented: $showAddPet) { AddEditPetSheet() }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
                    .presentationSizing(.page)
            }
            .sheet(isPresented: $showFeedAll) {
                    FeedAllDogsSheet(pets: pets.filter { !$0.isFasting }, onLogged: { _, undo in
                    triggerToast(message: "All dogs fed", undo: undo)
                })
            }
            .sheet(item: $deepLinkFeedingPet) { pet in LogFeedingSheet(pet: pet) }
            .overlay {
                if pets.isEmpty {
                    ContentUnavailableView(
                        "No Dogs Yet",
                        systemImage: "pawprint.fill",
                        description: Text("Use the Add button in the toolbar to add your first dog.")
                    )
                    .frame(maxWidth: 480)
                }
            }
            .overlay(alignment: .bottom) {
                if showUndoToast {
                    UndoToast(message: toastMessage) {
                        undoAction?()
                        showUndoToast = false
                        undoAction = nil
                    } onDismiss: {
                        showUndoToast = false
                        undoAction = nil
                    }
                    .id(toastId)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.3), value: showUndoToast)
            .onChange(of: toastId) { _, _ in
                UIAccessibility.post(notification: .announcement, argument: "\(toastMessage). Undo available.")
            }
        }
        .onChange(of: deepLinkPetId) { _, newId in
            guard let id = newId else { return }
            if let pet = pets.first(where: { $0.id == id }), !pet.isFasting {
                deepLinkFeedingPet = pet
            }
            deepLinkPetId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickActionTriggered)) { notification in
            guard let petIdString = notification.userInfo?["petId"] as? String,
                  let petId = UUID(uuidString: petIdString) else { return }
            if let pet = pets.first(where: { $0.id == petId }), !pet.isFasting {
                deepLinkFeedingPet = pet
            }
        }
        .onAppear {
            NotificationManager.shared.rescheduleIfNeeded(
                reminderMode: reminderMode,
                allDogsReminderTimes: allDogsReminderTimes,
                pets: pets
            )
            DogFoodShortcuts.updateAppShortcutParameters()
            WidgetDataWriter.write(from: modelContext)
            NotificationManager.shared.updateBadgeCount(pets: pets)
            QuickActionManager.shared.update(with: pets)
            
            if let pendingIdString = QuickActionManager.shared.pendingPetId,
               let pendingId = UUID(uuidString: pendingIdString) {
                if let pet = pets.first(where: { $0.id == pendingId }), !pet.isFasting {
                    deepLinkFeedingPet = pet
                }
                QuickActionManager.shared.pendingPetId = nil
            }
        }
        .onChange(of: pets) { _, newPets in
            WidgetDataWriter.write(from: modelContext)
            NotificationManager.shared.updateBadgeCount(pets: newPets)
            QuickActionManager.shared.update(with: newPets)
            // Re-register pet vocabulary so Siri/Shortcuts pick up newly added,
            // renamed, deleted, or iCloud-synced dogs without an app relaunch.
            DogFoodShortcuts.updateAppShortcutParameters()
            // Refresh All-Dogs reminder body so it names the current roster.
            RemindersCoordinator.refresh(pets: newPets)
        }
        // Widget refresh + badge update on feeding changes is now driven from
        // FeedingLogService directly — no separate @Query needed (loading
        // every event into memory just to fire a side effect was wasteful).
    }

    private func triggerToast(message: String, undo: @escaping () -> Void) {
        toastMessage = message
        undoAction = undo
        toastId = UUID()
        showUndoToast = true
    }
}
