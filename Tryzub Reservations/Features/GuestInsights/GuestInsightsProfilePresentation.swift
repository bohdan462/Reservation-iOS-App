//
//  GuestInsightsProfilePresentation.swift
//  Tryzub Reservations
//
//  Staff-readable formatting for backend guest profile packs.
//

import Foundation

enum GuestInsightsProfilePresentation {

    struct ServerVisitRow: Identifiable, Equatable {
        let id: Int
        let headline: String
        let detailLine: String
        let guestNoteLine: String?
        let staffNoteLine: String?
    }

    struct DetailPreview: Equatable {
        let title: String
        let lines: [String]
    }

    static func serverVisitRows(from pack: GuestIntelligenceProfilePackDTO?) -> [ServerVisitRow] {
        guard let pack else { return [] }
        return pack.matchedVisitPreview.map { visit in
            ServerVisitRow(
                id: visit.reservationId > 0 ? visit.reservationId : visit.id,
                headline: serverVisitHeadline(for: visit),
                detailLine: serverVisitDetail(for: visit),
                guestNoteLine: noteLine(prefix: "Guest note", text: visit.guestNotesPreview),
                staffNoteLine: noteLine(prefix: "Staff note", text: visit.staffNotesPreview)
            )
        }
    }

    static func detailPreview(
        guestName: String,
        pack: GuestIntelligenceProfilePackDTO?
    ) -> DetailPreview? {
        guard let pack else { return nil }
        var lines: [String] = []

        if let historyLine = pack.hostProfilePacket?.safeHistoryLine?.nilIfBlank {
            lines.append(historyLine)
        } else if let safeCopy = pack.history?.safeCopy?.nilIfBlank {
            lines.append(safeCopy)
        } else if pack.history?.seenBefore == true {
            lines.append("\(guestName) has visited before.")
        }

        if let lastSeen = displayDate(pack.history?.lastSeenDate)
            ?? pack.hostProfilePacket?.lastSeenLine?.nilIfBlank {
            lines.append("Last seen \(lastSeen).")
        }

        if let preferences = pack.preferences {
            var bookingParts: [String] = []
            if let time = preferences.usualTime?.nilIfBlank {
                bookingParts.append("around \(displayTime(time))")
            }
            if let party = preferences.usualPartySize, party > 0 {
                bookingParts.append("for \(party) guests")
            }
            if !bookingParts.isEmpty {
                let prefix = (pack.history?.priorVisitCount ?? 0) <= 1 ? "Previously booked" : "Usually books"
                lines.append("\(prefix) \(bookingParts.joined(separator: " ")).")
            }
        }

        if let guestNote = pack.noteIntelligence?.latestGuestNotePreview?.nilIfBlank
            ?? pack.matchedVisitPreview.first?.guestNotesPreview?.nilIfBlank {
            lines.append("Prior note: \(truncate(guestNote)).")
        }

        guard !lines.isEmpty else { return nil }
        return DetailPreview(title: "Guest profile", lines: lines)
    }

    static func preferenceLines(from pack: GuestIntelligenceProfilePackDTO?) -> [String] {
        guard let preferences = pack?.preferences else { return [] }
        var lines: [String] = []
        if let time = preferences.usualTime?.nilIfBlank {
            lines.append("Usually around \(displayTime(time))")
        }
        if let weekday = preferences.usualWeekday?.nilIfBlank {
            lines.append("Often on \(weekday)")
        }
        if let party = preferences.usualPartySize, party > 0 {
            lines.append("Often party of \(party)")
        }
        if let largest = preferences.largestPartySize, largest > 0 {
            lines.append("Largest party \(largest)")
        }
        if let tables = preferences.preferredTables?.filter({ !$0.isEmpty }), !tables.isEmpty {
            lines.append("Preferred tables: \(tables.joined(separator: ", "))")
        }
        if let area = preferences.preferredTableArea?.nilIfBlank {
            lines.append("Preferred area: \(area)")
        }
        if let source = preferences.sourcePattern?.nilIfBlank {
            lines.append("Books \(source.lowercased())")
        }
        if let occasion = preferences.commonOccasion?.nilIfBlank {
            lines.append("Common occasion: \(occasion)")
        }
        return lines
    }

