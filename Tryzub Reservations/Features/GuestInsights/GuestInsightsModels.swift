//
//  GuestInsightsModels.swift
//  Tryzub Reservations
//

import Foundation

enum GuestMatchConfidence: String, CaseIterable, Identifiable {
    case exact
    case strong
    case possible
    case weak

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .exact:
            return "Exact"
        case .strong:
            return "Strong"
        case .possible:
            return "Possible"
        case .weak:
            return "Weak"
        }
    }
}

enum GuestInsightNoteType: String, Identifiable {
    case guest
    case staff

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .guest:
            return "Guest"
        case .staff:
            return "Staff"
        }
    }
}

enum GuestBookingSource: String {
    case online
    case manual

    var displayName: String {
        switch self {
        case .online:
            return "Online"
        case .manual:
            return "Manual / Call-in"
        }
    }
}

enum GuestRegularityLevel: Int, CaseIterable, Identifiable {
    case firstTime
    case seenBefore
    case becomingRegular
    case regular
    case frequentRegular

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .firstTime:
            return "First time"
        case .seenBefore:
            return "Seen before"
        case .becomingRegular:
            return "Becoming regular"
        case .regular:
            return "Regular"
        case .frequentRegular:
            return "Frequent regular"
        }
    }

    var rank: Int {
        rawValue
    }

    static func level(for reservationCount: Int) -> GuestRegularityLevel {
        switch reservationCount {
        case ..<2:
            return .firstTime
        case 2:
            return .seenBefore
        case 3...4:
            return .becomingRegular
        case 5...9:
            return .regular
        default:
            return .frequentRegular
        }
    }
}

struct GuestInsightReport {
    let selectedReservationID: Int
    let displayName: String
    let primaryPhone: String?
    let primaryEmail: String?
    let isLikelyManualGuest: Bool
    let regularityLevel: GuestRegularityLevel
    let hospitalitySnapshot: GuestHospitalitySnapshot
    let bookingBehavior: GuestBookingBehavior
    let collapsedDuplicateReservationCount: Int

    let summary: GuestInsightSummary
    let matchedReservations: [GuestMatchedReservation]
    let possibleMatches: [GuestMatchedReservation]

    let bookingHistory: [GuestBookingHistoryItem]
    let noteHistory: [GuestNoteHistoryItem]
    let staffMentionHistory: [GuestNoteHistoryItem]

    let preferredTimes: [GuestTimePreference]
    let preferredWeekdays: [GuestWeekdayPreference]
    let partySizeStats: GuestPartySizeStats
    let statusStats: GuestStatusStats

    let warnings: [GuestInsightWarning]

    var isRepeatGuest: Bool {
        summary.totalMatchedReservations > 1
    }

    var hasReliableContactIdentity: Bool {
        primaryPhone != nil || primaryEmail != nil
    }
}

struct GuestInsightSummary {
    let totalMatchedReservations: Int
    let upcomingReservationsCount: Int
    let pastReservationsCount: Int
    let cancelledNoShowCount: Int
    let firstSeenDate: String?
    let lastBookedDate: String?
    let mostCommonReservationTime: String?
    let mostCommonWeekday: String?
    let mostCommonPartySize: Int?
    let lastStaffNote: GuestNoteHistoryItem?
    let lastGuestNote: GuestNoteHistoryItem?
}

struct GuestHospitalitySnapshot {
    let visitsLast90Days: Int
    let visitsLast12Months: Int
    let lastUpcomingReservationDate: String?
    let averagePartySize: Double?
    let largestPartySize: Int?
    let hasRealEmail: Bool
    let hasPhone: Bool
    let hasStaffNotes: Bool
    let hasGuestNotes: Bool
    let noteCount: Int
    let isRecent: Bool
    let isNotRecent: Bool
}

struct GuestBookingBehavior {
    let mostCommonTime: String?
    let mostCommonWeekday: String?
    let mostCommonPartySize: Int?
    let commonTable: String?
    let onlineCount: Int
    let manualCount: Int
    let upcomingActiveCount: Int
    let pastServedCount: Int
    let cancelledNoShowCount: Int
}

