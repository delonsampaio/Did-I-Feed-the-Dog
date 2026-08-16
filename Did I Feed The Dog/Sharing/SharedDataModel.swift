import CoreData

/// Builds the Core Data model for the shared-dog store programmatically so there is
/// no .xcdatamodeld bundle to manage. Mirrors the SwiftData Pet/FeedingEvent/
/// Medication/MedicationLog graph and adds CloudKit sync bookkeeping fields used
/// by the Phase 2 custom sync engine.
enum SharedDataModel {

    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let pet = entity("SharedPet", SharedPet.self)
        var event = entity("SharedFeedingEvent", SharedFeedingEvent.self)
        var med = entity("SharedMedication", SharedMedication.self)
        var log = entity("SharedMedicationLog", SharedMedicationLog.self)

        pet.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType, optional: true),
            attr("birthday", .dateAttributeType, optional: true),
            attr("photoData", .binaryDataAttributeType, optional: true),
            attr("foodStockCount", .integer64AttributeType, defaultValue: 0),
            attr("feedingScheduleTimesRaw", .stringAttributeType, defaultValue: ""),
            attr("isFasting", .booleanAttributeType, defaultValue: false),
            attr("notificationsMuted", .booleanAttributeType, defaultValue: false),
            attr("lastFeedingDate", .dateAttributeType, optional: true),
            attr("todaysFeedingCountRaw", .integer64AttributeType, defaultValue: 0),
            attr("foodStockBaselineDate", .dateAttributeType, optional: true),
        ] + syncFields()

        event.properties = [
            attr("timestamp", .dateAttributeType),
            attr("mealType", .stringAttributeType, optional: true),
            attr("notes", .stringAttributeType, defaultValue: ""),
            attr("loggedBy", .stringAttributeType, optional: true),
            attr("didDeductStock", .booleanAttributeType, optional: true),
            attr("portionsDeducted", .integer64AttributeType, optional: true),
        ] + syncFields()

        med.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType, defaultValue: ""),
            attr("dose", .stringAttributeType, defaultValue: ""),
            attr("frequencyHours", .integer64AttributeType, defaultValue: 24),
            attr("notificationsEnabled", .booleanAttributeType, defaultValue: false),
            attr("reminderMinutesRaw", .stringAttributeType, defaultValue: ""),
            attr("lastGivenDate", .dateAttributeType, optional: true),
        ] + syncFields()

        log.properties = [
            attr("id", .UUIDAttributeType),
            attr("timestamp", .dateAttributeType),
            attr("notes", .stringAttributeType, defaultValue: ""),
            attr("loggedBy", .stringAttributeType, defaultValue: ""),
            attr("medicationName", .stringAttributeType, defaultValue: ""),
            attr("petId", .UUIDAttributeType, optional: true),
        ] + syncFields()

        // Pet 1—* FeedingEvent (cascade)
        relate(pet, "feedingEvents", to: event, toMany: true, delete: .cascadeDeleteRule,
               inverseName: "pet", inverse: &event, inverseToMany: false, inverseDelete: .nullifyDeleteRule)
        // Pet 1—* Medication (cascade)
        relate(pet, "medications", to: med, toMany: true, delete: .cascadeDeleteRule,
               inverseName: "pet", inverse: &med, inverseToMany: false, inverseDelete: .nullifyDeleteRule)
        // Medication 1—* MedicationLog (nullify)
        relate(med, "logs", to: log, toMany: true, delete: .nullifyDeleteRule,
               inverseName: "medication", inverse: &log, inverseToMany: false, inverseDelete: .nullifyDeleteRule)

        model.entities = [pet, event, med, log]
        return model
    }

    // MARK: helpers

    private static func entity(_ name: String, _ klass: AnyClass) -> NSEntityDescription {
        let e = NSEntityDescription()
        e.name = name
        e.managedObjectClassName = NSStringFromClass(klass)
        return e
    }

    private static func attr(_ name: String,
                             _ type: NSAttributeType,
                             optional: Bool = false,
                             defaultValue: Any? = nil) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = optional
        if let defaultValue { a.defaultValue = defaultValue }
        return a
    }

    private static func syncFields() -> [NSAttributeDescription] {
        [
            attr("ckRecordName", .stringAttributeType, optional: true),
            attr("ckSystemFields", .binaryDataAttributeType, optional: true),
            attr("ckZoneName", .stringAttributeType, optional: true),
            attr("ckDatabaseScope", .integer16AttributeType, defaultValue: 0),
        ]
    }

    /// Wires a to-many relationship and its to-one inverse with delete rules.
    private static func relate(_ from: NSEntityDescription,
                               _ name: String,
                               to dest: NSEntityDescription,
                               toMany: Bool,
                               delete: NSDeleteRule,
                               inverseName: String,
                               inverse: inout NSEntityDescription,
                               inverseToMany: Bool,
                               inverseDelete: NSDeleteRule) {
        let forward = NSRelationshipDescription()
        forward.name = name
        forward.destinationEntity = dest
        forward.deleteRule = delete
        forward.minCount = 0
        forward.maxCount = toMany ? 0 : 1

        let back = NSRelationshipDescription()
        back.name = inverseName
        back.destinationEntity = from
        back.deleteRule = inverseDelete
        back.minCount = 0
        back.maxCount = inverseToMany ? 0 : 1

        forward.inverseRelationship = back
        back.inverseRelationship = forward

        from.properties += [forward]
        dest.properties += [back]
    }
}