    static func visitAnalyticsLines(from pack: GuestIntelligenceProfilePackDTO?) -> [String] {
        guard let analytics = pack?.visitAnalytics else { return [] }
        var lines: [String] = []
        if let known = analytics.knownVisitCount, known > 0 {
            lines.append("Known visits: \(known)")
        }
        if let prior = analytics.priorVisitCount, prior > 0 {
            lines.append("Prior visits: \(prior)")
        }
        if let completed = analytics.completedCount, completed > 0 {
            lines.append("Completed: \(completed)")
        }
        if let cancelled = analytics.cancelledCount, cancelled > 0 {
            lines.append("Cancelled: \(cancelled)")
        }
        if let noShow = analytics.noShowCount, noShow > 0 {
            lines.append("No-shows: \(noShow)")
        }
        if let average = analytics.averagePartySize, average > 0 {
            lines.append(String(format: "Average party: %.1f", average))
        }
        if let breakdown = analytics.sourceBreakdown, !breakdown.isEmpty {
            let parts = breakdown.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
            lines.append("Sources: \(parts.joined(separator: ", "))")
        }
        if let breakdown = analytics.statusBreakdown, !breakdown.isEmpty {
            let parts = breakdown.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
            lines.append("Statuses: \(parts.joined(separator: ", "))")
        }
        return lines
    }

    static func priorNoteLines(from pack: GuestIntelligenceProfilePackDTO?) -> [String] {
        guard let notes = pack?.noteIntelligence else { return [] }
        var lines: [String] = []
        if let guest = notes.latestGuestNotePreview?.nilIfBlank {
            lines.append("Latest guest note: \(truncate(guest))")
        }
        if let staff = notes.latestStaffNotePreview?.nilIfBlank {
            lines.append("Latest staff note: \(truncate(staff))")
        }
        if notes.guestNoteCount > 0 {
            lines.append("Prior guest notes: \(notes.guestNoteCount)")
        }
        if notes.staffNoteCount > 0 {
            lines.append("Prior staff notes: \(notes.staffNoteCount)")
        }
        if !notes.allNoteSignals.isEmpty {
            let bucketLines = notes.allNoteSignals
                .filter { !$0.value.isEmpty }
                .sorted { $0.key < $1.key }
                .map { key, values in
                    // .convertFromSnakeCase rewrites dict keys too (table_preference → tablePreference,
                    // service_issue → serviceIssue). Map known keys to staff-readable labels;
                    // fallback splits camelCase/snake_case for unknown future keys.
                    let label = GuestIntelligenceSignalLabels.display(for: key)
                    return "\(label): \(values.joined(separator: ", "))"
                }
            lines.append(contentsOf: bucketLines)
        }
        return lines
    }

    private static func serverVisitHeadline(for visit: GuestIntelligenceMatchedVisitPreviewDTO) -> String {
        let date = displayDate(visit.date) ?? visit.date
        let time = displayTime(visit.time)
        return "\(date) · \(time)"
    }

    private static func serverVisitDetail(for visit: GuestIntelligenceMatchedVisitPreviewDTO) -> String {
        var parts = ["\(visit.partySize) guests"]
        let status = visit.status.nilIfBlank ?? "Unknown"
        parts.append(status.capitalized)
        if let table = visit.tableName?.nilIfBlank {
            parts.append("Table \(table)")
        }
        if let source = visit.source?.nilIfBlank {
            parts.append(source.capitalized)
        }
        return parts.joined(separator: " · ")
    }

    private static func displayDate(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let date = ReservationFormatters.reservationDateKey.date(from: raw) {
            return ReservationFormatters.mediumDate.string(from: date)
        }
        return raw
    }

    private static func displayTime(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = ReservationFormatters.apiTime.date(from: trimmed) {
            return ReservationFormatters.shortTime.string(from: date)
        }
        return trimmed
    }

    private static func noteLine(prefix: String, text: String?) -> String? {
        guard let text = text?.nilIfBlank else { return nil }
        return "\(prefix): \(truncate(text))"
    }

    private static func truncate(_ text: String, limit: Int = 120) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
