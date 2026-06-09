//
//  GuestIdentityResolver.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Resolved Identity

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

// MARK: - Match Result

struct GuestIdentityMatch {
    let record: ReservationRecord
    let confidence: GuestMatchConfidence
    let reasons: [String]

    var isPrimaryHistoryMatch: Bool {
        confidence == .exact || confidence == .strong
    }
}

// MARK: - Identity Resolver

struct GuestIdentityResolver {
    // MARK: - Input Data

    // Intent: Extracts identity signals from one cached ReservationRecord.
    // Placeholder call-in emails are not useful identity evidence.
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

    // MARK: - Matching Rules

    // Intent: Conservative guest matching for hospitality memory.
    // Weak matches are possible identity clues, not confirmed guest history.
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
                reasons: ["Similar full name", "Similar booking pattern"]
            )
        }

        if sameName,
           nameTokens(selected.normalizedName).count >= 2 {
            return GuestIdentityMatch(
                record: record,
                confidence: .possible,
                reasons: ["Similar full name"]
            )
        }

        return nil
    }

    // MARK: - Placeholder / Contact Normalization

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

    // MARK: - Date / Time Helpers

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

    // MARK: - Name / Email Similarity

    func nameTokens(_ name: String) -> [String] {
        name
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    func isSingleTokenName(_ name: String) -> Bool {
        nameTokens(name).count <= 1
    }

    /// Used only when phone or email already matches.
    func namesCompatibleWithSharedContact(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        return fullNamesLookSimilar(lhs, rhs)
    }

    func fullNamesLookSimilar(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }

        let leftTokens = nameTokens(lhs)
        let rightTokens = nameTokens(rhs)
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return false }

        if isSingleTokenName(lhs) != isSingleTokenName(rhs) {
            return false
        }

        if leftTokens.count == 1, rightTokens.count == 1 {
            return leftTokens[0] == rightTokens[0]
        }

        guard let leftLast = leftTokens.last,
              let rightLast = rightTokens.last,
              leftLast == rightLast else {
            return false
        }

        let leftFirst = leftTokens[0]
        let rightFirst = rightTokens[0]
        if leftFirst == rightFirst { return true }
        if leftFirst.count == 1, rightFirst.hasPrefix(leftFirst) { return true }
        if rightFirst.count == 1, leftFirst.hasPrefix(rightFirst) { return true }

        return false
    }

    // MARK: - Manual Test Cases (no unit test target)
    //
    // firstNameOnlyDoesNotSurface:
    //   Anna Kyrychenko should not match Anna Koget / Anna Petrovych / Anna Sinh.
    // singleTokenNameDoesNotMatchFullNameWithoutPhoneOrEmail:
    //   anna should not match Anna Kyrychenko without shared phone/email.
    // samePhoneSurfacesStrongMatch:
    //   Anna Kyrychenko + phone X matches A. Kyrychenko + phone X.
    // sameEmailSurfacesStrongMatch:
    //   same normalized email always exact match.
    // sameFullNameSurfacesPossibleMatch:
    //   Anna Kyrychenko matches Anna Kyrychenko as possible same guest.

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

    // MARK: - Booking Pattern Similarity

    private func reservationPatternLooksSimilar(_ lhs: ReservationRecord, _ rhs: ReservationRecord) -> Bool {
        let samePartySize = lhs.partySize == rhs.partySize
        let sameHour = hour(from: lhs.reservationTime) == hour(from: rhs.reservationTime)
        let sameWeekday = weekdayName(from: lhs) == weekdayName(from: rhs)

        return [samePartySize, sameHour, sameWeekday].filter { $0 }.count >= 2
    }

    // MARK: - Static Lookup / Formatters

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
