import AppIntents
import SwiftUI
import SwiftData
import PhotosUI

struct AddEditPetSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementManager.self) private var entitlements
    @AppStorage("birthdayPushEnabled", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog")) private var birthdayPushEnabled = true
    @AppStorage("stockMode", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))           private var stockMode: StockMode = .individual
    @AppStorage("reminderMode", store: UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog"))        private var reminderMode: ReminderMode = .none

    var pet: Pet?

    @State private var name = ""
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var foodStockCount = 0
    @State private var photoData: Data?
    @State private var selectedAvatarName: String?
    @State private var showAvatarPicker = false
    @State private var feedingTimes: [Date] = []
    @State private var showPaywall = false
    @State private var pendingPetName: String? = nil

    // Feature #22
    @State private var isFasting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Dog Info") {
                    TextField("Name", text: $name)
                    Toggle("Add Birthday", isOn: $hasBirthday.animation())
                    if hasBirthday {
                        DatePicker("Birthday", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                    }
                }

                Section("Photo") {
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
                }
                
                // Feature #22: Medical Section
                Section("Medical") {
                    Toggle("Fasting Mode", isOn: $isFasting)
                        .tint(.red)
                    
                    if isFasting {
                        Text("Reminders and overdue alerts are disabled. A DO NOT FEED warning will appear on the dashboard.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                            Text("Type a number")
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
                                .accessibilityLabel("Delete reminder time \(index + 1)")
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
                        if hasReminderOverlap {
                            Label("Two reminder times are within 30 minutes of each other.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
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
            .sheet(isPresented: $showAvatarPicker) {
                AvatarPickerSheet(selectedAvatarName: $selectedAvatarName, photoData: $photoData)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallSheet(source: "addSecondDog", petName: pendingPetName)
                    .onDisappear {
                        if entitlements.isPro { performSave() }
                    }
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

    private func prefillIfEditing() {
        guard let pet else { return }
        name = pet.name ?? ""
        if let stored = pet.birthday {
            hasBirthday = true
            birthday = stored
        } else {
            hasBirthday = false
            birthday = Date()
        }
        foodStockCount = pet.foodStockCount
        photoData = pet.photoData
        isFasting = pet.isFasting
        feedingTimes = pet.feedingScheduleTimes.map { minutes in
            Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        }
    }

    private var hasReminderOverlap: Bool {
        guard feedingTimes.count >= 2 else { return false }
        let minutes = feedingTimes.map { date -> Int in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }.sorted()
        return zip(minutes, minutes.dropFirst()).contains { $1 - $0 < 30 }
    }

    private func save() {
        // Sunk-cost paywall: user has filled out the form; show paywall only now.
        if pet == nil && !entitlements.isPro {
            let existingCount = (try? modelContext.fetchCount(FetchDescriptor<Pet>())) ?? 0
            if existingCount >= 1 {
                pendingPetName = name.trimmingCharacters(in: .whitespaces)
                showPaywall = true
                return
            }
        }
        performSave()
    }

    private func performSave() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let resolvedBirthday: Date? = hasBirthday ? birthday : nil
        let times = feedingTimes.map { date -> Int in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }

        if let pet {
            pet.name = trimmedName
            pet.birthday = resolvedBirthday
            pet.photoData = photoData
            pet.foodStockCount = foodStockCount
            pet.isFasting = isFasting
            pet.feedingScheduleTimes = times

            if isFasting {
                NotificationManager.shared.removeOverdueNotification(for: pet)
                NotificationManager.shared.removePerDogReminders(for: pet)
            }

            // Birthday push only schedules when there IS a birthday and the
            // user opted into the push. Removing covers the "user cleared
            // their birthday" case.
            if birthdayPushEnabled, resolvedBirthday != nil {
                NotificationManager.shared.scheduleBirthdayNotification(for: pet)
            } else {
                NotificationManager.shared.removeBirthdayNotification(for: pet)
            }
            if reminderMode == .perDog && !isFasting {
                NotificationManager.shared.schedulePerDogReminders(for: pet, times: times)
            }
        } else {
            let newPet = Pet(name: trimmedName, birthday: resolvedBirthday, photoData: photoData, foodStockCount: foodStockCount, isFasting: isFasting)
            newPet.feedingScheduleTimes = times
            modelContext.insert(newPet)
            if birthdayPushEnabled, resolvedBirthday != nil {
                NotificationManager.shared.scheduleBirthdayNotification(for: newPet)
            }
            if reminderMode == .perDog && !isFasting {
                NotificationManager.shared.schedulePerDogReminders(for: newPet, times: times)
            }
        }
        
        WidgetDataWriter.write(from: modelContext)
        // Refresh Siri's pet vocabulary right away — adding/renaming a dog
        // here should let "Feed Rex" work without waiting for the dashboard
        // onChange to fire.
        DogFoodShortcuts.updateAppShortcutParameters()
        // Re-fetch + refresh reminders so renamed pets, fasting toggles, and
        // schedule edits propagate to the All-Dogs reminder body and per-dog
        // schedules.
        let allPets = (try? modelContext.fetch(FetchDescriptor<Pet>())) ?? []
        RemindersCoordinator.refresh(pets: allPets)
        dismiss()
    }
}

private struct AvatarPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedAvatarName: String?
    @Binding var photoData: Data?

    @State private var selectedPhoto: PhotosPickerItem?

    private let columns = [GridItem(.adaptive(minimum: 100))]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Upload Your Own Photo", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .onChange(of: selectedPhoto) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                photoData = compressed(data)
                                selectedAvatarName = nil
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(DefaultAvatars.all, id: \.self) { name in
                            avatarCell(name)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 16)
            }
            .navigationTitle("Choose Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func compressed(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let maxDim = AppConstants.photoMaxDimensionPoints
        let scale = min(maxDim / image.size.width, maxDim / image.size.height, 1.0)
        let targetSize = CGSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetSize)) }
        let qualityFloor = AppConstants.photoJPEGQualityFloor
        for quality in stride(
            from: AppConstants.photoJPEGQualityStart,
            through: qualityFloor,
            by: -AppConstants.photoJPEGQualityStep
        ) {
            if let jpeg = resized.jpegData(compressionQuality: quality),
               jpeg.count <= AppConstants.photoMaxJPEGBytes {
                return jpeg
            }
        }
        return resized.jpegData(compressionQuality: qualityFloor) ?? data
    }

    private func avatarCell(_ name: String) -> some View {
        let isSelected = selectedAvatarName == name
        return Button {
            selectedAvatarName = name
            // JPEG-compress the asset to keep photoData small. PNGs of stock
            // avatars were ~200-500KB each; JPEG at 0.8 quality is ~40KB and
            // visually identical for these flat-illustration avatars.
            if let uiImage = UIImage(named: name) {
                photoData = uiImage.jpegData(compressionQuality: AppConstants.photoJPEGQualityStart) ?? uiImage.pngData()
            }
            dismiss()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.title3)
                        .padding(4)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(name)
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}