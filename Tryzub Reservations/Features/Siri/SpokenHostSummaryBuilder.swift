//
//  SpokenHostSummaryBuilder.swift
//  Tryzub Reservations
//

import Foundation

struct SpokenHostSummaryBuilder {
    private let largePartyThreshold = 7
    private let maxCharacterCount = 450

    func build(
        from reservations: [ReservationDTO],
        dateKey: String,
        now: Date = Date(),
        prefix: String = ""
    ) -> String {
        build(
            from: reservations.map(SpokenHostSummaryReservation.init(dto:)),
            dateKey: dateKey,
            now: now,
            prefix: prefix
        )
    }

    func build(
        from reservations: [ReservationRecord],
        dateKey: String,
        now: Date = Date(),
        prefix: String = ""
    ) -> String {
        build(
            from: reservations.map(SpokenHostSummaryReservation.init(record:)),
            dateKey: dateKey,
            now: now,
            prefix: prefix
        )
    }

    private func build(
        from reservations: [SpokenHostSummaryReservation],
        dateKey: String,
        now: Date,
        prefix: String
    ) -> String {
        let todayReservations = reservations
            .filter { !$0.isHidden && $0.reservationDate == dateKey }

        let expected = todayReservations
            .filter(\.isExpectedGuest)
            .sortedChronologically()

        guard !expected.isEmpty else {
            return noReservationsSentence(prefix: prefix)
        }

        let openWork = expected.filter(\.isOpenWork)
        let guestCount = expected.reduce(0) { $0 + $1.partySize }
        let newCount = openWork.filter { $0.status == .new }.count
        let needsReviewCount = openWork.filter { $0.status == .needsReview }.count
        let noTableCount = openWork.filter { !$0.hasTableAssignment }.count
        let nextReservation = nextExpectedArrival(from: openWork, now: now)
        let peakHour = peakHour(from: expected)
        let noteFlags = noteFlags(from: expected)

        let lead = prefix.isEmpty ? "Today has" : "\(prefix)today has"
        var sentences: [String] = [
            "\(lead) \(expected.count) \(reservationWord(expected.count)) and \(guestCount) \(guestWord(guestCount)).",
            reviewSentence(newCount: newCount, needsReviewCount: needsReviewCount)
        ]

        if noTableCount > 0 {
            sentences.append("\(capitalizedCount(noTableCount)) \(reservationWord(noTableCount)) still \(noTableCount == 1 ? "has" : "have") no table.")
        }

        if let nextReservation,
           let time = spokenTime(from: nextReservation.reservationTime) {
            let name = safeFirstName(from: nextReservation.guestName)
            if let name {
                sentences.append("Next is \(name) at \(time).")
            } else {
                sentences.append("Next party is at \(time).")
            }
        }

        if let peakHour {
            sentences.append("Peak hour is \(spokenHour(peakHour)).")
        }

        if let noteSentence = noteFlagSentence(noteFlags) {
            sentences.append(noteSentence)
        }

        return trimmedSummary(from: sentences)
    }

    private func reviewSentence(newCount: Int, needsReviewCount: Int) -> String {
        let total = newCount + needsReviewCount
        if total == 0 {
            return "No new reservations need review."
        }
        if newCount > 0 && needsReviewCount > 0 {
            return "\(capitalizedCount(total)) \(reservationWord(total)) need review: \(newCount) new and \(needsReviewCount) flagged."
        }
        if newCount > 0 {
            return "\(capitalizedCount(newCount)) new \(reservationWord(newCount)) \(newCount == 1 ? "needs" : "need") review."
        }
        return "\(capitalizedCount(needsReviewCount)) \(reservationWord(needsReviewCount)) \(needsReviewCount == 1 ? "needs" : "need") review."
    }

    private func nextExpectedArrival(
        from reservations: [SpokenHostSummaryReservation],
        now: Date
    ) -> SpokenHostSummaryReservation? {
        let candidates = reservations
            .filter { $0.serviceDateTime != nil }
            .sortedChronologically()

        return candidates.first { reservation in
            guard let serviceDate = reservation.serviceDateTime else { return false }
            return serviceDate >= now
        } ?? candidates.first
    }

