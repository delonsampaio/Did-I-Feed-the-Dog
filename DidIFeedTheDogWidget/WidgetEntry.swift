// DidIFeedTheDogWidget/WidgetEntry.swift
import WidgetKit
import Foundation

struct PetSnapshot: Identifiable {
    let id: UUID
    let name: String
    let photoData: Data?
    let lastFedDate: Date?
    let isFeedingOverdue: Bool
    let isFasting: Bool

    init(data: PetWidgetData, at date: Date = .now) {
        self.id = data.id
        self.name = data.name
        self.photoData = data.photoData
        self.lastFedDate = data.lastFedDate
        self.isFasting = data.isFasting ?? false
        
        let isFasting = data.isFasting ?? false
        let scheduleTimes = data.scheduleTimes ?? []
        let thresholdHours = data.thresholdHours ?? 12

        if isFasting {
            self.isFeedingOverdue = false
        } else if !scheduleTimes.isEmpty {
            let cal = Calendar.current
            let now = cal.dateComponents([.hour, .minute], from: date)
            let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
            
            if let lastPassedMinutes = scheduleTimes.filter({ $0 <= currentMinutes }).last {
                var components = cal.dateComponents([.year, .month, .day], from: date)
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
                date.timeIntervalSince($0) >= Double(thresholdHours) * 3600
            } ?? true // Note: Pet.swift returns true if no lastFedDate and no schedule.
        }
    }

    static func nextOverdueDate(for data: PetWidgetData, after date: Date = .now) -> Date? {
        let isFasting = data.isFasting ?? false
        let scheduleTimes = data.scheduleTimes ?? []
        let thresholdHours = data.thresholdHours ?? 12

        if isFasting { return nil }

        if !scheduleTimes.isEmpty {
            let cal = Calendar.current
            var components = cal.dateComponents([.year, .month, .day], from: date)
            components.second = 0
            
            var potentialDates: [Date] = []
            for minutes in scheduleTimes {
                components.hour = minutes / 60
                components.minute = minutes % 60
                if let d = cal.date(from: components) {
                    potentialDates.append(d)
                    if let dNext = cal.date(byAdding: .day, value: 1, to: d) {
                        potentialDates.append(dNext)
                    }
                }
            }
            
            return potentialDates.filter { $0 > date }.min()
        } else {
            if let last = data.lastFedDate {
                let overdueDate = last.addingTimeInterval(Double(thresholdHours) * 3600)
                return overdueDate > date ? overdueDate : nil
            }
            return nil
        }
    }
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let pets: [PetSnapshot]   // sorted most-overdue first; empty = no pets added yet
    let isPro: Bool

    var mostOverdue: PetSnapshot? { pets.first }
    var fedCount: Int { pets.filter { !$0.isFeedingOverdue }.count }
}
