//
//  GuestInsightsProfilePresentation.swift
//  Tryzub Reservations
//
//  Restaurant user-readable formatting for backend guest profile packs.
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
        let badges: [String]
        let showsUpdatingBadge: Bool

        init(
            title: String,
            lines: [String],
            badges: [String] = [],
            showsUpdatingBadge: Bool = false
        ) {
            self.title = title
            self.lines = lines
            self.badges = badges
            self.showsUpdatingBadge = showsUpdatingBadge
        }
    }

    struct AggregateProfileState: Equatable {
        let sourceLine: String
        let showsUpdatingBadge: Bool
        let summaryLines: [String]
        let labels: [AggregateLabelState]
        let countCards: [AggregateMetricState]
        let preferenceLines: [String]
        let noteLines: [String]
        let upcomingLine: String?
    }

    struct AggregateLabelState: Identifiable, Equatable {
        let id: String
        let title: String
        let detail: String?
        let evidence: String?
    }

    struct AggregateMetricState: Identifiable, Equatable {
        let id: String
        let title: String
        let value: String
        let caption: String
    }

    static func aggregateState(from profile: GuestProfileDTO?) -> AggregateProfileState? {
        guard let profile else { return nil }
        let labels = safeLabels(from: profile.labels)
        let summaryLines = aggregateSummaryLines(from: profile, labels: labels)
        return AggregateProfileState(
            sourceLine: profile.stale == true ? "Based on backend guest profile. Profile updating." : "Based on backend guest profile.",
            showsUpdatingBadge: profile.stale == true,
            summaryLines: summaryLines,
            labels: labels,
            countCards: aggregateMetrics(from: profile),
            preferenceLines: aggregatePreferenceLines(from: profile),
            noteLines: aggregateNoteLines(from: profile),
            upcomingLine: upcomingLine(from: profile.nextReservation)
        )
    }

    static func detailPreview(profile: GuestProfileDTO?) -> DetailPreview? {
        guard let profile else { return nil }
        var lines: [String] = []
        let visitCount = profile.cleanVisitCount ?? profile.totalReservations ?? 0
        if visitCount > 0 {
            lines.append("\(visitCount) \(visitCount == 1 ? "visit" : "visits") in backend guest profile.")
        }
        if let lastSeen = displayDate(profile.lastSeenDate) {
            lines.append("Last seen \(lastSeen).")
        }
        if let partySize = profile.usualPartySize ?? profile.preferences?.usualPartySize, partySize > 0 {
            lines.append("Usually books for \(partySize) guests.")
        }
        if let upcoming = upcomingLine(from: profile.nextReservation) {
            lines.append(upcoming)
        }
        let badges = safeLabels(from: profile.labels).map(\.title)
        guard !lines.isEmpty || !badges.isEmpty || profile.stale == true else { return nil }
        return DetailPreview(
            title: "Backend guest profile",
            lines: lines,
            badges: Array(badges.prefix(4)),
            showsUpdatingBadge: profile.stale == true
        )
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

    private static func aggregateSummaryLines(
        from profile: GuestProfileDTO,
        labels: [AggregateLabelState]
    ) -> [String] {
        var lines: [String] = []
        if let summary = profile.summary?.summaryText?.nilIfBlank {
            lines.append(truncate(summary, limit: 180))
        }
        if let first = labels.first {
            if let detail = first.detail?.nilIfBlank {
                lines.append("\(first.title): \(detail)")
            } else if let evidence = first.evidence?.nilIfBlank {
                lines.append("\(first.title): \(evidence)")
            }
        }
        if lines.isEmpty, let name = profile.primaryName?.nilIfBlank {
            lines.append("\(name)'s profile is loaded from backend guest history.")
        }
        return lines
    }

    private static func aggregateMetrics(from profile: GuestProfileDTO) -> [AggregateMetricState] {
        var metrics: [AggregateMetricState] = []
        let total = profile.totalReservations ?? 0
        let clean = profile.cleanVisitCount ?? 0
        metrics.append(
            AggregateMetricState(
                id: "visits",
                title: "Visits",
                value: "\(max(clean, total))",
                caption: clean > 0 ? "Clean visits" : "Reservations"
            )
        )
        if let lastSeen = displayDate(profile.lastSeenDate) {
            metrics.append(AggregateMetricState(id: "last_seen", title: "Last seen", value: lastSeen, caption: "Backend profile"))
        }
        if let party = profile.usualPartySize ?? profile.preferences?.usualPartySize, party > 0 {
            metrics.append(AggregateMetricState(id: "party", title: "Usual party", value: "\(party)", caption: "Most common size"))
        }
        if let upcoming = profile.upcomingCount, upcoming > 0 {
            metrics.append(AggregateMetricState(id: "upcoming", title: "Upcoming", value: "\(upcoming)", caption: "Future reservations"))
        }
        if let noShow = profile.noShowCount ?? profile.counts?.noShow, noShow > 0 {
            metrics.append(AggregateMetricState(id: "no_show", title: "No-shows", value: "\(noShow)", caption: "Backend history"))
        }
        if let cancelled = profile.cancelledCount ?? profile.counts?.cancelled, cancelled > 0 {
            metrics.append(AggregateMetricState(id: "cancelled", title: "Cancelled", value: "\(cancelled)", caption: "Backend history"))
        }
        return Array(metrics.prefix(6))
    }

    private static func aggregatePreferenceLines(from profile: GuestProfileDTO) -> [String] {
        var lines: [String] = []
        if let party = profile.usualPartySize ?? profile.preferences?.usualPartySize, party > 0 {
            lines.append("Usually party of \(party)")
        }
        if let average = profile.averagePartySize ?? profile.preferences?.averagePartySize, average > 0 {
            lines.append(String(format: "Average party %.1f", average))
        }
        if let largest = profile.largestPartySize ?? profile.preferences?.largestPartySize, largest > 0 {
            lines.append("Largest party \(largest)")
        }
        if let hour = profile.usualHour ?? profile.preferences?.usualHour {
            lines.append("Usually around \(displayHour(hour))")
        }
        if let weekday = profile.usualWeekday ?? profile.preferences?.usualWeekday {
            lines.append("Often \(displayWeekday(weekday))")
        }
        return lines
    }

    private static func aggregateNoteLines(from profile: GuestProfileDTO) -> [String] {
        var lines: [String] = []
        let guestNotes = profile.counts?.guestNotes ?? 0
        let internalNotes = profile.counts?.staffNotes ?? 0
        if guestNotes > 0 {
            lines.append("\(guestNotes) guest \(guestNotes == 1 ? "note" : "notes") found")
        }
        if internalNotes > 0 {
            lines.append("\(internalNotes) internal \(internalNotes == 1 ? "note" : "notes") found")
        }
        if profile.noteFlags?.hasBirthdayNote == true {
            lines.append("Birthday note")
        }
        if profile.noteFlags?.hasOccasionNote == true {
            lines.append("Occasion note")
        }
        if profile.noteFlags?.hasReplyNeededNote == true {
            lines.append("May expect a reply")
        }
        if profile.noteFlags?.hasDietaryNote == true {
            lines.append("Dietary note")
        }
        return lines
    }

    private static func safeLabels(from labels: [GuestProfileLabelDTO]?) -> [AggregateLabelState] {
        Array((labels ?? [])
            .compactMap { label -> AggregateLabelState? in
                guard let title = label.title?.nilIfBlank else { return nil }
                let values = [label.id, label.title, label.category, label.source]
                guard !values.contains(where: containsUnsupportedLabelToken) else { return nil }
                let identity = [label.id, label.category, label.title, label.detail]
                    .compactMap { $0?.nilIfBlank }
                    .joined(separator: "|")
                return AggregateLabelState(
                    id: identity.isEmpty ? title : identity,
                    title: title,
                    detail: safeLabelDisplayText(label.detail),
                    evidence: safeLabelDisplayText(label.evidence)
                )
            }
            .prefix(8))
    }

    private static func safeLabelDisplayText(_ value: String?) -> String? {
        guard let value = value?.nilIfBlank else { return nil }
        guard !containsUnsupportedLabelToken(value) else { return nil }
        return value
    }

    private static func upcomingLine(from nextReservation: GuestProfileNextReservationDTO?) -> String? {
        guard let nextReservation else { return nil }
        let date = displayDate(nextReservation.reservationDate ?? nextReservation.date)
        let time = (nextReservation.reservationTime ?? nextReservation.time).flatMap(displayOptionalTime)
        let party = nextReservation.partySize.map { "\($0) guests" }
        let parts = [date, time, party].compactMap { $0 }
        guard !parts.isEmpty else { return "Upcoming reservation on file." }
        return "Next reservation: \(parts.joined(separator: " · "))."
    }

    private static func displayHour(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        let suffix = normalized >= 12 ? "PM" : "AM"
        let displayHour = normalized % 12 == 0 ? 12 : normalized % 12
        return "\(displayHour) \(suffix)"
    }

    private static func displayWeekday(_ weekday: Int) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard weekday >= 0, weekday < names.count else { return "same weekday" }
        return names[weekday]
    }

    private static func displayOptionalTime(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return displayTime(trimmed)
    }

    private static func containsUnsupportedLabelToken(_ value: String?) -> Bool {
        guard let value = value?.nilIfBlank else { return false }
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        let exactBlocked = [
            "vip", "high spender", "highspender",
            "wine drinker", "winedrinker",
            "cocktail guest", "cocktailguest",
            "risky", "risk",
            "problem", "problem guest", "problemguest",
            "suspicious", "suspicious guest", "suspiciousguest",
            "concerned", "concerned guest", "concernedguest"
        ]
        if exactBlocked.contains(normalized) || exactBlocked.contains(compact) { return true }
        return normalized.contains("high spender")
            || normalized.contains("wine")
            || normalized.contains("cocktail")
            || normalized.contains("risky")
            || normalized.contains("problem guest")
            || normalized.contains("suspicious")
            || normalized.contains("concerned guest")
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
                    // service_issue → serviceIssue). Map known keys to Restaurant user-readable labels;
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
