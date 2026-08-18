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
    @NSManaged var todaysFeedingCountRaw: Int64
    @NSManaged var foodStockBaselineDate: Date?
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

    /// Mirrors `Medication.isDue` via the shared `medicationIsDue` rule, so a shared
    /// dog's due-medication banner can never drift from the owned-dog one.
    var isDue: Bool {
        medicationIsDue(frequencyHours: Int(frequencyHours), reminderMinutes: reminderMinutes, lastGivenDate: lastGivenDate)
    }
}

extension SharedPet {
    /// Current stock, derived from the last manually-set baseline minus every feeding logged
    /// since. Two devices logging concurrently each create a new SharedFeedingEvent rather than
    /// mutating a shared counter, so CloudKit sync merges them with nothing to conflict on.
    var effectiveFoodStockCount: Int {
        let events = (feedingEvents as? Set<SharedFeedingEvent>) ?? []
        let since = foodStockBaselineDate ?? .distantPast
        let deducted = events
            .filter { $0.timestamp > since }
            .reduce(0) { $0 + ($1.portionsDeducted?.intValue ?? 0) }
        return max(0, Int(foodStockCount) - deducted)
    }
}

extension SharedMedication {
    /// Mirrors Medication.frequencyLabel so SharedPetDetailView's medication row can display
    /// this without a second copy of the switch statement.
    var frequencyLabel: String {
        switch frequencyHours {
        case 8:   return "3 times daily"
        case 12:  return "Twice daily"
        case 24:  return "Daily"
        case 48:  return "Every 2 days"
        case 72:  return "Every 3 days"
        case 168: return "Weekly"
        case 720: return "Monthly"
        default:  return "Every \(frequencyHours)h"
        }
    }
}

extension SharedFeedingEvent: Identifiable {
    /// SharedFeedingEvent has no stored `id` field (unlike SharedMedication/SharedMedicationLog,
    /// which do) — objectID is stable for the object's lifetime in a context and is enough for
    /// SwiftUI's `.sheet(item:)`, which only needs identity, not a persisted business key.
    public var id: NSManagedObjectID { objectID }
}

extension SharedMedication: Identifiable {}