struct GuestMatchedReservation: Identifiable {
    let reservationID: Int
    let date: String
    let time: String
    let displayDate: String
    let displayTime: String
    let guestName: String
    let partySize: Int
    let status: ReservationStatus
    let table: String?
    let confidence: GuestMatchConfidence
    let matchReasons: [String]

    var id: Int { reservationID }
}

struct GuestBookingHistoryItem: Identifiable {
    let reservationID: Int
    let date: String
    let time: String
    let displayDate: String
    let displayTime: String
    let partySize: Int
    let status: ReservationStatus
    let table: String?
    let source: GuestBookingSource
    let hasGuestNotes: Bool
    let hasStaffNotes: Bool

    var id: Int { reservationID }

    var hasNotes: Bool {
        hasGuestNotes || hasStaffNotes
    }
}

struct GuestNoteHistoryItem: Identifiable {
    let reservationID: Int
    let date: String
    let time: String
    let displayDate: String
    let displayTime: String
    let noteType: GuestInsightNoteType
    let text: String
    let status: ReservationStatus

    var id: String {
        "\(reservationID)-\(noteType.rawValue)"
    }
}

struct GuestTimePreference: Identifiable {
    let bucket: String
    let count: Int
    let percentage: Double

    var id: String { bucket }
}

struct GuestWeekdayPreference: Identifiable {
    let weekday: String
    let count: Int

    var id: String { weekday }
}

struct GuestPartySizeStats {
    let min: Int?
    let max: Int?
    let average: Double?
    let mostCommon: Int?
    let largePartyCount: Int
}

struct GuestStatusStats {
    let new: Int
    let needsReview: Int
    let confirmed: Int
    let seated: Int
    let completed: Int
    let cancelled: Int
    let noShow: Int

    var cancelledOrNoShow: Int {
        cancelled + noShow
    }

    func count(for status: ReservationStatus) -> Int {
        switch status {
        case .new:
            return new
        case .needsReview:
            return needsReview
        case .confirmed:
            return confirmed
        case .seated:
            return seated
        case .completed:
            return completed
        case .cancelled:
            return cancelled
        case .noShow:
            return noShow
        }
    }
}

struct GuestInsightWarning: Identifiable {
    let id: String
    let title: String
    let message: String
    let systemImage: String
}

enum RegularGuestFilter: String, CaseIterable, Identifiable {
    case allSeenBefore
    case regulars
    case becomingRegular
    case notesFound
    case staffNotesFound
    case callIn
    case possibleMatches
    case cancellationOrNoShow
    case upcoming

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allSeenBefore:
            return "Seen before"
        case .regulars:
            return "Regulars"
        case .becomingRegular:
            return "Becoming"
        case .notesFound:
            return "Notes"
        case .staffNotesFound:
            return "Staff notes"
        case .callIn:
            return "Call-in"
        case .possibleMatches:
            return "Possible matches"
        case .cancellationOrNoShow:
            return "Cancelled/no-show"
        case .upcoming:
            return "Upcoming"
        }
    }
}

enum RegularGuestSort: String, CaseIterable, Identifiable {
    case mostReservations
    case recentlyBooked
    case firstSeen
    case mostNotes
    case upcomingFirst
    case name

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mostReservations:
            return "Most reservations"
        case .recentlyBooked:
            return "Recently booked"
        case .firstSeen:
            return "First seen"
        case .mostNotes:
            return "Most notes"
        case .upcomingFirst:
            return "Upcoming first"
        case .name:
            return "Name"
        }
    }
}

struct RegularGuestSummary: Identifiable {
    let id: String
    let displayName: String
    let primaryPhone: String?
    let primaryEmail: String?
    let regularityLevel: GuestRegularityLevel
    let totalReservations: Int
    let firstSeenDate: String?
    let lastBookedDate: String?
    let firstSeenSortKey: String?
    let lastBookedSortKey: String?
    let upcomingCount: Int
    let cancelledNoShowCount: Int
    let mostCommonTime: String?
    let mostCommonPartySize: Int?
    let hasStaffNotes: Bool
    let hasGuestNotes: Bool
    let isLikelyManualGuest: Bool
    let possibleMatchCount: Int
    let matchedReservationIDs: [Int]
    let representativeReservationID: Int
    let collapsedDuplicateReservationCount: Int
    let noteCount: Int
    let visitsLast90Days: Int
    let visitsLast12Months: Int
    let searchText: String
}