    private func peakHour(from reservations: [SpokenHostSummaryReservation]) -> Int? {
        let grouped = Dictionary(grouping: reservations) { reservation in
            reservation.serviceHour ?? -1
        }

        return grouped
            .filter { $0.key >= 0 }
            .map { hour, rows in
                (hour: hour, guests: rows.reduce(0) { $0 + $1.partySize })
            }
            .sorted {
                if $0.guests == $1.guests {
                    return $0.hour < $1.hour
                }
                return $0.guests > $1.guests
            }
            .first?.hour
    }

    private func noteFlags(from reservations: [SpokenHostSummaryReservation]) -> NoteFlags {
        var flags = NoteFlags()

        for reservation in reservations {
            let notes = normalizedNotes(reservation.guestNotes)
            if notes.contains("birthday") || notes.contains("bday") {
                flags.birthdays += 1
            }
            if notes.contains("anniversary") {
                flags.anniversaries += 1
            }
            if containsAny(
                notes,
                [
                    "allergy", "allergic", "celiac", "gluten", "dairy", "shellfish",
                    "shrimp", "crab", "lobster", "peanut", "tree nut", "nut allergy",
                    "sesame", "soy", "egg", "fish", "vegan", "vegetarian", "kosher", "halal"
                ]
            ) {
                flags.dietary += 1
            }
            if containsAny(
                notes,
                ["wheelchair", "accessible", "accessibility", "mobility", "high chair", "highchair"]
            ) {
                flags.accessibility += 1
            }
            if reservation.partySize >= largePartyThreshold {
                flags.largeParties += 1
            }
        }

        return flags
    }

    private func noteFlagSentence(_ flags: NoteFlags) -> String? {
        let phrases = [
            flagPhrase(count: flags.birthdays, singular: "birthday note", plural: "birthday notes"),
            flagPhrase(count: flags.anniversaries, singular: "anniversary note", plural: "anniversary notes"),
            flagPhrase(count: flags.dietary, singular: "dietary note", plural: "dietary notes"),
            flagPhrase(count: flags.accessibility, singular: "accessibility note", plural: "accessibility notes"),
            flagPhrase(count: flags.largeParties, singular: "large party", plural: "large parties")
        ].compactMap { $0 }

        guard !phrases.isEmpty else { return nil }
        if phrases.count == 1 {
            return "\(phrases[0].capitalizedFirst) needs checking."
        }
        return "Check \(phrases.joinedForSpeech())."
    }

    private func flagPhrase(count: Int, singular: String, plural: String) -> String? {
        guard count > 0 else { return nil }
        return "\(lowercaseCount(count)) \(count == 1 ? singular : plural)"
    }

    private func spokenTime(from value: String) -> String? {
        guard let parts = timeParts(from: value) else { return nil }
        return spokenClock(hour: parts.hour, minute: parts.minute)
    }

    private func spokenHour(_ hour: Int) -> String {
        spokenClock(hour: hour, minute: 0)
    }

    private func spokenClock(hour: Int, minute: Int) -> String {
        let normalizedHour = ((hour % 24) + 24) % 24
        let suffix = normalizedHour < 12 ? "AM" : "PM"
        let hour12 = normalizedHour % 12 == 0 ? 12 : normalizedHour % 12
        if minute == 0 {
            return "\(hour12) \(suffix)"
        }
        return "\(hour12):\(String(format: "%02d", minute)) \(suffix)"
    }

    private func timeParts(from value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return (hour, minute)
    }

    private func safeFirstName(from guestName: String) -> String? {
        let firstToken = guestName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        guard let firstToken, !firstToken.isEmpty else { return nil }

        let blockedWords = ["vip", "regular"]
        guard !blockedWords.contains(firstToken.lowercased()) else { return nil }
        return firstToken
    }

