//
//  ReservationRecord.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import Foundation
import SwiftData

@Model
class ReservationRecord: Identifiable {
    var id: UUID
    var remoteID: Int
    var sourceSubmissionID: Int = 0
    var guestName: String
    var email: String
    var phone: String
    var reservationDate: String
    var reservationTime: String
    var partySize: Int
    var status: String
    var guestNotes: String?
    var tableName: String?
    var staffNotes: String?
    var createdAt: String
    var apiUpdatedAt: String?
    var confirmedAt: String?
    var confirmationEmailSentAt: String?
    var reminderEmailSentAt: String?
    var supersededById: Int?
    var sourceType: String?
    var createdByUserId: Int?
    var createdByDevice: String?
    var isHidden: Bool = false
    var hiddenAt: String?
    var hiddenReason: String?
    var hiddenByUserId: Int?
    var lastSyncedAt: Date
    var updatedAt: Date?
    
    init (from dto: ReservationDTO) {
        self.id = UUID()
        self.remoteID = dto.id
        self.sourceSubmissionID = dto.sourceSubmissionId ?? 0
        self.guestName = dto.guestName
        self.email = dto.email
        self.phone = dto.phone
        self.reservationDate = dto.reservationDate
        self.reservationTime = dto.reservationTime
        self.partySize = dto.partySize
        self.status = dto.status.rawValue
        self.guestNotes = dto.guestNotes?.nilIfEmpty
        self.tableName = dto.tableName?.nilIfEmpty
        self.staffNotes = dto.staffNotes?.nilIfEmpty
        self.createdAt = dto.createdAt
        self.apiUpdatedAt = dto.updatedAt
        self.confirmedAt = dto.confirmedAt
        self.confirmationEmailSentAt = dto.confirmationEmailSentAt
        self.reminderEmailSentAt = dto.reminderEmailSentAt
        self.supersededById = dto.supersededById
        self.sourceType = dto.sourceType?.rawValue
        self.createdByUserId = dto.createdByUserId
        self.createdByDevice = dto.createdByDevice
        self.isHidden = dto.isHidden ?? false
        self.hiddenAt = dto.hiddenAt
        self.hiddenReason = dto.hiddenReason?.nilIfEmpty
        self.hiddenByUserId = dto.hiddenByUserId
        self.lastSyncedAt = Date()
        self.updatedAt = nil
    }

    #if DEBUG
    /// In-memory fixture for deterministic proof harnesses (not inserted into a context).
    init(
        fixtureRemoteID: Int,
        reservationDate: String,
        reservationTime: String,
        partySize: Int,
        status: ReservationStatus,
        tableName: String? = nil
    ) {
        self.id = UUID()
        self.remoteID = fixtureRemoteID
        self.sourceSubmissionID = 0
        self.guestName = "Fixture"
        self.email = ""
        self.phone = ""
        self.reservationDate = reservationDate
        self.reservationTime = reservationTime
        self.partySize = partySize
        self.status = status.rawValue
        self.guestNotes = nil
        self.tableName = tableName
        self.staffNotes = nil
        self.createdAt = ""
        self.apiUpdatedAt = nil
        self.confirmedAt = nil
        self.confirmationEmailSentAt = nil
        self.reminderEmailSentAt = nil
        self.supersededById = nil
        self.sourceType = nil
        self.createdByUserId = nil
        self.createdByDevice = nil
        self.isHidden = false
        self.hiddenAt = nil
        self.hiddenReason = nil
        self.hiddenByUserId = nil
        self.lastSyncedAt = Date()
        self.updatedAt = nil
    }
    #endif

    /// Canonical row version for optimistic mutation guards (sent as expected_updated_at).
    /// Matches backend rule: row_version = updated_at ?? created_at.
    /// `apiUpdatedAt` is the server `updated_at`; `updatedAt` is a local SwiftData stamp
    /// and must not be used as a server version.
    var rowVersion: String {
        apiUpdatedAt ?? createdAt
    }

    /// True when cached row already matches the server payload (skip rewrite).
    func isContentEquivalent(to dto: ReservationDTO) -> Bool {
        remoteID == dto.id
            && sourceSubmissionID == (dto.sourceSubmissionId ?? 0)
            && guestName == dto.guestName
            && email == dto.email
            && phone == dto.phone
            && reservationDate == dto.reservationDate
            && reservationTime == dto.reservationTime
            && partySize == dto.partySize
            && status == dto.status.rawValue
            && guestNotes == dto.guestNotes?.nilIfEmpty
            && tableName == dto.tableName?.nilIfEmpty
            && staffNotes == dto.staffNotes?.nilIfEmpty
            && apiUpdatedAt == dto.updatedAt
            && confirmedAt == dto.confirmedAt
            && isHidden == (dto.isHidden ?? false)
    }

    func update(from dto: ReservationDTO) {
        remoteID = dto.id
        sourceSubmissionID = dto.sourceSubmissionId ?? 0
        guestName = dto.guestName
        email = dto.email
        phone = dto.phone
        reservationDate = dto.reservationDate
        reservationTime = dto.reservationTime
        partySize = dto.partySize
        status = dto.status.rawValue
        guestNotes = dto.guestNotes?.nilIfEmpty
        tableName = dto.tableName?.nilIfEmpty
        staffNotes = dto.staffNotes?.nilIfEmpty
        createdAt = dto.createdAt
        apiUpdatedAt = dto.updatedAt
        confirmedAt = dto.confirmedAt
        confirmationEmailSentAt = dto.confirmationEmailSentAt
        reminderEmailSentAt = dto.reminderEmailSentAt
        supersededById = dto.supersededById
        sourceType = dto.sourceType?.rawValue
        createdByUserId = dto.createdByUserId
        createdByDevice = dto.createdByDevice
        isHidden = dto.isHidden ?? false
        hiddenAt = dto.hiddenAt
        hiddenReason = dto.hiddenReason?.nilIfEmpty
        hiddenByUserId = dto.hiddenByUserId
        lastSyncedAt = Date()
        updatedAt = Date()
    }

    var statusValue: ReservationStatus {
        ReservationStatus(rawValue: status) ?? .new
    }

    var sourceTypeValue: ReservationSourceType {
        guard let sourceType else {
            return sourceSubmissionID > 0 ? .form : .manualCallIn
        }
        return ReservationSourceType(rawValue: sourceType) ?? .unknown
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
