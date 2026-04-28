import SwiftUI
import SwiftData
import PhotosUI

struct AddEditPetSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("birthdayPushEnabled") private var birthdayPushEnabled = true
    @AppStorage("stockMode")           private var stockMode: StockMode = .individual
    @AppStorage("reminderMode")        private var reminderMode: ReminderMode = .none

    var pet: Pet?

    @State private var name = ""
    @State private var birthday = Date()
    @State private var foodStockCount = 0
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var feedingTimes: [Date] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Dog Info") {
                    TextField("Name", text: $name)
                    DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                }

                Section("Photo") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack {
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
                            }
                            Text(photoData == nil ? "Add Photo" : "Change Photo")
                                .foregroundStyle(.blue)
                        }
                    }
                    .onChange(of: selectedPhoto) { _, newItem in
                        Task {
                            photoData = try? await newItem?.loadTransferable(type: Data.self)
                        }
                    }
                }

                if stockMode == .individual {
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
                            Text("Enter directly")
                            Spacer()
                            TextField("0", value: $foodStockCount, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                        }
                    }
                }

                if reminderMode == .perDog {
                    Section("Feeding Reminders") {
                        ForEach(Array(feedingTimes.enumerated()), id: \.offset) { index, time in
                            HStack {
                                DatePicker(
                                    "Time \(index + 1)",
                                    selection: Binding(
                                        get: { feedingTimes[index] },
                                        set: { feedingTimes[index] = $0 }
                                    ),
                                    displayedComponents: .hourAndMinute
                                )
                                Button(role: .destructive) {
                                    feedingTimes.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if feedingTimes.count < 3 {
                            Button {
                                feedingTimes.append(
                                    Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
                                )
                            } label: {
                                Label("Add Reminder Time", systemImage: "plus.circle.fill")
                            }
                        }
                    }
                }
            }
            .navigationTitle(pet == nil ? "Add Dog" : "Edit \(pet?.name ?? "Unknown")")
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
            .onAppear { prefillIfEditing() }
        }
    }

    private func prefillIfEditing() {
        guard let pet else { return }
        name = pet.name ?? ""
        birthday = pet.birthday ?? Date()
        foodStockCount = pet.foodStockCount
        photoData = pet.photoData
        feedingTimes = pet.feedingScheduleTimes.map { minutes in
            Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let times = feedingTimes.map { date -> Int in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }

        if let pet {
            pet.name = trimmedName
            pet.birthday = birthday
            pet.photoData = photoData
            pet.foodStockCount = foodStockCount
            pet.feedingScheduleTimes = times
            if birthdayPushEnabled {
                NotificationManager.shared.scheduleBirthdayNotification(for: pet)
            }
            if reminderMode == .perDog {
                NotificationManager.shared.schedulePerDogReminders(for: pet, times: times)
            }
        } else {
            let newPet = Pet(name: trimmedName, birthday: birthday, photoData: photoData, foodStockCount: foodStockCount)
            newPet.feedingScheduleTimes = times
            modelContext.insert(newPet)
            if birthdayPushEnabled {
                NotificationManager.shared.scheduleBirthdayNotification(for: newPet)
            }
            if reminderMode == .perDog {
                NotificationManager.shared.schedulePerDogReminders(for: newPet, times: times)
            }
        }
        dismiss()
    }
}
