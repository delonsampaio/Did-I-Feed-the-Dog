import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("reminderMode")            private var reminderMode: ReminderMode = .none
    @AppStorage("allDogsReminderTimesRaw") private var allDogsReminderTimesRaw = ""

    @State private var step = 0
    @State private var dogNames: [String] = [""]
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
                    case 0: welcomeStep
                    case 1: addDogStep
                    case 2: syncStep
                    case 3: reminderStep
                    default: doneStep
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
            ForEach(0..<5) { i in
                Capsule()
                    .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: i == step ? 24 : 8, height: 8)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: step)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of 5")
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

    private var doneStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("You're All Set!")
                    .font(.largeTitle.bold())

                Text("Head to the dashboard to log \(petName)'s first meal.")
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
            Button(action: advance) {
                Text(step == 4 ? "Get Started" : "Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canAdvance ? Color.accentColor : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(!canAdvance)

            if step == 3 {
                Button("Skip for now") {
                    stepAnimate { step = 4 }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if step > 0 && step < 4 {
                Button("Back") {
                    stepAnimate { step -= 1 }
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

    private var canAdvance: Bool {
        if step == 1 {
            return dogNames.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return true
    }

    private func stepAnimate(_ block: @escaping () -> Void) {
        if reduceMotion { block() } else { withAnimation(.easeInOut(duration: 0.25), block) }
    }

    private func advance() {
        switch step {
        case 1:
            stepAnimate { step = 2 }
        case 3:
            stepAnimate { step = 4 }
        case 4:
            saveDog()
            saveReminder()
            dismiss()
        default:
            stepAnimate { step += 1 }
        }
    }

    private func saveDog() {
        for name in dogNames {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            modelContext.insert(Pet(name: trimmed))
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
