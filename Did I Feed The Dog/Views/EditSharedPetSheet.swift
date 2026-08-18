import CoreData
import PhotosUI
import SwiftUI

/// Edit-only equivalent of AddEditPetSheet for shared dogs — a SharedPet is only ever created by
/// migration (SharePreparationController), never fresh through this sheet, so there is no "Add"
/// mode. Mirrors AddEditPetSheet's actual Form fields exactly: photo, name, birthday, fasting,
/// food stock (always shown here — unlike the owned sheet, never behind a Pro paywall), and mute
/// notifications (stored only; no NotificationManager call, matching this phase's scope).
struct EditSharedPetSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pet: SharedPet

    @State private var name = ""
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var foodStockCount = 0
    @State private var photoData: Data?
    @State private var selectedAvatarName: String?
    @State private var showAvatarPicker = false
    @State private var isFasting = false
    @State private var notificationsMuted = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Dog Info") {
                    Button { showAvatarPicker = true } label: {
                        HStack(spacing: 14) {
                            photoPreview
                            Text(photoData == nil ? "Add Photo" : "Change Photo")
                                .foregroundStyle(.blue)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    TextField("Name", text: $name)
                    Toggle("Add Birthday", isOn: $hasBirthday.animation())
                    if hasBirthday {
                        DatePicker("Birthday", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                    }
                }

                Section("Health") {
                    Toggle("Fasting Mode", isOn: $isFasting)
                        .tint(.red)
                    if isFasting {
                        Text("A DO NOT FEED warning will appear on the dashboard.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(
                    header: Text("Food Stock"),
                    footer: Text("Snack and Treat meals do not reduce the portion count.")
                ) {
                    Stepper(value: $foodStockCount, in: 0...999) {
                        HStack {
                            Text("Portions")
                            Spacer()
                            Text("\(foodStockCount)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    HStack {
                        Text("Type a number")
                        Spacer()
                        TextField("0", value: $foodStockCount, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                }

                Section("Alerts & Reminders") {
                    Toggle("Mute Notifications", isOn: $notificationsMuted)
                }
            }
            .navigationTitle("Edit \(pet.name ?? "Unknown")")
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
            .sheet(isPresented: $showAvatarPicker) {
                AvatarPickerSheet(selectedAvatarName: $selectedAvatarName, photoData: $photoData)
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
        .presentationSizing(.page)
    }

    private var photoPreview: some View {
        Group {
            if let data = photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.title2)
                    .frame(width: 60, height: 60)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            }
        }
    }

    private func prefill() {
        name = pet.name ?? ""
        if let stored = pet.birthday {
            hasBirthday = true
            birthday = stored
        } else {
            hasBirthday = false
            birthday = Date()
        }
        foodStockCount = pet.effectiveFoodStockCount
        photoData = pet.photoData
        isFasting = pet.isFasting
        notificationsMuted = pet.notificationsMuted
    }

    private func save() {
        guard let context = pet.managedObjectContext else {
            saveErrorMessage = "Failed to save: no context"
            showSaveError = true
            return
        }
        pet.name = name.trimmingCharacters(in: .whitespaces)
        pet.birthday = hasBirthday ? birthday : nil
        pet.photoData = photoData
        pet.isFasting = isFasting
        pet.notificationsMuted = notificationsMuted
        // Editing the stock number here is a restock, same as SharedRestockSheet: reset the
        // baseline so effectiveFoodStockCount reads back exactly what was typed. Only touch the
        // baseline if the value actually changed, so saving unrelated fields (name, photo, ...)
        // doesn't silently discard deductions recorded since the last real restock.
        if foodStockCount != pet.effectiveFoodStockCount {
            pet.foodStockCount = Int64(foodStockCount)
            pet.foodStockBaselineDate = .now
        }
        do {
            try context.save()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to save: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
