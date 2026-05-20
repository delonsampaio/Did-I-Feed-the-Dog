import Foundation
import SwiftData

@Model
final class MedicationLog {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var notes: String = ""
    var loggedBy: String = ""

    var medication: Medication?

    init(timestamp: Date = .now, notes: String = "", loggedBy: String, medication: Medication?) {
        self.id = UUID()
        self.timestamp = timestamp
        self.notes = notes
        self.loggedBy = loggedBy
        self.medication = medication
    }
}
