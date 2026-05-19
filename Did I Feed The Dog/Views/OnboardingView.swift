import AppIntents
import StoreKit
import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("reminderMode", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))            private var reminderMode: ReminderMode = .none
    @AppStorage("allDogsReminderTimesRaw", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog")) private var allDogsReminderTimesRaw = ""

    private enum OnboardingStep: Int, CaseIterable {
        case welcome = 0, addDog, sync, reminder, proPitch, done
    }

    @Environment(EntitlementManager.self) private var entitlements
    @Query private var existingPets: [Pet]

    @State private var step: OnboardingStep = .welcome
    @State private var dogNames: [String] = [""]
    @State private var reminderEnabled = false
    @State private var showPaywallFromOnboarding = false
    @State private var reminderTime: Date = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        c.hour = 8; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c) ?? .now
    }()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                progressDots
                    .padding(.top, 24)
                    .padding(.bottom, 36)

                Group {
                    switch step {
                    case .welcome:   welcomeStep
                    case .addDog:    addDogStep
                    case .sync:      syncStep
                    case .reminder:  reminderStep
                    case .proPitch:  proPitchStep
                    case .done:      doneStep
                    }
                }
                .frame(maxWidth: .infinity)
                .id(step)
                .transition(reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                Spacer()

                bottomButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                    .padding(.top, 16)
            }
            .frame(maxWidth: 500)
        }
        .sheet(isPresented: $showPaywallFromOnboarding) {
            PaywallSheet(source: "onboarding")
        }
        .onChange(of: entitlements.isPro) { _, isPro in
            if isPro && step == .proPitch {
                stepAnimate { step = .done }
            }
        }
    }

    // MARK: - Progress

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { s in
                Capsule()
                    .fill(s == step ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: s == step ? 24 : 8, height: 8)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: step)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
                .padding(28)
                .background(Color.accentColor.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Did I Feed the Dog?")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("Track your dog's feedings so the whole\nfamily always knows who fed who.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
    }

    private var addDogStep: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Add Your Dog")
                    .font(.title.bold())

                Text("Just a name to get started — you can add\na photo and more details in Settings later.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                ForEach(dogNames.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        TextField(i == 0 ? "Dog's name" : "Another dog's name", text: $dogNames[i])
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        if dogNames.count > 1 {
                            Button {
                                dogNames.remove(at: i)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.red)
                            }
                            .accessibilityLabel("Remove \(dogNames[i].trimmingCharacters(in: .whitespaces).isEmpty ? "dog" : dogNames[i].trimmingCharacters(in: .whitespaces))")
                        }
                    }
                }

                if entitlements.isPro {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { dogNames.append("") }
                    } label: {
                        Label("Add Another Dog", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 32)
    }

    private var syncStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .padding(28)
                .background(Color.accentColor.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Stays in Sync")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text("Everyone signed into the same Apple ID sees feedings automatically — no setup needed.\n\nSharing across different Apple IDs isn't supported yet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
    }

    private var reminderStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Set a Reminder")
                    .font(.title.bold())

                Text("Get a daily nudge so \(petNamesNeverMiss).")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Toggle("Daily Feeding Reminder", isOn: $reminderEnabled)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onChange(of: reminderEnabled) { _, enabled in
                        if enabled {
                            Task { await NotificationManager.shared.requestAuthorization() }
                        }
                    }

                if reminderEnabled {
                    DatePicker("", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: reminderEnabled)
        }
        .padding(.horizontal, 32)
    }

    private var proPitchStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Unlock the Full Experience")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text("Free for 1 dog with the essentials. Pro adds unlimited dogs and power features.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach([
                    ("dog.fill",        "Unlimited dogs"),
                    ("apps.iphone",     "Home & Lock Screen widgets"),
                    ("mic.fill",        "Siri & Shortcuts"),
                    ("bell.badge.fill", "Push notifications"),
                ], id: \.1) { icon, text in
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        Text(text).font(.body)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(spacing: 6) {
                Button {
                    showPaywallFromOnboarding = true
                } label: {
                    Text("Upgrade to Pro — \(entitlements.product?.displayPrice ?? "$0.99")")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Text("One purchase · Family Sharing included")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 28)
    }

    private var doneStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("You're All Set!")
                    .font(.largeTitle.bold())

                Text("Head to the dashboard to log \(firstMealText).")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Bottom buttons

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            if step != .proPitch {
                Button(action: advance) {
                    Text(step == .done ? "Get Started" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canAdvance ? Color.accentColor : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!canAdvance)
            }

            if step == .reminder {
                Button("Skip for now") {
                    stepAnimate { step = .proPitch }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if step == .proPitch {
                Button("Maybe Later") {
                    stepAnimate { step = .done }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button("Restore Purchase") {
                    Task { await entitlements.restore() }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)

                if let error = entitlements.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }

            if step != .welcome && step != .done {
                Button("Back") {
                    stepAnimate {
                        if var prev = OnboardingStep(rawValue: step.rawValue - 1) {
                            if prev == .addDog && !existingPets.isEmpty { prev = .welcome }
                            step = prev
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var petName: String {
        dogNames
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "your dog"
    }

    private var petNamesFormatted: String {
        let names = dogNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return names.isEmpty ? "your dogs" : ListFormatter.localizedString(byJoining: names)
    }

    private var petNamesNeverMiss: String {
        let names = dogNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let verb = names.count == 1 ? "misses" : "miss"
        return "\(petNamesFormatted) never \(verb) a meal"
    }

    private var firstMealText: String {
        let names = dogNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if names.isEmpty {
            return "your dog's first meal"
        }
        let joined = ListFormatter.localizedString(byJoining: names)
        return "\(joined)'s first \(names.count > 1 ? "meals" : "meal")"
    }

    private var canAdvance: Bool {
        if step == .addDog {
            return dogNames.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return true
    }

    private func stepAnimate(_ block: @escaping () -> Void) {
        if reduceMotion { block() } else { withAnimation(.easeInOut(duration: 0.25), block) }
    }

    private func advance() {
        switch step {
        case .proPitch:
            stepAnimate { step = .done }
        case .done:
            saveDog()
            saveReminder()
            WidgetDataWriter.write(from: modelContext)
            // Refresh Siri's pet vocabulary so the dogs created here are
            // immediately addressable by name.
            DogFoodShortcuts.updateAppShortcutParameters()
            // Always request notification authorization once at the end of
            // onboarding — even if the user skipped the reminder step — so
            // overdue / low-stock / birthday pushes can fire later.
            Task { await NotificationManager.shared.requestAuthorization() }
            dismiss()
        default:
            stepAnimate {
                if var next = OnboardingStep(rawValue: step.rawValue + 1) {
                    if next == .addDog && !existingPets.isEmpty { next = .sync }
                    if next == .proPitch && entitlements.isPro { next = .done }
                    step = next
                }
            }
        }
    }

    private func saveDog() {
        var seen = Set<String>()
        let limit = entitlements.isPro ? Int.max : 1
        var insertCount = 0
        for raw in dogNames {
            guard insertCount < limit else { break }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            modelContext.insert(Pet(name: trimmed))
            insertCount += 1
        }
    }

    private func saveReminder() {
        guard reminderEnabled else { return }
        let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let names = dogNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        reminderMode = .allDogs
        allDogsReminderTimesRaw = "\(minutes)"
        NotificationManager.shared.scheduleAllDogsReminders(times: [minutes], petNames: names.isEmpty ? [petName] : names)
    }
}
