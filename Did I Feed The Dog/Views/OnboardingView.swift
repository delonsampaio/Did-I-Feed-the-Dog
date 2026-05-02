import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("reminderMode")            private var reminderMode: ReminderMode = .none
    @AppStorage("allDogsReminderTimesRaw") private var allDogsReminderTimesRaw = ""

    @State private var step = 0
    @State private var dogName = ""
    @State private var reminderEnabled = false
    @State private var reminderTime: Date = Calendar.current.date(
        bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now

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
                    case 2: reminderStep
                    default: doneStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

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
            ForEach(0..<4) { i in
                Capsule()
                    .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: i == step ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
                .padding(28)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 28))

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

            TextField("Dog's name", text: $dogName)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 32)
    }

    private var reminderStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Set a Reminder")
                    .font(.title.bold())

                Text("Get a daily nudge so \(petName) never misses a meal.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Toggle("Daily Feeding Reminder", isOn: $reminderEnabled)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

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
                Text(step == 3 ? "Get Started" : "Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canAdvance ? Color.accentColor : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(!canAdvance)

            if step == 2 {
                Button("Skip for now") {
                    withAnimation(.easeInOut(duration: 0.25)) { step = 3 }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if step > 0 && step < 3 {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.25)) { step -= 1 }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var petName: String {
        let trimmed = dogName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "your dog" : trimmed
    }

    private var canAdvance: Bool {
        step == 1 ? !dogName.trimmingCharacters(in: .whitespaces).isEmpty : true
    }

    private func advance() {
        switch step {
        case 1:
            saveDog()
            withAnimation(.easeInOut(duration: 0.25)) { step = 2 }
        case 2:
            saveReminder()
            withAnimation(.easeInOut(duration: 0.25)) { step = 3 }
        case 3:
            dismiss()
        default:
            withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
        }
    }

    private func saveDog() {
        let name = dogName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        modelContext.insert(Pet(name: name))
    }

    private func saveReminder() {
        guard reminderEnabled else { return }
        let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        reminderMode = .allDogs
        allDogsReminderTimesRaw = "\(minutes)"
        NotificationManager.shared.scheduleAllDogsReminders(times: [minutes], petNames: [petName])
    }
}
