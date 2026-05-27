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

    var rowSourceLabel: String? {
        sourceTypeValue.isManualSource ? sourceTypeValue.displayName : nil
    }

    var rowSourceSystemImage: String {
        switch sourceTypeValue {
        case .manualCallIn:
            return "phone.badge.plus"
        case .manualWalkIn:
            return "figure.walk"
        case .knownGuestManual:
            return "person.text.rectangle"
        case .importRepair:
            return "wrench.and.screwdriver"
        case .form, .unknown:
            return "globe"
        }
    }

    var hasUsableConfirmationEmail: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmail.contains("@") && !trimmedEmail.isManualPlaceholderEmail
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

        return nil
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

    static func sortedForHostBoard(_ reservations: [ReservationRecord]) -> [ReservationRecord] {
        reservations.sorted {
            if $0.activeTodayStatusSortBucket == $1.activeTodayStatusSortBucket {
                if $0.reservationTime == $1.reservationTime {
                    return $0.remoteID < $1.remoteID
                }

                return $0.reservationTime < $1.reservationTime
            }

            return $0.activeTodayStatusSortBucket < $1.activeTodayStatusSortBucket
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
