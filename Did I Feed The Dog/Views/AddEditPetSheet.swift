import SwiftUI
import SwiftData
import PhotosUI

struct AddEditPetSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("birthdayPushEnabled") private var birthdayPushEnabled = true
    @AppStorage("stockMode") private var stockMode: StockMode = .individual

    var pet: Pet? // nil = create mode

    @State private var name = ""
    @State private var birthday = Date()
    @State private var foodStockCount = 0
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?

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
                    Section("Food Stock") {
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
            }
            .navigationTitle(pet == nil ? "Add Dog" : "Edit \(pet!.name)")
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
        name = pet.name
        birthday = pet.birthday
        foodStockCount = pet.foodStockCount
        photoData = pet.photoData
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let pet {
            pet.name = trimmedName
            pet.birthday = birthday
            pet.photoData = photoData
            pet.foodStockCount = foodStockCount
            if birthdayPushEnabled {
                NotificationManager.shared.scheduleBirthdayNotification(for: pet)
            }
        } else {
            let newPet = Pet(name: trimmedName, birthday: birthday, photoData: photoData, foodStockCount: foodStockCount)
            modelContext.insert(newPet)
            if birthdayPushEnabled {
                NotificationManager.shared.scheduleBirthdayNotification(for: newPet)
            }
        }
        dismiss()
    }
}
