// DidIFeedTheDogWidget/WidgetEntry.swift
import WidgetKit
import Foundation

struct PetSnapshot: Identifiable {
    let id: UUID
    let name: String
    let photoData: Data?
    let lastFedDate: Date?
    let isFeedingOverdue: Bool

    init(id: UUID, name: String, photoData: Data?, lastFedDate: Date?) {
        self.id = id
        self.name = name
        self.photoData = photoData
        self.lastFedDate = lastFedDate
        let threshold: TimeInterval = 12 * 3600
        self.isFeedingOverdue = lastFedDate.map {
            Date().timeIntervalSince($0) >= threshold
        } ?? true
    }
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let pets: [PetSnapshot]   // sorted most-overdue first; empty = no pets added yet

    var mostOverdue: PetSnapshot? { pets.first }
    var fedCount: Int { pets.filter { !$0.isFeedingOverdue }.count }
}
