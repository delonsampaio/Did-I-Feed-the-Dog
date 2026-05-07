import SwiftUI
import SwiftData
import StoreKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pet.name) private var pets: [Pet]

    @AppStorage("waterBowlReminderEnabled", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog")) private var waterBowlReminderEnabled = false
    @AppStorage("waterBowlReminderWeekday", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog")) private var waterBowlReminderWeekday = 1
    @AppStorage("waterBowlReminderTime", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))   private var waterBowlReminderTime = 600
    @AppStorage("stockMode", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))              private var stockMode: StockMode = .individual
    @AppStorage("sharedFoodStock", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))         private var sharedFoodStock = 0
    @AppStorage("stockOutPromptEnabled", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))   private var stockOutPromptEnabled = true
    @AppStorage("reminderMode", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))            private var reminderMode: ReminderMode = .none
    @AppStorage("allDogsReminderTimesRaw", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog")) private var allDogsReminderTimesRaw = ""
    @AppStorage(LoggedBy.storageKey, store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))       private var loggedByName = ""
    @AppStorage("appearanceMode", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))          private var appearanceMode: AppearanceMode = .system

    @State private var editingPet: Pet?
    @State private var showAddPet = false
    @State private var notificationsAuthorized = true

    var body: some View {
        Form {
            appearanceSection
            petsSection
            displayNameSection
            foodStockSection
            feedingRemindersSection
            notificationsSection
            hygieneSection
            safetySection
            supportSection
            aboutSection
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(item: $editingPet) { pet in
            AddEditPetSheet(pet: pet)
        }
        .sheet(isPresented: $showAddPet) {
            AddEditPetSheet()
        }
        .task { await refreshNotificationAuth() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refreshNotificationAuth() }
        }
    }

    private func refreshNotificationAuth() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAuthorized = settings.authorizationStatus == .authorized
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var petsSection: some View {
        Section("Dogs") {
            ForEach(pets) { pet in
                Button {
                    editingPet = pet
                } label: {
                    HStack {
                        Text(pet.name ?? "Unknown").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityHint("Double tap to edit \(pet.name ?? "dog")")
            }
            .onDelete(perform: deletePets)

            Button {
                showAddPet = true
            } label: {
                Label("Add Dog", systemImage: "plus.circle.fill")
            }
        }
    }

    private var displayNameSection: some View {
        Section {
            TextField("e.g. Mom, Dad, Alex", text: $loggedByName)
                .textInputAutocapitalization(.words)
        } header: {
            Text("Your Name")
        } footer: {
            Text("Shown next to feedings you log so family members know who fed the dog.")
        }
    }

    private var foodStockSection: some View {
        Section {
            Picker("Tracking Mode", selection: $stockMode) {
                ForEach(StockMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            if stockMode == .individual {
                ForEach(pets) { pet in
                    Stepper(value: Binding(
                        get: { pet.foodStockCount },
                        set: { pet.foodStockCount = max(0, $0) }
                    ), in: 0...999) {
                        HStack {
                            Text(pet.name ?? "Unknown")
                            Spacer()
                            Text("\(pet.foodStockCount) portions")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } else if stockMode == .shared {
                Stepper(value: $sharedFoodStock, in: 0...9999) {
                    HStack {
                        Text("Shared Pool")
                        Spacer()
                        Text("\(sharedFoodStock) portions")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            if stockMode != .none {
                Toggle(isOn: $stockOutPromptEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prompt to Restock When Empty")
                        Text("Alert appears after a feeding that empties your stock.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Food Stock")
        } footer: {
            if stockMode != .none {
                Text("Snack and Treat meals do not reduce the portion count.")
            }
        }
    }

    private var allDogsReminderTimes: [Int] {
        get { allDogsReminderTimesRaw.split(separator: ",").compactMap { Int($0) } }
        nonmutating set { allDogsReminderTimesRaw = newValue.map(String.init).joined(separator: ",") }
    }

    private var hasReminderOverlap: Bool {
        let times = allDogsReminderTimes.sorted()
        guard times.count >= 2 else { return false }
        return zip(times, times.dropFirst()).contains { $1 - $0 < 30 }
    }

    private func minutesToDate(_ m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
    }

    private func dateToMinutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func scheduleLabel(for pet: Pet) -> String {
        let times = pet.feedingScheduleTimes
        guard !times.isEmpty else { return "No reminders" }
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return times.map { f.string(from: minutesToDate($0)) }.joined(separator: ", ")
    }

    private func updateReminders() {
        RemindersCoordinator.refresh(pets: pets)
        WidgetDataWriter.write(from: modelContext)
    }

    private var feedingRemindersSection: some View {
        Section("Feeding Reminders") {
            Picker("Schedule", selection: $reminderMode) {
                ForEach(ReminderMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .onChange(of: reminderMode) { _, _ in
                if reminderMode == .allDogs && allDogsReminderTimes.isEmpty {
                    allDogsReminderTimes = [7 * 60, 18 * 60]
                }
                updateReminders()
            }

            if reminderMode == .allDogs {
                ForEach(Array(allDogsReminderTimes.enumerated()), id: \.offset) { index, minutes in
                    HStack {
                        DatePicker(
                            "Time \(index + 1)",
                            selection: Binding(
                                get: { minutesToDate(minutes) },
                                set: {
                                    var t = allDogsReminderTimes
                                    t[index] = dateToMinutes($0)
                                    allDogsReminderTimes = t
                                    updateReminders()
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        Button(role: .destructive) {
                            var t = allDogsReminderTimes
                            t.remove(at: index)
                            allDogsReminderTimes = t
                            updateReminders()
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete reminder time \(index + 1)")
                    }
                }
                if allDogsReminderTimes.count < 3 {
                    Button {
                        var t = allDogsReminderTimes
                        t.append(12 * 60)
                        allDogsReminderTimes = t
                        updateReminders()
                    } label: {
                        Label("Add Reminder Time", systemImage: "plus.circle.fill")
                    }
                }
                if hasReminderOverlap {
                    Label("Two reminder times are within 30 minutes of each other.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else if reminderMode == .perDog {
                ForEach(pets) { pet in
                    Button { editingPet = pet } label: {
                        HStack {
                            Text(pet.name ?? "Unknown").foregroundStyle(.primary)
                            Spacer()
                            Text(scheduleLabel(for: pet))
                                .font(.caption).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityHint("Double tap to set reminder times for \(pet.name ?? "this dog")")
                }
                Text("Tap a dog to set their reminder times.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var notificationsSection: some View {
        Section {
            NavigationLink(destination: NotificationsSettingsView()) {
                Label("Notifications", systemImage: "bell.fill")
            }
        }
    }

    private var hygieneSection: some View {
        Section("Health & Hygiene") {
            Toggle(isOn: $waterBowlReminderEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Water Bowl Cleaning Reminder")
                    Text("Weekly nudge to wash the bowl and keep their water fresh and clean.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!notificationsAuthorized)
            .onChange(of: waterBowlReminderEnabled) { _, _ in
                updateWaterBowlReminder()
            }

            if waterBowlReminderEnabled {
                Picker("Day of Week", selection: $waterBowlReminderWeekday) {
                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                    Text("Tuesday").tag(3)
                    Text("Wednesday").tag(4)
                    Text("Thursday").tag(5)
                    Text("Friday").tag(6)
                    Text("Saturday").tag(7)
                }
                .onChange(of: waterBowlReminderWeekday) { _, _ in
                    updateWaterBowlReminder()
                }

                DatePicker(
                    "Time",
                    selection: Binding(
                        get: { minutesToDate(waterBowlReminderTime) },
                        set: {
                            waterBowlReminderTime = dateToMinutes($0)
                            updateWaterBowlReminder()
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }
        }
    }

    private var safetySection: some View {
        Section {
            NavigationLink(destination: SafetyGuideView()) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.red)
                            .frame(width: 36, height: 36)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Toxic Foods Guide")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text("Foods that are dangerous for your dog")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Safety Guide")
        }
    }

    private var supportSection: some View {
        Section("Support") {
            NavigationLink(destination: HelpView()) {
                Label("Help & FAQ", systemImage: "questionmark.circle")
            }
            Button {
                // iOS rate-limits this prompt to 3 times per 365 days; nothing
                // happens silently if we're past the cap, which is expected.
                requestReview()
            } label: {
                Label("Rate the App", systemImage: "star.fill")
                    .foregroundStyle(.orange)
            }

            // TODO: Replace `id0` with the real App Store ID once the listing
            // goes live — current URL is a placeholder that 404s for users.
            ShareLink(
                item: URL(string: "https://apps.apple.com/app/id0")!,
                message: Text("Track your dog's feedings and keep them safe with Did I Feed the Dog?")
            ) {
                Label("Invite Family Member", systemImage: "person.badge.plus")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func updateWaterBowlReminder() {
        if waterBowlReminderEnabled {
            NotificationManager.shared.scheduleWaterBowlReminder(weekday: waterBowlReminderWeekday, timeMinutes: waterBowlReminderTime)
        } else {
            NotificationManager.shared.removeWaterBowlReminder()
        }
    }

    private func deletePets(at offsets: IndexSet) {
        for index in offsets {
            let pet = pets[index]
            NotificationManager.shared.removeBirthdayNotification(for: pet)
            NotificationManager.shared.removeOverdueNotification(for: pet)
            NotificationManager.shared.removePerDogReminders(for: pet)
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [NotificationManager.shared.lowStockIdentifier(for: pet)]
            )
            modelContext.delete(pet)
        }
        // Re-fetch survivors instead of filtering the (now-stale) @Query so the
        // reminder body lists the actual remaining roster, then delegate to
        // RemindersCoordinator to centralize the scheduling rules.
        let survivors = (try? modelContext.fetch(FetchDescriptor<Pet>())) ?? []
        RemindersCoordinator.refresh(pets: survivors)
        QuickActionManager.shared.update(with: survivors)
        WidgetDataWriter.write(from: modelContext)
    }
}
