import CoreData
import Foundation
import SwiftData

/// Clones a dog's full data graph between the owned SwiftData store and the shared Core Data
/// store. `migrateToShared` runs the first time a dog is shared: the caller deletes the source
/// `Pet` only after this succeeds. `migrateToOwned` is the mirror, run when the owner stops
/// sharing, so they never lose data by unsharing.
@MainActor
enum SharePreparationController {

    /// Clones `pet` (and its feeding events, medications, medication logs) into a new
    /// `SharedPet` on `sharedContext`, reusing `pet.id` so the CloudKit zone name
    /// (`"Zone-\(id)"`) stays stable. Every new shared object gets a fresh `ckRecordName`
    /// stamped BEFORE save, since `SharedSyncEngine`'s push observer only picks up objects
    /// that already have one at save time. On save failure, rolls back and rethrows —
    /// the source `Pet` is never touched here.
    static func migrateToShared(
        pet: Pet,
        sharedContext: NSManagedObjectContext = SharedDataStack.shared.viewContext
    ) throws -> SharedPet {
        let sharedPet = SharedPet(context: sharedContext)
        sharedPet.id = pet.id
        sharedPet.name = pet.name
        sharedPet.birthday = pet.birthday
        sharedPet.photoData = pet.photoData
        sharedPet.foodStockCount = Int64(pet.foodStockCount)
        sharedPet.feedingScheduleTimesRaw = pet.feedingScheduleTimesRaw
        sharedPet.isFasting = pet.isFasting
        sharedPet.notificationsMuted = pet.notificationsMuted
        sharedPet.lastFeedingDate = pet.lastFeedingDate
        sharedPet.todaysFeedingCountRaw = Int64(pet.todaysFeedingCount)
        sharedPet.ckRecordName = UUID().uuidString

        for event in pet.feedingEvents ?? [] {
            let sharedEvent = SharedFeedingEvent(context: sharedContext)
            sharedEvent.timestamp = event.timestamp
            sharedEvent.mealType = event.mealType
            sharedEvent.notes = event.notes
            sharedEvent.loggedBy = event.loggedBy
            sharedEvent.didDeductStock = event.didDeductStock.map { NSNumber(value: $0) }
            sharedEvent.portionsDeducted = event.portionsDeducted.map { NSNumber(value: $0) }
            sharedEvent.ckRecordName = UUID().uuidString
            sharedEvent.pet = sharedPet
        }

        for medication in pet.medications ?? [] {
            let sharedMed = SharedMedication(context: sharedContext)
            sharedMed.id = medication.id
            sharedMed.name = medication.name
            sharedMed.dose = medication.dose
            sharedMed.frequencyHours = Int64(medication.frequencyHours)
            sharedMed.notificationsEnabled = medication.notificationsEnabled
            sharedMed.reminderMinutes = medication.reminderMinutes
            sharedMed.lastGivenDate = medication.lastGivenDate
            sharedMed.ckRecordName = UUID().uuidString
            sharedMed.pet = sharedPet

            for log in medication.logs ?? [] {
                let sharedLog = SharedMedicationLog(context: sharedContext)
                sharedLog.id = log.id
                sharedLog.timestamp = log.timestamp
                sharedLog.notes = log.notes
                sharedLog.loggedBy = log.loggedBy
                sharedLog.medicationName = log.medicationName
                sharedLog.petId = log.petId
                sharedLog.ckRecordName = UUID().uuidString
                sharedLog.medication = sharedMed
            }
        }

        do {
            try sharedContext.save()
        } catch {
            sharedContext.rollback()
            throw error
        }
        return sharedPet
    }

    /// Clones `sharedPet` back into a new owned `Pet` on `modelContext`, reusing `sharedPet.id`.
    /// Caller proceeds to `ShareController.stopSharing` only after this succeeds, so a failed
    /// reverse migration never destroys the shared copy. Idempotent by id: if a Pet with
    /// `sharedPet.id` already exists (a retry after `ShareController.stopSharing`'s CloudKit
    /// zone-delete failed on a prior attempt — this function already committed the owned Pet
    /// before that call runs), returns the existing Pet instead of inserting a duplicate.
    static func migrateToOwned(sharedPet: SharedPet, modelContext: ModelContext) throws -> Pet {
        let sharedPetId = sharedPet.id
        let existing = FetchDescriptor<Pet>(predicate: #Predicate { $0.id == sharedPetId })
        if let alreadyMigrated = try? modelContext.fetch(existing).first {
            return alreadyMigrated
        }

        let pet = Pet(name: sharedPet.name)
        pet.id = sharedPet.id
        pet.birthday = sharedPet.birthday
        pet.photoData = sharedPet.photoData
        pet.foodStockCount = Int(sharedPet.foodStockCount)
        pet.feedingScheduleTimesRaw = sharedPet.feedingScheduleTimesRaw
        pet.isFasting = sharedPet.isFasting
        pet.notificationsMuted = sharedPet.notificationsMuted
        pet.lastFeedingDate = sharedPet.lastFeedingDate
        pet.todaysFeedingCount = Int(sharedPet.todaysFeedingCountRaw)
        modelContext.insert(pet)

        let sharedEvents = (sharedPet.feedingEvents as? Set<SharedFeedingEvent>) ?? []
        for sharedEvent in sharedEvents {
            let event = FeedingEvent(
                timestamp: sharedEvent.timestamp,
                mealType: sharedEvent.mealType,
                notes: sharedEvent.notes,
                loggedBy: sharedEvent.loggedBy,
                pet: pet,
                didDeductStock: sharedEvent.didDeductStock?.boolValue
            )
            event.portionsDeducted = sharedEvent.portionsDeducted?.intValue
            modelContext.insert(event)
        }

        let sharedMeds = (sharedPet.medications as? Set<SharedMedication>) ?? []
        for sharedMed in sharedMeds {
            let medication = Medication(
                name: sharedMed.name,
                dose: sharedMed.dose,
                frequencyHours: Int(sharedMed.frequencyHours),
                notificationsEnabled: sharedMed.notificationsEnabled
            )
            medication.id = sharedMed.id
            medication.reminderMinutes = sharedMed.reminderMinutes
            medication.lastGivenDate = sharedMed.lastGivenDate
            medication.pet = pet
            modelContext.insert(medication)

            let sharedLogs = (sharedMed.logs as? Set<SharedMedicationLog>) ?? []
            for sharedLog in sharedLogs {
                let log = MedicationLog(
                    timestamp: sharedLog.timestamp,
                    notes: sharedLog.notes,
                    loggedBy: sharedLog.loggedBy,
                    medication: medication
                )
                log.id = sharedLog.id
                log.medicationName = sharedLog.medicationName
                log.petId = sharedLog.petId
                modelContext.insert(log)
            }
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return pet
    }
}
