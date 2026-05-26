//
//  GuestIdentityResolver.swift
//  Tryzub Reservations
//

import Foundation

struct GuestResolvedIdentity {
    let record: ReservationRecord
    let normalizedName: String
    let fullPhoneDigits: String?
    let phoneLast4: String?
    let usefulEmail: String?
    let emailLocalPart: String?
    let emailDomain: String?
    let isPlaceholderEmail: Bool

    var hasReliableContact: Bool {
        fullPhoneDigits != nil || usefulEmail != nil
    }
}

struct GuestIdentityMatch {
    let record: ReservationRecord
    let confidence: GuestMatchConfidence
    let reasons: [String]

    var isPrimaryHistoryMatch: Bool {
        confidence == .exact || confidence == .strong
    }
}

struct GuestIdentityResolver {
    func identity(for record: ReservationRecord) -> GuestResolvedIdentity {
        let usefulEmail = normalizedUsefulEmail(record.email)
        let parts = usefulEmail.map(emailParts)

        return GuestResolvedIdentity(
            record: record,
            normalizedName: normalizeName(record.guestName),
            fullPhoneDigits: fullPhoneDigits(record.phone),
            phoneLast4: phoneLast4(record.phone),
            usefulEmail: usefulEmail,
            emailLocalPart: parts?.local,
            emailDomain: parts?.domain,
            isPlaceholderEmail: isPlaceholderEmail(record.email)
        )
    }

    func match(
        _ record: ReservationRecord,
        against selected: GuestResolvedIdentity,
        selectedID: Int?
    ) -> GuestIdentityMatch? {
        if record.remoteID == selectedID {
            return GuestIdentityMatch(
                record: record,
                confidence: .exact,
                reasons: ["Current reservation"]
            )
        }

        let candidate = identity(for: record)
        var exactReasons: [String] = []

        if let selectedPhone = selected.fullPhoneDigits,
           let candidatePhone = candidate.fullPhoneDigits,
           selectedPhone == candidatePhone {
            exactReasons.append("Same phone")
        }

        if let selectedEmail = selected.usefulEmail,
           let candidateEmail = candidate.usefulEmail,
           selectedEmail == candidateEmail {
            exactReasons.append("Same email")
        }

        if !exactReasons.isEmpty {
            return GuestIdentityMatch(
                record: record,
                confidence: .exact,
                reasons: exactReasons
            )
        }

        let sameName = !selected.normalizedName.isEmpty
            && selected.normalizedName == candidate.normalizedName

        if sameName,
           let selectedLast4 = selected.phoneLast4,
           let candidateLast4 = candidate.phoneLast4,
           selectedLast4 == candidateLast4 {
            return GuestIdentityMatch(
                record: record,
                confidence: .strong,
                reasons: ["Same name and phone ending"]
            )
        }

        if sameName,
           emailLocalPartsLookSimilar(selected.emailLocalPart, candidate.emailLocalPart) {
            return GuestIdentityMatch(
                record: record,
                confidence: .strong,
                reasons: ["Same name and similar email"]
            )
        }

        if sameName,
           let selectedDomain = selected.emailDomain,
           let candidateDomain = candidate.emailDomain,
           selectedDomain == candidateDomain,
           !isCommonEmailProviderDomain(selectedDomain) {
            return GuestIdentityMatch(
                record: record,
                confidence: .strong,
                reasons: ["Same name and private email domain"]
            )
        }

        if sameName, reservationPatternLooksSimilar(selected.record, record) {
            return GuestIdentityMatch(
                record: record,
                confidence: .possible,
                reasons: ["Same name and similar booking pattern"]
            )
        }

        if namesLookSimilar(selected.normalizedName, candidate.normalizedName) {
            return GuestIdentityMatch(
                record: record,
                confidence: .weak,
                reasons: ["Similar name"]
            )
        }

        if let selectedLast4 = selected.phoneLast4,
           let candidateLast4 = candidate.phoneLast4,
           selectedLast4 == candidateLast4 {
            return GuestIdentityMatch(
                record: record,
                confidence: .weak,
                reasons: ["Same phone ending only"]
            )
        }

        return nil
    }

