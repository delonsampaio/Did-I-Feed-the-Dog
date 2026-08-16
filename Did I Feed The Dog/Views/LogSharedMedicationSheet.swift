import CoreData
import SwiftUI

struct LogSharedMedicationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pet: SharedPet
    let medications: [SharedMedication]

    @State private var selectedMedication: SharedMedication?
    @State private var notes = ""
    @State private var showCustomTime = false
    @State private var logDate = Date()
    @State private var isSubmitting = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                if medications.count > 1 {
                    medicationPicker
                }

                VStack(spacing: 12) {
                    Toggle("Set custom time", isOn: $showCustomTime.animation())
                        .tint(.purple)
                    if showCustomTime {
                        DatePicker("Time", selection: $logDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    }
                }
                .padding(.horizontal)

                TextField("Add a note (optional)", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...3)
                    .padding(.horizontal)

                Spacer()
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .safeAreaInset(edge: .bottom) {
                logButton
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.bottom)
            }
            .navigationTitle(medications.count == 1 ? medications[0].name : "Log Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { selectedMedication = medications.first }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
        .presentationSizing(.page)
        .presentationDetents([.fraction(0.55), .large])
    }

    @ViewBuilder
    private var medicationPicker: some View {
        let columns = [GridItem(.adaptive(minimum: 120))]
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(medications, id: \.objectID) { med in
                let isSelected = selectedMedication?.objectID == med.objectID
                Button {
                    selectedMedication = med
                } label: {
                    VStack(spacing: 4) {
                        Text("💊").font(.title2).accessibilityHidden(true)
                        Text(med.name)
                            .font(.caption).fontWeight(.medium)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSelected ? Color.purple.opacity(0.2) : Color(.secondarySystemBackground))
                    .foregroundStyle(isSelected ? .purple : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.purple : .clear, lineWidth: 2)
                    )
                }
                .accessibilityLabel(med.name)
                .accessibilityValue(isSelected ? "Selected" : "")
            }
        }
        .padding(.horizontal)
    }

    private var logButton: some View {
        Button(action: logDose) {
            Label("Log Dose", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(selectedMedication != nil ? Color.purple : Color.gray.opacity(0.3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(selectedMedication == nil || isSubmitting)
    }

    private func logDose() {
        guard let med = selectedMedication, !isSubmitting else { return }
        isSubmitting = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let timestamp = showCustomTime ? logDate : .now
        guard let context = med.managedObjectContext else {
            saveErrorMessage = "Failed to save dose: no context"
            showSaveError = true
            isSubmitting = false
            return
        }

        let log = SharedMedicationLog(context: context)
        log.id = UUID()
        log.timestamp = timestamp
        log.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        log.loggedBy = LoggedBy.current
        log.medicationName = med.name
        log.petId = pet.id
        log.ckRecordName = UUID().uuidString
        log.medication = med
        med.lastGivenDate = timestamp

        do {
            try context.save()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to save dose: \(error.localizedDescription)"
            showSaveError = true
            isSubmitting = false
        }
    }
}
