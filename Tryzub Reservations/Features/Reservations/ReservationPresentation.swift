//
//  ReservationPresentation.swift
//  Tryzub Reservations
//

import Foundation

enum ReservationFormatters {
    static let reservationDateKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let apiTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    static let serverDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static let serverDateMinute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

extension Date {
    static func reservationDateString() -> String {
        Date().reservationDateString()
    }

    func reservationDateString() -> String {
        ReservationFormatters.reservationDateKey.string(from: self)
    }
}

enum ReservationScheduleScope: String, CaseIterable, Identifiable {
    case upcoming = "Upcoming"
    case all = "All"

    var id: String { rawValue }
}

enum ReservationQueueScope: String, CaseIterable, Identifiable {
    case pending = "Pending"
    case needsReview = "Needs Review"

    var id: String { rawValue }
}

enum ReservationOperationalTimingState: Equatable {
    case none
    case normal
    case dueSoon(minutes: Int)
    case dueNow
    case overdue(minutes: Int)

    var insightText: String? {
        switch self {
        case .none, .normal:
            return nil
        case .dueSoon(let minutes):
            return "Due in \(Self.durationText(minutes: minutes))"
        case .dueNow:
            return "Due now"
        case .overdue(let minutes):
            return "Needs attention · \(Self.durationText(minutes: minutes)) past due"
        }
    }

    var sortBucket: Int {
        switch self {
        case .overdue:
            return 0
        case .dueNow:
            return 1
        case .dueSoon:
            return 2
        case .normal, .none:
            return 3
        }
    }

    var isAttention: Bool {
        if case .overdue = self {
            return true
        }
        return false
    }

    var isDueSoon: Bool {
        switch self {
        case .dueSoon, .dueNow:
            return true
        case .none, .normal, .overdue:
            return false
        }
    }

    private static func durationText(minutes: Int) -> String {
        let minutes = max(minutes, 1)
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }
}

struct ReservationDateSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let reservations: [ReservationRecord]
}

extension ReservationRecord {
    var isToday: Bool {
        reservationDate == Date.reservationDateString()
    }

    var isExpectedGuest: Bool {
        switch statusValue {
        case .new, .needsReview, .confirmed, .seated:
            return true
        case .completed, .cancelled, .noShow:
            return false
        }
    }

    var isOpenWork: Bool {
        switch statusValue {
        case .new, .needsReview, .confirmed:
            return true
        case .seated, .completed, .cancelled, .noShow:
            return false
        }
    }

    var isActiveReservationStatus: Bool {
        switch statusValue {
        case .new, .needsReview, .confirmed:
            return true
        case .seated, .completed, .cancelled, .noShow:
            return false
        }
    }

    func operationalTimingState(now: Date = Date()) -> ReservationOperationalTimingState {
        guard !isHidden,
              isActiveReservationStatus,
              let serviceDate = serviceDateTime else {
            return .none
        }

        let secondsUntilReservation = serviceDate.timeIntervalSince(now)
        if secondsUntilReservation < 0 {
            return .overdue(minutes: Int(ceil(abs(secondsUntilReservation) / 60)))
        }

        if secondsUntilReservation <= 15 * 60 {
            return .dueNow
        }

        if secondsUntilReservation <= 2 * 60 * 60 {
            return .dueSoon(minutes: Int(ceil(secondsUntilReservation / 60)))
        }

        return .normal
    }

