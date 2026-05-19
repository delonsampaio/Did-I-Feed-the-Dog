import AppIntents
import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(EntitlementManager.self) private var entitlements
    @AppStorage("reminderMode", store: .sharedGroup) private var reminderMode: ReminderMode = .none
    @AppStorage("allDogsReminderTimesRaw", store: .sharedGroup) private var allDogsReminderTimesRaw = ""

    @Query private var existingPets: [Pet]

    private enum OnboardingStep: Int, CaseIterable {
        case welcome = 0, addDog, sync, reminder, done
    }

    private struct DogEntry: Identifiable, Equatable {
        let id = UUID()
        var name: String
    }

    @State private var step: OnboardingStep = .welcome
    @State private var dogNames: [DogEntry] = [DogEntry(name: "")]
    @State private var reminderEnabled = false
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
                    case .welcome:  welcomeStep
                    case .addDog:   addDogStep
                    case .sync:     syncStep
                    case .reminder: reminderStep
                    case .done:     doneStep
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

            ScrollView {
                VStack(spacing: 10) {
                    ForEach($dogNames) { $dog in
                        HStack(spacing: 10) {
                            TextField(dog.id == dogNames.first?.id ? "Dog's name" : "Another dog's name", text: $dog.name)
                                .font(.title3)
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            if dogNames.count > 1 {
                                Button {
                                    dogNames.removeAll(where: { $0.id == dog.id })
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.red)
                                }
                                .accessibilityLabel("Remove \(dog.name.trimmingCharacters(in: .whitespaces).isEmpty ? "dog" : dog.name.trimmingCharacters(in: .whitespaces))")
                            }
                        }
                    }

                    if entitlements.isPro {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { dogNames.append(DogEntry(name: "")) }
                        } label: {
                            Label("Add Another Dog", systemImage: "plus.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, 28)
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

                if !entitlements.isPro {
                    Text("Want multiple dogs, widgets, or Siri? Upgrade to Pro anytime in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Bottom buttons

    private var bottomButtons: some View {
        VStack(spacing: 12) {
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

            if step == .reminder {
                Button("Skip for now") {
                    stepAnimate { step = .done }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if step != .welcome && step != .done {
                Button("Back") {
                    stepAnimate {
                        // Mirror the forward skip: if dogs already exist we skipped addDog on the
                        // way in, so skip it on the way back too.
                        if step == .sync && !existingPets.isEmpty {
                            step = .welcome
                        } else if let prev = OnboardingStep(rawValue: step.rawValue - 1) {
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

    private var validDogNames: [String] {
        dogNames.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var petName: String {
        validDogNames.first ?? "your dog"
    }

    private var petNamesFormatted: String {
        return validDogNames.isEmpty ? "your dogs" : ListFormatter.localizedString(byJoining: validDogNames)
    }

    private var petNamesNeverMiss: String {
        let verb = validDogNames.count == 1 ? "misses" : "miss"
        return "\(petNamesFormatted) never \(verb) a meal"
    }

    private var firstMealText: String {
        if validDogNames.isEmpty {
            return "your dog's first meal"
        }
        let joined = ListFormatter.localizedString(byJoining: validDogNames)
        return "\(joined)'s first \(validDogNames.count > 1 ? "meals" : "meal")"
    }

    private var canAdvance: Bool {
        if step == .addDog {
            return dogNames.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return true
    }

    private func stepAnimate(_ block: @escaping () -> Void) {
        if reduceMotion { block() } else { withAnimation(.easeInOut(duration: 0.25), block) }
    }

    private func advance() {
        switch step {
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
        case .welcome:
            // Skip Add Dog if iCloud already synced dogs back (e.g. reinstall).
            stepAnimate { step = existingPets.isEmpty ? .addDog : .sync }
        default:
            stepAnimate {
                if let next = OnboardingStep(rawValue: step.rawValue + 1) { step = next }
            }
        }
    }

    private func saveDog() {
        let existingCount = (try? modelContext.fetchCount(FetchDescriptor<Pet>())) ?? 0
        var seen = Set<String>()
        var created = 0
        for trimmed in validDogNames {
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            // Free tier is limited to 1 dog total across all sources (including iCloud-synced dogs).
            if !entitlements.isPro && existingCount + created >= 1 { break }
            modelContext.insert(Pet(name: trimmed))
            created += 1
        }
    }

    private func saveReminder() {
        guard reminderEnabled else { return }
        let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        reminderMode = .allDogs
        allDogsReminderTimesRaw = "\(minutes)"
        NotificationManager.shared.scheduleAllDogsReminders(times: [minutes], petNames: validDogNames.isEmpty ? [petName] : validDogNames)
    }
}
