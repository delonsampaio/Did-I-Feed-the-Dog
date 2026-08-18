import CoreData
import SwiftUI

/// Mirrors AddEditMedicationSheet minus its Notifications section (Dose Reminder, fixed-time
/// pickers) — notifications for shared dogs are out of scope this phase. nil medication = new.
struct EditSharedMedicationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pet: SharedPet
    var medication: SharedMedication?

    @State private var name = ""
    @State private var dose = ""
    @State private var frequencyHours = 24
    @State private var showDeleteConfirm = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    private let frequencyOptions = [8, 12, 24, 48, 72, 168, 720]

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
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
        .presentationSizing(.page)
        .presentationDetents([.medium, .large])
    }

    private func prefill() {
        guard let med = medication else { return }
        name = med.name
        dose = med.dose
        frequencyHours = Int(med.frequencyHours)
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
        guard let context = pet.managedObjectContext else {
            saveErrorMessage = "Failed to save: no context"
            showSaveError = true
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDose = dose.trimmingCharacters(in: .whitespaces)

        if let med = medication {
            med.name = trimmedName
            med.dose = trimmedDose
            med.frequencyHours = Int64(frequencyHours)
        } else {
            let newMed = SharedMedication(context: context)
            newMed.id = UUID()
            newMed.name = trimmedName
            newMed.dose = trimmedDose
            newMed.frequencyHours = Int64(frequencyHours)
            newMed.notificationsEnabled = false
            newMed.reminderMinutesRaw = ""
            newMed.ckRecordName = UUID().uuidString
            newMed.pet = pet
        }

        do {
            try context.save()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to save: \(error.localizedDescription)"
            showSaveError = true
        }
    }

    private func delete() {
        guard let med = medication, let context = pet.managedObjectContext else { return }
        for log in (med.logs as? Set<SharedMedicationLog>) ?? [] { log.medication = nil }
        context.delete(med)
        do {
            try context.save()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to delete: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