    private func normalizedNotes(_ value: String?) -> String {
        value?
            .replacingOccurrences(of: "\n", with: " ")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func reservationWord(_ count: Int) -> String {
        count == 1 ? "reservation" : "reservations"
    }

    private func noReservationsSentence(prefix: String) -> String {
        if prefix.isEmpty {
            return "No reservations are currently listed for today."
        }
        return "\(prefix)no reservations are currently listed for today."
    }

    private func guestWord(_ count: Int) -> String {
        count == 1 ? "guest" : "guests"
    }

    private func lowercaseCount(_ count: Int) -> String {
        count == 1 ? "one" : "\(count)"
    }

    private func capitalizedCount(_ count: Int) -> String {
        count == 1 ? "One" : "\(count)"
    }

    private func trimmedSummary(from sentences: [String]) -> String {
        var accepted: [String] = []
        for sentence in sentences {
            let candidate = (accepted + [sentence]).joined(separator: " ")
            guard candidate.count <= maxCharacterCount else { break }
            accepted.append(sentence)
        }
        return accepted.joined(separator: " ")
    }
}

private struct NoteFlags {
    var birthdays = 0
    var anniversaries = 0
    var dietary = 0
    var accessibility = 0
    var largeParties = 0
}

private struct SpokenHostSummaryReservation {
    let id: Int
    let guestName: String
    let reservationDate: String
    let reservationTime: String
    let partySize: Int
    let status: ReservationStatus
    let tableName: String?
    let guestNotes: String?
    let isHidden: Bool

    init(dto: ReservationDTO) {
        id = dto.id
        guestName = dto.guestName
        reservationDate = dto.reservationDate
        reservationTime = dto.reservationTime
        partySize = dto.partySize
        status = dto.status
        tableName = dto.tableName
        guestNotes = dto.guestNotes
        isHidden = dto.isHidden ?? false
    }

    init(record: ReservationRecord) {
        id = record.remoteID
        guestName = record.guestName
        reservationDate = record.reservationDate
        reservationTime = record.reservationTime
        partySize = record.partySize
        status = record.statusValue
        tableName = record.tableName
        guestNotes = record.guestNotes
        isHidden = record.isHidden
    }

    var isExpectedGuest: Bool {
        switch status {
        case .new, .needsReview, .confirmed, .seated:
            return true
        case .completed, .cancelled, .noShow:
            return false
        }
    }

    var isOpenWork: Bool {
        switch status {
        case .new, .needsReview, .confirmed:
            return true
        case .seated, .completed, .cancelled, .noShow:
            return false
        }
    }

    var hasTableAssignment: Bool {
        tableName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var serviceHour: Int? {
        reservationTime
            .split(separator: ":")
            .first
            .flatMap { Int($0) }
            .flatMap { (0...23).contains($0) ? $0 : nil }
    }

    var serviceDateTime: Date? {
        let time = reservationTime.count >= 5 ? String(reservationTime.prefix(5)) : reservationTime
        if let date = ReservationFormatters.serverDateTime.date(from: "\(reservationDate) \(reservationTime)") {
            return date
        }
        return ReservationFormatters.serverDateMinute.date(from: "\(reservationDate) \(time)")
    }
}

private extension Array where Element == SpokenHostSummaryReservation {
    func sortedChronologically() -> [SpokenHostSummaryReservation] {
        sorted {
            if $0.reservationDate == $1.reservationDate {
                if $0.reservationTime == $1.reservationTime {
                    return $0.id < $1.id
                }
                return $0.reservationTime < $1.reservationTime
            }
            return $0.reservationDate < $1.reservationDate
        }
    }
}

private extension Array where Element == String {
    func joinedForSpeech() -> String {
        switch count {
        case 0:
            return ""
        case 1:
            return self[0]
        case 2:
            return "\(self[0]) and \(self[1])"
        default:
            return dropLast().joined(separator: ", ") + ", and \(last ?? "")"
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
