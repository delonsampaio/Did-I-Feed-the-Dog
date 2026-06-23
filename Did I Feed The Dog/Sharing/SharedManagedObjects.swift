import CoreData
import Foundation

@objc(SharedPet)
final class SharedPet: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String?
    @NSManaged var birthday: Date?
    @NSManaged var photoData: Data?
    @NSManaged var foodStockCount: Int64
    @NSManaged var feedingScheduleTimesRaw: String
    @NSManaged var isFasting: Bool
    @NSManaged var notificationsMuted: Bool
    @NSManaged var lastFeedingDate: Date?
    @NSManaged var todaysFeedingCountRaw: Int64
    // sync bookkeeping (unused in Phase 1)
    @NSManaged var ckRecordName: String?
    @NSManaged var ckSystemFields: Data?
    @NSManaged var ckZoneName: String?
    @NSManaged var ckDatabaseScope: Int16
    @NSManaged var feedingEvents: NSSet?
    @NSManaged var medications: NSSet?
}

@objc(SharedFeedingEvent)
final class SharedFeedingEvent: NSManagedObject {
    @NSManaged var timestamp: Date
    @NSManaged var mealType: String?
    @NSManaged var notes: String
    @NSManaged var loggedBy: String?
    @NSManaged var didDeductStock: NSNumber?     // optional Bool
    @NSManaged var portionsDeducted: NSNumber?   // optional Int
    @NSManaged var ckRecordName: String?
    @NSManaged var ckSystemFields: Data?
    @NSManaged var ckZoneName: String?
    @NSManaged var ckDatabaseScope: Int16
    @NSManaged var pet: SharedPet?
}

@objc(SharedMedication)
final class SharedMedication: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var dose: String
    @NSManaged var frequencyHours: Int64
    @NSManaged var notificationsEnabled: Bool
    @NSManaged var reminderMinutesRaw: String
    @NSManaged var lastGivenDate: Date?
    @NSManaged var ckRecordName: String?
    @NSManaged var ckSystemFields: Data?
    @NSManaged var ckZoneName: String?
    @NSManaged var ckDatabaseScope: Int16
    @NSManaged var pet: SharedPet?
    @NSManaged var logs: NSSet?
}

@objc(SharedMedicationLog)
final class SharedMedicationLog: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var timestamp: Date
    @NSManaged var notes: String
    @NSManaged var loggedBy: String
    @NSManaged var medicationName: String
    @NSManaged var petId: UUID?
    @NSManaged var ckRecordName: String?
    @NSManaged var ckSystemFields: Data?
    @NSManaged var ckZoneName: String?
    @NSManaged var ckDatabaseScope: Int16
    @NSManaged var medication: SharedMedication?
}

extension SharedMedication {
    /// Mirrors SwiftData `Medication.reminderMinutes`: [Int] backed by a comma-joined string.
    var reminderMinutes: [Int] {
        get { reminderMinutesRaw.split(separator: ",").compactMap { Int($0) } }
        set { reminderMinutesRaw = newValue.map(String.init).joined(separator: ",") }
    }
}