    var hasTableAssignment: Bool {
        tableName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var tableDisplay: String {
        guard let tableName = tableName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tableName.isEmpty else {
            return "No table"
        }

        return "Table \(tableName)"
    }

    var formattedPhone: String {
        Self.formatPhone(phone)
    }

    var hasGuestNotes: Bool {
        guestNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var hasStaffNotes: Bool {
        staffNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var hasConfirmationEmailRecord: Bool {
        confirmationEmailSentAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var isManualOrCallIn: Bool {
        sourceTypeValue.isManualSource || sourceSubmissionID <= 0 || email.isManualPlaceholderEmail
    }

    var canSoftHideAsWrongEntry: Bool {
        sourceTypeValue.isManualSource || sourceSubmissionID <= 0 || email.isManualPlaceholderEmail
    }

    var sourceDisplayName: String {
        sourceTypeValue.displayName
    }

    var hasUsableConfirmationEmail: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmail.contains("@") && !trimmedEmail.isManualPlaceholderEmail
    }

    /// tel: URL for tap-to-call, or nil when no dialable number exists.
    var callURL: URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard digits.filter(\.isNumber).count >= 7 else { return nil }
        return URL(string: "tel:\(digits)")
    }

    /// mailto: URL for tap-to-email, or nil for missing/placeholder emails.
    var mailtoURL: URL? {
        guard hasUsableConfirmationEmail else { return nil }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: "mailto:\(trimmed)")
    }

    var needsOperationalWarning: Bool {
        statusValue == .needsReview || !hasTableAssignment || partySize >= 7 || hasGuestNotes || hasStaffNotes
    }

    var activeTodayStatusSortBucket: Int {
        switch statusValue {
        case .needsReview:
            return 0
        case .new:
            return 1
        case .confirmed:
            return 2
        case .seated:
            return 3
        case .completed:
            return 4
        case .cancelled:
            return 5
        case .noShow:
            return 6
        }
    }

    var displayDate: String {
        Self.displayDate(from: reservationDate)
    }

    var displayTime: String {
        Self.displayTime(from: reservationTime)
    }

    var submittedAgoText: String? {
        guard statusValue == .new,
              let createdDate = ReservationFormatters.serverDateTime.date(from: createdAt) else {
            return nil
        }

        let elapsed = max(0, Date().timeIntervalSince(createdDate))
        if elapsed < 60 {
            return "Just submitted"
        }

        let minutes = Int(elapsed / 60)
        if minutes < 60 {
            return "\(minutes) min ago"
        }

        let hours = Int(elapsed / 3600)
        if hours < 24 {
            return "\(hours) hr ago"
        }

        let days = Int(elapsed / 86400)
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }

    var shortContactLine: String {
        [formattedPhone, email]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
    }

    func matchesSearch(_ query: String) -> Bool {
        let normalizedQuery = query.lowercased()
        let digitQuery = query.filter(\.isNumber)
        let phoneDigits = phone.filter(\.isNumber)

        if !digitQuery.isEmpty, phoneDigits.contains(digitQuery) {
            return true
        }

        return [
            guestName,
            email,
            phone,
            formattedPhone,
            tableName,
            staffNotes
        ]
        .compactMap { $0?.lowercased() }
        .contains { $0.contains(normalizedQuery) }
    }

    static func sortedChronologically(_ reservations: [ReservationRecord]) -> [ReservationRecord] {
        reservations.sorted {
            if $0.reservationDate == $1.reservationDate {
                if $0.reservationTime == $1.reservationTime {
                    return $0.remoteID < $1.remoteID
                }

                return $0.reservationTime < $1.reservationTime
            }

            return $0.reservationDate < $1.reservationDate
        }
    }

    static func sortedForHostBoard(_ reservations: [ReservationRecord], now: Date = Date()) -> [ReservationRecord] {
        reservations.sorted {
            let lhsTimingBucket = $0.operationalTimingState(now: now).sortBucket
            let rhsTimingBucket = $1.operationalTimingState(now: now).sortBucket

            if lhsTimingBucket == rhsTimingBucket,
               $0.activeTodayStatusSortBucket == $1.activeTodayStatusSortBucket {
                if $0.reservationTime == $1.reservationTime {
                    return $0.remoteID < $1.remoteID
                }

                return $0.reservationTime < $1.reservationTime
            }

            if lhsTimingBucket == rhsTimingBucket {
                return $0.activeTodayStatusSortBucket < $1.activeTodayStatusSortBucket
            }

            return lhsTimingBucket < rhsTimingBucket
        }
    }

    static func sortedNewestFirst(_ reservations: [ReservationRecord]) -> [ReservationRecord] {
        reservations.sorted {
            if $0.reservationDate == $1.reservationDate {
                if $0.reservationTime == $1.reservationTime {
                    return $0.remoteID > $1.remoteID
                }

                return $0.reservationTime > $1.reservationTime
            }

            return $0.reservationDate > $1.reservationDate
        }
    }

    static func dateSections(
        from reservations: [ReservationRecord],
        newestFirst: Bool
    ) -> [ReservationDateSection] {
        let grouped = Dictionary(grouping: reservations, by: \.reservationDate)
        let sortedDates = grouped.keys.sorted(by: newestFirst ? (>) : (<))

        return sortedDates.map { date in
            let rows = newestFirst
                ? sortedNewestFirst(grouped[date] ?? [])
                : sortedChronologically(grouped[date] ?? [])
            let guestCount = rows
                .filter(\.isExpectedGuest)
                .reduce(0) { $0 + $1.partySize }
            let reservationWord = rows.count == 1 ? "reservation" : "reservations"
            let guestWord = guestCount == 1 ? "guest" : "guests"

            return ReservationDateSection(
                id: date,
                title: displayDate(from: date),
                subtitle: "\(rows.count) \(reservationWord) · \(guestCount) \(guestWord)",
                reservations: rows
            )
        }
    }

    private static func displayDate(from value: String) -> String {
        guard let date = ReservationFormatters.reservationDateKey.date(from: value) else {
            return value
        }

        return ReservationFormatters.mediumDate.string(from: date)
    }

    private static func displayTime(from value: String) -> String {
        guard let date = ReservationFormatters.apiTime.date(from: value) else {
            return value
        }

        return ReservationFormatters.shortTime.string(from: date)
    }

    var serviceDateTime: Date? {
        let time = reservationTime.count >= 5 ? String(reservationTime.prefix(5)) : reservationTime
        if let date = ReservationFormatters.serverDateTime.date(from: "\(reservationDate) \(reservationTime)") {
            return date
        }

        return ReservationFormatters.serverDateMinute.date(from: "\(reservationDate) \(time)")
    }

    private static func formatPhone(_ value: String) -> String {
        let digits = value.filter(\.isNumber)

        if digits.count == 10 {
            let area = digits.prefix(3)
            let middle = digits.dropFirst(3).prefix(3)
            let last = digits.suffix(4)
            return "(\(area)) \(middle)-\(last)"
        }

        if digits.count == 11, digits.first == "1" {
            let localDigits = digits.dropFirst()
            let area = localDigits.prefix(3)
            let middle = localDigits.dropFirst(3).prefix(3)
            let last = localDigits.suffix(4)
            return "+1 (\(area)) \(middle)-\(last)"
        }

        return value
    }

    static func sortedByCreatedAtAscending(_ reservations: [ReservationRecord]) -> [ReservationRecord] {
        reservations.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.remoteID < $1.remoteID
            }

            return $0.createdAt < $1.createdAt
        }
    }
}

extension String {
    var isManualPlaceholderEmail: Bool {
        let value = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return true }

        return value.hasPrefix("callin+manual-") && value.hasSuffix("@tryzubchicago.com")
            || value.hasSuffix("@manualreservation.com")
    }
}