    func isLikelyManualCallIn(_ record: ReservationRecord) -> Bool {
        record.sourceSubmissionID <= 0 || isPlaceholderEmail(record.email)
    }

    func normalizedUsefulEmail(_ email: String) -> String? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@"), !isPlaceholderEmail(normalized) else {
            return nil
        }

        return normalized
    }

    func isPlaceholderEmail(_ email: String) -> Bool {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("callin+manual-")
            && normalized.hasSuffix("@tryzubchicago.com")
    }

    func isCommonEmailProviderDomain(_ domain: String) -> Bool {
        Self.commonEmailProviderDomains.contains(domain.lowercased())
    }

    func normalizeName(_ name: String) -> String {
        let lowercase = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = lowercase.map { character -> Character in
            if character.isLetter || character.isNumber || character.isWhitespace {
                return character
            }
            return " "
        }

        return String(allowed)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    func fullPhoneDigits(_ phone: String) -> String? {
        let digits = phone.filter(\.isNumber)
        return digits.count >= 7 ? digits : nil
    }

    func phoneLast4(_ phone: String) -> String? {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 4 else { return nil }
        return String(digits.suffix(4))
    }

    func hourBucket(from time: String) -> String? {
        guard let hour = hour(from: time) else { return nil }
        let adjustedHour = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return "\(adjustedHour) \(suffix)"
    }

    func hour(from time: String) -> Int? {
        guard let hourString = time.split(separator: ":").first,
              let hour = Int(hourString),
              (0...23).contains(hour) else {
            return nil
        }
        return hour
    }

    func dateTime(from record: ReservationRecord) -> Date? {
        let combined = "\(record.reservationDate) \(record.reservationTime)"
        return Self.dateTimeParser.date(from: combined)
    }

    func reservationDate(from record: ReservationRecord) -> Date? {
        Self.dateParser.date(from: record.reservationDate)
    }

    func weekdayName(from record: ReservationRecord) -> String? {
        guard let date = reservationDate(from: record) else { return nil }
        return Self.weekdayFormatter.string(from: date)
    }

    func namesLookSimilar(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs.count >= 4, rhs.count >= 4 else { return false }
        if lhs == rhs { return true }
        if lhs.contains(rhs) || rhs.contains(lhs) { return true }

        let lhsTokens = Set(lhs.split(separator: " ").map(String.init).filter { $0.count > 1 })
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init).filter { $0.count > 1 })
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return false }

        let overlap = lhsTokens.intersection(rhsTokens).count
        let smallerCount = min(lhsTokens.count, rhsTokens.count)
        return Double(overlap) / Double(smallerCount) >= 0.5
    }

    private func emailLocalPartsLookSimilar(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        let cleanLHS = normalizedEmailLocalPart(lhs)
        let cleanRHS = normalizedEmailLocalPart(rhs)

        if cleanLHS == cleanRHS { return true }

        guard cleanLHS.count >= 4, cleanRHS.count >= 4 else { return false }
        return cleanLHS.contains(cleanRHS) || cleanRHS.contains(cleanLHS)
    }

    private func normalizedEmailLocalPart(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func emailParts(_ email: String) -> (local: String, domain: String) {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return (email, "") }
        return (parts[0], parts[1])
    }

    private func reservationPatternLooksSimilar(_ lhs: ReservationRecord, _ rhs: ReservationRecord) -> Bool {
        let samePartySize = lhs.partySize == rhs.partySize
        let sameHour = hour(from: lhs.reservationTime) == hour(from: rhs.reservationTime)
        let sameWeekday = weekdayName(from: lhs) == weekdayName(from: rhs)

        return [samePartySize, sameHour, sameWeekday].filter { $0 }.count >= 2
    }

    private static let commonEmailProviderDomains: Set<String> = [
        "gmail.com",
        "googlemail.com",
        "icloud.com",
        "me.com",
        "mac.com",
        "yahoo.com",
        "ymail.com",
        "outlook.com",
        "hotmail.com",
        "live.com",
        "msn.com",
        "aol.com",
        "proton.me",
        "protonmail.com",
        "pm.me",
        "comcast.net",
        "att.net",
        "sbcglobal.net",
        "verizon.net"
    ]

    private static let dateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateTimeParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}
