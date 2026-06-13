//
//  HostReservationActionClusterBuilder.swift
//  Tryzub Reservations
//
//  Reservation-centered deterministic action clusters for the Host board.
//

import Foundation

enum HostReservationActionClusterBuilder {

    struct Input {
        let selectedDate: Date
        let now: Date
        let reservations: [ReservationRecord]
        let briefingFacts: [HostBriefingFact]
        let suggestedActions: [HostSuggestedAction]
        let guestSignals: [HostGuestSignal]
        let tableSignals: [HostTableSignal]
        let seatedTimingSignals: [HostSeatedTimingSignal]
        let settings: HostIntelligenceSettings
    }

    static func build(input: Input) -> [HostReservationActionCluster] {
        let activeReservations = input.reservations
            .filter { !$0.isHidden }
            .sorted { lhs, rhs in
                if lhs.reservationTime == rhs.reservationTime {
                    return lhs.remoteID < rhs.remoteID
                }
                return lhs.reservationTime < rhs.reservationTime
            }

        let factsByReservation = groupedByReservationID(input.briefingFacts)
        let actionsByReservation = groupedByReservationID(input.suggestedActions)
        let guestSignalsByReservation = Dictionary(grouping: input.guestSignals, by: \.reservationID)
        let tableSignalsByReservation = tableSignalsByReservation(input.tableSignals)
        let seatedSignalsByReservation = Dictionary(grouping: input.seatedTimingSignals, by: \.reservationID)

        var signalCounts: [HostReservationSignal: Int] = [:]
        var clusters: [HostReservationActionCluster] = []

        for reservation in activeReservations {
            let remoteID = reservation.remoteID
            var signalSet = Set<HostReservationSignal>()
            var severity = HostSeverity.info

            let noteFlags = deterministicNoteFlags(from: reservation.guestNotes)
            noteFlags.forEach { signalSet.insert($0) }

            if reservation.isOpenWork, !reservation.hasTableAssignment {
                signalSet.insert(.noTable)
            }

            if reservation.partySize >= input.settings.largePartyThreshold {
                signalSet.insert(.largeParty)
            }

            if shouldSuggestConfirmation(for: reservation) {
                signalSet.insert(.confirmationMissing)
            }

            if shouldSuggestReminder(for: reservation, now: input.now) {
                signalSet.insert(.reminderMissing)
            }

            switch reservation.operationalTimingState(now: input.now) {
            case .dueNow, .overdue:
                if reservation.statusValue == .confirmed || reservation.statusValue == .new || reservation.statusValue == .needsReview {
                    signalSet.insert(.lateAttention)
                }
                if reservation.statusValue == .confirmed, reservation.hasTableAssignment {
                    signalSet.insert(.tableReadyRelevant)
                }
            case .none, .normal, .dueSoon:
                break
            }

            for signal in guestSignalsByReservation[remoteID] ?? [] {
                severity = highest(severity, signal.severity)
                switch signal.kind {
                case .allergy:
                    signalSet.insert(.dietary)
                case .accessibility:
                    signalSet.insert(.accessibility)
                case .specialOccasion:
                    signalSet.insert(.celebration)
                case .regularGuest, .importantGuest, .vip:
                    signalSet.insert(.returningGuest)
                case .seatingPreference, .noteReminder:
                    signalSet.insert(.guestNote)
                case .cancellationRisk, .noShowRisk, .previousServiceIssue, .manualCallIn, .possibleDuplicate, .unknown:
                    break
                }
            }

            for signal in tableSignalsByReservation[remoteID] ?? [] {
                severity = highest(severity, signal.severity)
                switch signal.kind {
                case .noTableAssigned:
                    signalSet.insert(.noTable)
                case .doubleBookedTable, .tableCapacityMismatch:
                    signalSet.insert(.tableMismatch)
                case .longSeated, .tableTurnRisk:
                    signalSet.insert(.seatedTooLong)
                case .tableFreed, .cancellationFreedTable, .unknown:
                    break
                }
            }

            if let seatedSignals = seatedSignalsByReservation[remoteID], !seatedSignals.isEmpty {
                signalSet.insert(.seatedTooLong)
            }

            for fact in factsByReservation[remoteID] ?? [] {
                severity = highest(severity, fact.severity)
                inferredSignals(from: fact).forEach { signalSet.insert($0) }
            }

            for action in actionsByReservation[remoteID] ?? [] {
                severity = highest(severity, action.severity)
                inferredSignals(from: action).forEach { signalSet.insert($0) }
            }

            guard !signalSet.isEmpty else { continue }

            let signals = orderedSignals(Array(signalSet))
            signals.forEach { signalCounts[$0, default: 0] += 1 }

            let primaryAction = primaryAction(for: reservation, signals: signals)
            let secondaryActions = secondaryActions(for: reservation, signals: signals, primaryAction: primaryAction)
            let title = title(for: reservation, signals: signals)
            let summary = summary(for: signals)

            clusters.append(
                HostReservationActionCluster(
                    id: "host-cluster-\(remoteID)",
                    reservationRemoteID: remoteID,
                    reservationLocalID: reservation.id,
                    guestDisplayName: safeGuestDisplayName(reservation.guestName),
                    reservationTimeText: reservation.displayTime,
                    partySize: max(reservation.partySize, 1),
                    tableName: reservation.assignedTableName,
                    severity: severity,
                    title: title,
                    summary: summary,
                    signals: signals,
                    primaryAction: primaryAction,
                    secondaryActions: secondaryActions
                )
            )
        }

        let duplicateFlatActionsCollapsed = max(0, input.suggestedActions.count - Set(
            input.suggestedActions.map { action in
                "\(action.kind.rawValue):\(action.relatedReservationIDs.sorted().map(String.init).joined(separator: ","))"
            }
        ).count)

        HostProductionTrace.hostActionCluster(
            date: input.selectedDate.reservationDateString(),
            reservationCount: activeReservations.count,
            clusterCount: clusters.count,
            signalCounts: signalCounts,
            duplicateFlatActionsCollapsed: duplicateFlatActionsCollapsed
        )

        return clusters
            .sorted { lhs, rhs in
                if lhs.severity.rank != rhs.severity.rank {
                    return lhs.severity.rank < rhs.severity.rank
                }
                return lhs.reservationTimeText < rhs.reservationTimeText
            }
    }

