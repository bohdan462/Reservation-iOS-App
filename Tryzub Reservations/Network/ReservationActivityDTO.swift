//
//  ReservationActivityDTO.swift
//  Tryzub Reservations
//
//  Backend-owned reservation activity history (schema 1.7.0).
//

import Foundation

// MARK: - Mutation sidecar (optional on write responses)

struct MutationActivityResultDTO: Codable, Equatable {
    let created: Bool?
    let eventTypes: [String]?
}

// MARK: - Per-reservation activity

struct ReservationActivityDTO: Decodable, Identifiable, Equatable {
    let id: Int
    let reservationId: Int
    let eventType: String
    let summary: String
    let actorName: String?
    let actorRole: String?
    let source: String
    let createdAt: String
    let createdAtGmt: String
    let metadata: [String: JSONValue]?
}

struct ReservationActivityResponseDTO: Decodable, Equatable {
    let success: Bool
    let reservationId: Int
    let page: Int
    let perPage: Int
    let total: Int
    let totalPages: Int
    let data: [ReservationActivityDTO]
}

// MARK: - Service-day feed

struct ReservationActivityRangeDTO: Decodable, Equatable {
    let from: String
    let to: String
}

struct ReservationActivityFeedSummaryDTO: Decodable, Equatable {
    let created: Int?
    let cancelled: Int?
    let tableAssigned: Int?
    let guestNoteUpdated: Int?
    let staffNoteUpdated: Int?
    let statusChanged: Int?
    let confirmed: Int?
    let seated: Int?
    let completed: Int?
    let noShow: Int?
    let imported: Int?
    let updated: Int?
    let hidden: Int?
    let restored: Int?
    let hardDeleted: Int?
    let guestCancelled: Int?
    let emailDraftCreated: Int?
    let manualEmailSent: Int?

    /// Flat key/value pairs for summary chips (event type → count).
    var chipCounts: [(eventType: String, count: Int)] {
        let pairs: [(String, Int?)] = [
            ("created", created),
            ("cancelled", cancelled),
            ("table_assigned", tableAssigned),
            ("guest_note_updated", guestNoteUpdated),
            ("staff_note_updated", staffNoteUpdated),
            ("status_changed", statusChanged),
            ("confirmed", confirmed),
            ("seated", seated),
            ("completed", completed),
            ("no_show", noShow),
            ("imported", imported),
            ("updated", updated),
            ("guest_cancelled", guestCancelled),
            ("manual_email_sent", manualEmailSent),
        ]
        return pairs.compactMap { key, value in
            guard let value, value > 0 else { return nil }
            return (key, value)
        }
    }
}

struct ReservationActivityFeedResponseDTO: Decodable, Equatable {
    let success: Bool
    let range: ReservationActivityRangeDTO
    let page: Int
    let perPage: Int
    let total: Int
    let totalPages: Int
    let summary: ReservationActivityFeedSummaryDTO?
    let data: [ReservationActivityDTO]
}
