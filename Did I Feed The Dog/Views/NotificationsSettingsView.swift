import SwiftUI
import SwiftData
import UserNotifications

struct NotificationsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pet.name) private var pets: [Pet]

    @AppStorage("lowStockUIWarning", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))     private var lowStockUIWarning = true
    @AppStorage("lowStockPushEnabled", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))   private var lowStockPushEnabled = true
    @AppStorage("birthdayPushEnabled", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))   private var birthdayPushEnabled = true
    @AppStorage("badgeEnabled", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))          private var badgeEnabled = true
    @AppStorage("overduePushEnabled", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))    private var overduePushEnabled = true
    @AppStorage("lowStockThreshold", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))     private var lowStockThreshold = 5
    @AppStorage("overdueThresholdHours", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog")) private var overdueThresholdHours = 12
    @AppStorage("reminderMode", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))          private var reminderMode: ReminderMode = .none

    @Environment(EntitlementManager.self) private var entitlements

    @State private var notificationsAuthorized = true
    @State private var showPaywall = false

    private var proBadge: some View {
        Text("PRO")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    var body: some View {
        Form {
            if !notificationsAuthorized {
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.slash.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifications are disabled on your iPhone")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Tap to open Settings and turn them on. Until then, you won't receive alerts.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                    .accessibilityHint("Opens iPhone Settings to turn on notifications")
                }
            }

            Section("Push Notifications") {
                if !entitlements.isPro {
                    Button { showPaywall = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Push notifications require Pro")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text("Get overdue, low stock, and birthday alerts delivered to your phone.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            proBadge
                        }
                    }
                } else {
                    Toggle(isOn: $lowStockPushEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Low Stock Notification")
                            Text("Sends an alert to your phone when food is low.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!notificationsAuthorized)
                    Toggle(isOn: $birthdayPushEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Birthday Notification")
                            Text("Sends a celebration alert on your dog's special day.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!notificationsAuthorized)
                    Toggle(isOn: $overduePushEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Overdue Notification")
                            Text("Alerts you if a dog misses their meal.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!notificationsAuthorized)
                }
            }

            Section("In-App") {
                Toggle(isOn: $lowStockUIWarning) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In-App Low Stock Banner")
                        Text("Shows an orange warning on the dog's card.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if entitlements.isPro {
                    Toggle(isOn: $badgeEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("App Icon Badge")
                            Text("Shows a red number on the app icon when a dog needs feeding.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!notificationsAuthorized)
                    .onChange(of: badgeEnabled) { _, enabled in
                        if enabled {
                            NotificationManager.shared.updateBadgeCount(pets: pets)
                        } else {
                            NotificationManager.shared.clearBadge()
                        }
                    }
                } else {
                    Button { showPaywall = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("App Icon Badge")
                                Text("Shows a red number on the app icon when a dog needs feeding.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            proBadge
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section("Thresholds") {
                Stepper(value: $lowStockThreshold, in: 1...50) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Low Stock Threshold")
                            Text("Warn when stock is this low.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(lowStockThreshold) portions")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                if reminderMode == .none {
                    Stepper(value: $overdueThresholdHours, in: 1...48) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Overdue After")
                                Text("Card turns red when past due.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(overdueThresholdHours) hr\(overdueThresholdHours == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .onChange(of: overdueThresholdHours) { _, _ in
                        WidgetDataWriter.write(from: modelContext)
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshNotificationAuth() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refreshNotificationAuth() }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(source: "notifications")
        }
    }

    private func refreshNotificationAuth() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAuthorized = settings.authorizationStatus == .authorized
    }
}