    // MARK: - Grouping

    private static func groupedByReservationID(_ facts: [HostBriefingFact]) -> [Int: [HostBriefingFact]] {
        var grouped: [Int: [HostBriefingFact]] = [:]
        for fact in facts {
            for id in fact.relatedReservationIDs {
                grouped[id, default: []].append(fact)
            }
        }
        return grouped
    }

    private static func groupedByReservationID(_ actions: [HostSuggestedAction]) -> [Int: [HostSuggestedAction]] {
        var grouped: [Int: [HostSuggestedAction]] = [:]
        for action in actions {
            for id in action.relatedReservationIDs {
                grouped[id, default: []].append(action)
            }
        }
        return grouped
    }

    private static func tableSignalsByReservation(_ signals: [HostTableSignal]) -> [Int: [HostTableSignal]] {
        var grouped: [Int: [HostTableSignal]] = [:]
        for signal in signals {
            for id in signal.relatedReservationIDs {
                grouped[id, default: []].append(signal)
            }
        }
        return grouped
    }

    // MARK: - Signals

    private static func deterministicNoteFlags(from notes: String?) -> Set<HostReservationSignal> {
        let normalized = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }

        var flags: Set<HostReservationSignal> = [.guestNote]
        if containsAny(normalized, ["birthday", "bday", "birth day"]) {
            flags.insert(.birthday)
        }
        if containsAny(normalized, ["anniversary"]) {
            flags.insert(.anniversary)
        }
        if containsAny(normalized, ["celebration", "celebrate", "occasion", "graduation", "engagement"]) {
            flags.insert(.celebration)
        }
        if containsAny(normalized, [
            "allergy", "allergic", "dietary", "gluten", "celiac", "vegan",
            "vegetarian", "nut", "peanut", "shellfish", "dairy", "lactose"
        ]) {
            flags.insert(.dietary)
        }
        if containsAny(normalized, ["wheelchair", "accessible", "accessibility", "mobility", "walker"]) {
            flags.insert(.accessibility)
        }
        return flags
    }

    private static func inferredSignals(from fact: HostBriefingFact) -> Set<HostReservationSignal> {
        let lower = "\(fact.title) \(fact.detail) \(fact.suggestedActionTitle ?? "")".lowercased()
        var signals: Set<HostReservationSignal> = []
        if lower.contains("no table") || lower.contains("assign table") {
            signals.insert(.noTable)
        }
        if lower.contains("confirmation") {
            signals.insert(.confirmationMissing)
        }
        if lower.contains("reminder") {
            signals.insert(.reminderMissing)
        }
        if lower.contains("birthday") {
            signals.insert(.birthday)
        }
        if lower.contains("anniversary") {
            signals.insert(.anniversary)
        }
        if lower.contains("allergy") || lower.contains("dietary") {
            signals.insert(.dietary)
        }
        if lower.contains("accessibility") || lower.contains("wheelchair") {
            signals.insert(.accessibility)
        }
        if lower.contains("large party") {
            signals.insert(.largeParty)
        }
        if lower.contains("marked seated") || lower.contains("too long") {
            signals.insert(.seatedTooLong)
        }
        return signals
    }

    private static func inferredSignals(from action: HostSuggestedAction) -> Set<HostReservationSignal> {
        switch action.kind {
        case .assignTable:
            return [.noTable]
        case .confirmReservation:
            return [.confirmationMissing]
        case .generateEmailDraft:
            return [.confirmationMissing]
        case .seatReservation:
            return [.lateAttention]
        case .completeReservation:
            return [.seatedTooLong]
        case .reviewReservation:
            return [.guestNote]
        case .alertServer:
            return [.tableReadyRelevant]
        case .suggestAlternateTime, .closeSlot, .holdTable, .releaseTable, .generateGuestManageLink, .markNoShow, .reviewCancellationOpportunity, .noAction:
            return []
        }
    }

    private static func orderedSignals(_ signals: [HostReservationSignal]) -> [HostReservationSignal] {
        let priority: [HostReservationSignal] = [
            .noTable,
            .tableMismatch,
            .birthday,
            .anniversary,
            .dietary,
            .accessibility,
            .guestNote,
            .confirmationMissing,
            .reminderMissing,
            .largeParty,
            .lateAttention,
            .tableReadyRelevant,
            .seatedTooLong,
            .celebration,
            .returningGuest
        ]
        return signals.sorted { lhs, rhs in
            (priority.firstIndex(of: lhs) ?? priority.endIndex)
                < (priority.firstIndex(of: rhs) ?? priority.endIndex)
        }
    }

    // MARK: - Actions

    private static func primaryAction(
        for reservation: ReservationRecord,
        signals: [HostReservationSignal]
    ) -> HostQuickAction {
        let id = reservation.remoteID
        if signals.contains(where: { [.birthday, .anniversary, .dietary, .accessibility, .guestNote].contains($0) }),
           reservation.hasGuestNotes {
            return .viewGuestNote(remoteID: id)
        }
        if signals.contains(.confirmationMissing), reservation.hasUsableConfirmationEmail {
            return .draftConfirmation(remoteID: id)
        }
        if signals.contains(.reminderMissing), reservation.hasUsableConfirmationEmail {
            return .draftReminder(remoteID: id)
        }
        if signals.contains(.noTable) || signals.contains(.tableMismatch) {
            return .assignTable(remoteID: id)
        }
        if signals.contains(.tableReadyRelevant), reservation.hasUsableConfirmationEmail {
            return .draftTableReady(remoteID: id)
        }
        if signals.contains(.lateAttention), reservation.statusValue == .confirmed {
            return .markSeated(remoteID: id)
        }
        return .openReservation(remoteID: id)
    }

    private static func secondaryActions(
        for reservation: ReservationRecord,
        signals: [HostReservationSignal],
        primaryAction: HostQuickAction
    ) -> [HostQuickAction] {
        let id = reservation.remoteID
        var actions: [HostQuickAction] = []

        func append(_ action: HostQuickAction, when condition: Bool = true) {
            guard condition, action != primaryAction, !actions.contains(action) else { return }
            actions.append(action)
        }

        append(.viewGuestNote(remoteID: id), when: reservation.hasGuestNotes)
        append(.draftConfirmation(remoteID: id), when: signals.contains(.confirmationMissing) && reservation.hasUsableConfirmationEmail)
        append(.draftReminder(remoteID: id), when: signals.contains(.reminderMissing) && reservation.hasUsableConfirmationEmail)
        append(.assignTable(remoteID: id), when: reservation.isOpenWork && !reservation.hasTableAssignment)
        append(.draftTableReady(remoteID: id), when: signals.contains(.tableReadyRelevant) && reservation.hasUsableConfirmationEmail)
        append(.openReservation(remoteID: id))

        return Array(actions.prefix(3))
    }

    // MARK: - Presentation

    private static func title(for reservation: ReservationRecord, signals: [HostReservationSignal]) -> String {
        let name = safeGuestDisplayName(reservation.guestName)
        let suffix: String
        if signals.contains(.birthday) {
            suffix = "birthday note"
        } else if signals.contains(.anniversary) {
            suffix = "anniversary note"
        } else if signals.contains(.dietary) {
            suffix = "dietary note"
        } else if signals.contains(.accessibility) {
            suffix = "accessibility note"
        } else if signals.contains(.noTable) {
            suffix = "needs a table"
        } else if signals.contains(.confirmationMissing) {
            suffix = "needs confirmation"
        } else if signals.contains(.reminderMissing) {
            suffix = "reminder not sent"
        } else if signals.contains(.largeParty) {
            suffix = "\(reservation.partySize)-guest party"
        } else if signals.contains(.returningGuest) {
            suffix = "returning guest context"
        } else {
            suffix = "needs attention"
        }
        return "\(name) - \(suffix)"
    }

    private static func summary(for signals: [HostReservationSignal]) -> String {
        var lines: [String] = []
        if signals.contains(.birthday) {
            lines.append("Birthday mentioned.")
        } else if signals.contains(.anniversary) {
            lines.append("Anniversary mentioned.")
        } else if signals.contains(.celebration) {
            lines.append("Celebration mentioned.")
        }
        if signals.contains(.dietary) {
            lines.append("Dietary detail needs checking.")
        }
        if signals.contains(.accessibility) {
            lines.append("Accessibility detail needs checking.")
        }
        if signals.contains(.returningGuest) {
            lines.append("Returning guest context available.")
        }
        if signals.contains(.noTable) {
            lines.append("No table assigned.")
        }
        if signals.contains(.confirmationMissing) {
            lines.append("Confirmation has not been recorded.")
        }
        if signals.contains(.reminderMissing) {
            lines.append("Reminder has not been recorded.")
        }
        if signals.contains(.largeParty) {
            lines.append("Large party.")
        }
        if signals.contains(.seatedTooLong) {
            lines.append("Seated-time check may be needed.")
        }
        return lines.prefix(3).joined(separator: " ")
    }

    private static func safeGuestDisplayName(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for blocked in ["vip", "regular"] {
            trimmed = trimmed.replacingOccurrences(
                of: #"\b\#(blocked)\b"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        trimmed = trimmed.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Guest" : trimmed
    }

    private static func shouldSuggestConfirmation(for reservation: ReservationRecord) -> Bool {
        guard reservation.hasUsableConfirmationEmail,
              !reservation.hasConfirmationEmailRecord else {
            return false
        }
        switch reservation.statusValue {
        case .new, .needsReview, .confirmed:
            return true
        case .seated, .completed, .cancelled, .noShow:
            return false
        }
    }

    private static func shouldSuggestReminder(for reservation: ReservationRecord, now: Date) -> Bool {
        guard reservation.hasUsableConfirmationEmail,
              reservation.statusValue == .confirmed,
              reservation.reminderEmailSentAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
            return false
        }
        switch reservation.operationalTimingState(now: now) {
        case .dueSoon, .dueNow:
            return true
        case .none, .normal, .overdue:
            return false
        }
    }

    private static func highest(_ lhs: HostSeverity, _ rhs: HostSeverity) -> HostSeverity {
        lhs.rank <= rhs.rank ? lhs : rhs
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
