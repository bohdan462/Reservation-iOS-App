//
//  GuestProfileCacheRecord.swift
//  Tryzub Reservations
//

import Foundation
import SwiftData

@Model
final class GuestProfileCacheRecord {
    @Attribute(.unique) var guestKey: String
    var displayName: String
    var normalizedPhone: String?
    var email: String?
    var primaryPhone: String?
    var cleanVisitCount: Int
    var totalReservations: Int
    var upcomingCount: Int
    var firstSeenDate: String?
    var lastSeenDate: String?
    var lastBookedAt: String?
    var nextReservationDate: String?
    var nextReservationTime: String?
    var summaryLine: String?
    var topLabelTitles: String?
    var hasDietaryNote: Bool
    var isRegularGuest: Bool
    var latestGuestNotePreview: String?
    var latestStaffNotePreview: String?
    var backendUpdatedAt: String?
    var fetchedAt: Date
    var hasDetailPayload: Bool
    var labelsJSON: String?
    var listProfileJSON: String?
    var detailProfileJSON: String?
    var bookingHistoryJSON: String?
    var notesHistoryJSON: String?

    init(
        guestKey: String,
        displayName: String,
        normalizedPhone: String? = nil,
        email: String? = nil,
        primaryPhone: String? = nil,
        cleanVisitCount: Int = 0,
        totalReservations: Int = 0,
        upcomingCount: Int = 0,
        firstSeenDate: String? = nil,
        lastSeenDate: String? = nil,
        lastBookedAt: String? = nil,
        nextReservationDate: String? = nil,
        nextReservationTime: String? = nil,
        summaryLine: String? = nil,
        topLabelTitles: String? = nil,
        hasDietaryNote: Bool = false,
        isRegularGuest: Bool = false,
        latestGuestNotePreview: String? = nil,
        latestStaffNotePreview: String? = nil,
        backendUpdatedAt: String? = nil,
        fetchedAt: Date = Date(),
        hasDetailPayload: Bool = false,
        labelsJSON: String? = nil,
        listProfileJSON: String? = nil,
        detailProfileJSON: String? = nil,
        bookingHistoryJSON: String? = nil,
        notesHistoryJSON: String? = nil
    ) {
        self.guestKey = guestKey
        self.displayName = displayName
        self.normalizedPhone = normalizedPhone
        self.email = email
        self.primaryPhone = primaryPhone
        self.cleanVisitCount = cleanVisitCount
        self.totalReservations = totalReservations
        self.upcomingCount = upcomingCount
        self.firstSeenDate = firstSeenDate
        self.lastSeenDate = lastSeenDate
        self.lastBookedAt = lastBookedAt
        self.nextReservationDate = nextReservationDate
        self.nextReservationTime = nextReservationTime
        self.summaryLine = summaryLine
        self.topLabelTitles = topLabelTitles
        self.hasDietaryNote = hasDietaryNote
        self.isRegularGuest = isRegularGuest
        self.latestGuestNotePreview = latestGuestNotePreview
        self.latestStaffNotePreview = latestStaffNotePreview
        self.backendUpdatedAt = backendUpdatedAt
        self.fetchedAt = fetchedAt
        self.hasDetailPayload = hasDetailPayload
        self.labelsJSON = labelsJSON
        self.listProfileJSON = listProfileJSON
        self.detailProfileJSON = detailProfileJSON
        self.bookingHistoryJSON = bookingHistoryJSON
        self.notesHistoryJSON = notesHistoryJSON
    }

    func matchesPhoneDigits(_ query: String) -> Bool {
        let digits = Self.normalizedPhoneDigits(query)
        guard digits.count >= 4, let normalizedPhone else { return false }
        return normalizedPhone == digits
            || normalizedPhone.hasSuffix(digits)
            || normalizedPhone.contains(digits)
    }

    var displaySubtitle: String {
        if let nextReservationDate {
            let time = nextReservationTime.map { " at \($0)" } ?? ""
            return "Next \(nextReservationDate)\(time)"
        }
        if isLikelyRegular {
            return "\(cleanVisitCount) clean visits"
        }
        if totalReservations > 0 {
            return "\(totalReservations) reservations"
        }
        if let email {
            return email
        }
        if let primaryPhone {
            return primaryPhone
        }
        return "Guest profile"
    }

    var isLikelyRegular: Bool {
        isRegularGuest || cleanVisitCount >= 3 || totalReservations >= 5
    }

    var latestNotePreview: String? {
        latestGuestNotePreview ?? latestStaffNotePreview
    }

    private static func normalizedPhoneDigits(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        if digits.count == 11, digits.first == "1" {
            return String(digits.dropFirst())
        }
        return digits
    }
}
