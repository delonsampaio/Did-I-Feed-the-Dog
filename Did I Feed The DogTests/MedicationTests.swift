import XCTest
import SwiftData
@testable import Did_I_Feed_The_Dog

@MainActor
final class MedicationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Pet.self, FeedingEvent.self, Medication.self, MedicationLog.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - Helpers

    private func makePetWithMedAndLogs(logCount: Int = 3) -> (Pet, Medication, [MedicationLog]) {
        let pet = Pet(name: "Buddy")
        context.insert(pet)

        let med = Medication(name: "Aspirin", dose: "1 tablet")
        med.pet = pet
        context.insert(med)

        var logs: [MedicationLog] = []
        for i in 0..<logCount {
            let log = MedicationLog(
                timestamp: Date(timeIntervalSinceNow: Double(-i * 3600)),
                notes: "dose \(i + 1)",
                loggedBy: "Tester",
                medication: med
            )
            context.insert(log)
            logs.append(log)
        }
        try? context.save()
        return (pet, med, logs)
    }

    // MARK: - petId denormalization

    func testMedicationLogStoresPetId() throws {
        let (pet, _, logs) = makePetWithMedAndLogs()
        for log in logs {
            XCTAssertEqual(log.petId, pet.id, "petId should be set at log creation time")
        }
    }

    // MARK: - Deletion behaviour

    func testLogsNotDeletedWhenMedicationDeleted() throws {
        let (_, med, _) = makePetWithMedAndLogs(logCount: 3)

        // Simulate the fix: explicitly nullify before delete
        for log in med.logs ?? [] { log.medication = nil }
        context.delete(med)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<MedicationLog>())
        XCTAssertEqual(remaining.count, 3, "all logs must survive medication deletion")
    }

    func testLogsQueryableByPetIdAfterMedicationDeleted() throws {
        let (pet, med, _) = makePetWithMedAndLogs(logCount: 3)
        let petId = pet.id

        for log in med.logs ?? [] { log.medication = nil }
        context.delete(med)
        try context.save()

        let all = try context.fetch(FetchDescriptor<MedicationLog>())
        let visible = all.filter { $0.petId == petId }
        XCTAssertEqual(visible.count, 3, "all logs must be findable by petId after medication deleted")
    }

    func testLogsForOtherPetUnaffected() throws {
        let (_, med1, _) = makePetWithMedAndLogs(logCount: 2)

        let pet2 = Pet(name: "Luna")
        context.insert(pet2)
        let med2 = Medication(name: "Vitamins")
        med2.pet = pet2
        context.insert(med2)
        let log2 = MedicationLog(timestamp: .now, notes: "", loggedBy: "Tester", medication: med2)
        context.insert(log2)
        try? context.save()

        // Delete only med1
        for log in med1.logs ?? [] { log.medication = nil }
        context.delete(med1)
        try context.save()

        let pet2Logs = try context.fetch(FetchDescriptor<MedicationLog>())
            .filter { $0.petId == pet2.id }
        XCTAssertEqual(pet2Logs.count, 1, "logs for other pet must be unaffected")
    }

    func testMedicationNameDenormalizedOnLog() throws {
        let (_, med, logs) = makePetWithMedAndLogs()
        let expectedName = med.name

        for log in med.logs ?? [] { log.medication = nil }
        context.delete(med)
        try context.save()

        for log in logs {
            XCTAssertEqual(log.medicationName, expectedName,
                           "medicationName should survive medication deletion")
        }
    }
}
