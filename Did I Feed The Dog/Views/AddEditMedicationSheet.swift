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
    @State private var preferredReminderTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    @State private var showDeleteConfirm = false

    private let frequencyOptions = [8, 12, 24, 48, 72, 168]

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
                        Toggle("Remind me at a specific time", isOn: $useFixedTime.animation())
                            .tint(.purple)
                        if useFixedTime {
                            DatePicker("Reminder time", selection: $preferredReminderTime, displayedComponents: .hourAndMinute)
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
        .presentationDetents([.medium, .large])
    }

    private func prefill() {
        guard let med = medication else { return }
        name = med.name
        dose = med.dose
        frequencyHours = med.frequencyHours
        notificationsEnabled = med.notificationsEnabled
        if let minutes = med.preferredReminderMinutes {
            useFixedTime = true
            preferredReminderTime = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        }
    }

    private func reminderMinutes(from date: Date) -> Int {
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
        default:  return "Every \(hours)h"
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDose = dose.trimmingCharacters(in: .whitespaces)
        let enableNotifs = notificationsEnabled && entitlements.isPro
        let resolvedReminderMinutes: Int? = (enableNotifs && useFixedTime) ? reminderMinutes(from: preferredReminderTime) : nil

        if let med = medication {
            med.name = trimmedName
            med.dose = trimmedDose
            med.frequencyHours = frequencyHours
            med.notificationsEnabled = enableNotifs
            med.preferredReminderMinutes = resolvedReminderMinutes
            if enableNotifs {
                NotificationManager.shared.scheduleMedicationReminder(for: med, petName: pet.name ?? "your dog")
            } else {
                NotificationManager.shared.removeMedicationReminder(for: med)
            }
        } else {
            let newMed = Medication(name: trimmedName, dose: trimmedDose, frequencyHours: frequencyHours, notificationsEnabled: enableNotifs)
            newMed.preferredReminderMinutes = resolvedReminderMinutes
            newMed.pet = pet
            modelContext.insert(newMed)
        }

        try? modelContext.save()
        dismiss()
    }

    private func delete() {
        guard let med = medication else { return }
        NotificationManager.shared.removeMedicationReminder(for: med)
        modelContext.delete(med)
        try? modelContext.save()
        dismiss()
    }
}
