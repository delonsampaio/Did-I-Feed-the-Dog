import Foundation
import SwiftData

@Model
final class MedicationLog {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var notes: String = ""
    var loggedBy: String = ""
    /// Denormalized name captured at log time so history survives medication deletion.
    var medicationName: String = ""
    /// Denormalized pet ID so logs remain queryable after medication deletion.
    var petId: UUID?

    var medication: Medication?

    init(timestamp: Date = .now, notes: String = "", loggedBy: String, medication: Medication?) {
        self.id = UUID()
        self.timestamp = timestamp
        self.notes = notes
        self.loggedBy = loggedBy
        self.medication = medication
        self.medicationName = medication?.name ?? ""
        self.petId = medication?.pet?.id
    }
}
