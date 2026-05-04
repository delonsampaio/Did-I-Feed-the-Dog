// DidIFeedTheDogWidget/WidgetEntry.swift
import WidgetKit
import Foundation

struct PetSnapshot: Identifiable {
    let id: UUID
    let name: String
    let photoData: Data?
    let lastFedDate: Date?
    let isFeedingOverdue: Bool

    init(data: PetWidgetData) {
        self.id = data.id
        self.name = data.name
        self.photoData = data.photoData
        self.lastFedDate = data.lastFedDate
        
        let isFasting = data.isFasting ?? false
        let scheduleTimes = data.scheduleTimes ?? []
        let thresholdHours = data.thresholdHours ?? 12

        if isFasting {
            self.isFeedingOverdue = false
        } else if !scheduleTimes.isEmpty {
            let cal = Calendar.current
            let now = cal.dateComponents([.hour, .minute], from: .now)
            let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
            
            if let lastPassedMinutes = scheduleTimes.filter({ $0 <= currentMinutes }).last {
                var components = cal.dateComponents([.year, .month, .day], from: .now)
                components.hour = lastPassedMinutes / 60
                components.minute = lastPassedMinutes % 60
                components.second = 0
                if let scheduledDate = cal.date(from: components) {
                    self.isFeedingOverdue = data.lastFedDate.map { $0 < scheduledDate } ?? true
                } else {
                    self.isFeedingOverdue = false
                }
            } else {
                self.isFeedingOverdue = false
            }
        } else {
            self.isFeedingOverdue = data.lastFedDate.map {
                Date().timeIntervalSince($0) >= Double(thresholdHours) * 3600
            } ?? false // Note: Pet.swift returns false if no lastFedDate and no schedule.
        }
    }
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let pets: [PetSnapshot]   // sorted most-overdue first; empty = no pets added yet

    var mostOverdue: PetSnapshot? { pets.first }
    var fedCount: Int { pets.filter { !$0.isFeedingOverdue }.count }
}
