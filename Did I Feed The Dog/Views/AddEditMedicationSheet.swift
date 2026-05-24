import SwiftUI
import SwiftData

struct AddEditMedicationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementManager.self) private var entitlements

    let pet: Pet
    var medication: Medication? // nil = new

    @State private var name = ""
    @State private var dose = ""
    @State private var frequencyHours = 24
    @State private var notificationsEnabled = false
    @State private var useFixedTime = false
    @State private var reminderTimes: [Date] = [
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    ]
    @State private var showDeleteConfirm = false

    private let frequencyOptions = [8, 12, 24, 48, 72, 168, 720]

    private var requiredReminderCount: Int {
        switch frequencyHours {
        case 8:  return 3
        case 12: return 2
        default: return 1
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Name (e.g. Heartgard, Prednisone)", text: $name)
                    TextField("Dose — optional (e.g. 25mg, 1 tablet)", text: $dose)
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $frequencyHours) {
                        ForEach(frequencyOptions, id: \.self) { hours in
                            Text(frequencyLabel(hours)).tag(hours)
                        }
                    }
                }

                Section {
                    Toggle(isOn: $notificationsEnabled) {
                        HStack(spacing: 6) {
                            Text("Dose Reminder")
                            if !entitlements.isPro {
                                Text("PRO")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                    .tint(.purple)
                    .disabled(!entitlements.isPro)
                    if notificationsEnabled && entitlements.isPro {
                        Toggle("Remind me at specific times", isOn: $useFixedTime.animation())
                            .tint(.purple)
                        if useFixedTime {
                            ForEach(reminderTimes.indices, id: \.self) { i in
                                DatePicker(
                                    "Dose \(i + 1)",
                                    selection: $reminderTimes[i],
                                    displayedComponents: .hourAndMinute
                                )
                            }
                        } else {
                            Text("Reminder fires \(frequencyLabel(frequencyHours).lowercased()) after your last logged dose.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !entitlements.isPro {
                        Text("Upgrade to Pro to get a push reminder when a dose is due.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Notifications")
                }

                if medication != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Medication", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(medication == nil ? "Add Medication" : "Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { prefill() }
            .onChange(of: frequencyHours) { _, _ in
                guard useFixedTime else { return }
                adjustReminderTimes()
            }
            .onChange(of: useFixedTime) { _, newValue in
                if newValue { adjustReminderTimes() }
            }
            .confirmationDialog(
                "Delete \(medication?.name ?? "Medication")?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("This will also remove all log history for this medication.")
            }
        }
        .presentationSizing(.page)
        .presentationDetents([.medium, .large])
    }

    private func prefill() {
        guard let med = medication else { return }
        name = med.name
        dose = med.dose
        frequencyHours = med.frequencyHours
        notificationsEnabled = med.notificationsEnabled
        if !med.reminderMinutes.isEmpty {
            useFixedTime = true
            reminderTimes = med.reminderMinutes.map { minutes in
                Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            }
        }
    }

    private func adjustReminderTimes() {
        let needed = requiredReminderCount
        let defaults = defaultReminderTimes(for: frequencyHours)
        if reminderTimes.count < needed {
            reminderTimes += defaults.suffix(needed - reminderTimes.count)
        } else if reminderTimes.count > needed {
            reminderTimes = Array(reminderTimes.prefix(needed))
        }
    }

    private func defaultReminderTimes(for hours: Int) -> [Date] {
        let cal = Calendar.current
        func t(_ h: Int) -> Date { cal.date(bySettingHour: h, minute: 0, second: 0, of: .now) ?? .now }
        switch hours {
        case 8:  return [t(8), t(12), t(18)]
        case 12: return [t(8), t(20)]
        default: return [t(8)]
        }
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 8) * 60 + (c.minute ?? 0)
    }

    private func frequencyLabel(_ hours: Int) -> String {
        switch hours {
        case 8:   return "3 times daily"
        case 12:  return "Twice daily"
        case 24:  return "Daily"
        case 48:  return "Every 2 days"
        case 72:  return "Every 3 days"
        case 168: return "Weekly"
        case 720: return "Monthly"
        default:  return "Every \(hours)h"
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDose = dose.trimmingCharacters(in: .whitespaces)
        let enableNotifs = notificationsEnabled && entitlements.isPro
        let resolvedReminderMinutes: [Int] = (enableNotifs && useFixedTime)
            ? reminderTimes.map { minutesFromDate($0) }
            : []

        if let med = medication {
            med.name = trimmedName
            med.dose = trimmedDose
            med.frequencyHours = frequencyHours
            med.notificationsEnabled = enableNotifs
            med.reminderMinutes = resolvedReminderMinutes
            if enableNotifs {
                NotificationManager.shared.scheduleMedicationReminder(for: med, petName: pet.name ?? "your dog")
            } else {
                NotificationManager.shared.removeMedicationReminder(for: med)
            }
        } else {
            let newMed = Medication(name: trimmedName, dose: trimmedDose, frequencyHours: frequencyHours, notificationsEnabled: enableNotifs)
            newMed.reminderMinutes = resolvedReminderMinutes
            newMed.pet = pet
            modelContext.insert(newMed)
        }

        try? modelContext.save()
        dismiss()
    }

    private func delete() {
        guard let med = medication else { return }
        NotificationManager.shared.removeMedicationReminder(for: med)
        for log in med.logs ?? [] { log.medication = nil }
        modelContext.delete(med)
        try? modelContext.save()
        dismiss()
    }
}
