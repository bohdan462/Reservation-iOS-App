//
//  HostServiceBriefingPacketBuilder.swift
//  Tryzub Reservations
//
//  Builds the parent service briefing packet from already-available local/cache
//  intelligence. No network, no LLM, no SwiftUI ownership.
//

import Foundation

enum HostServiceBriefingPacketBuilder {

    struct Input {
        let now: Date
        let selectedDate: Date
        let dateKey: String
        let serviceMode: ServiceMode
        let dayReservations: [ReservationRecord]
        let historyReservations: [ReservationRecord]
        let serviceSnapshot: HostServiceIntelligenceSnapshot
        let decisionSnapshot: HostDecisionSnapshot
        let boardSnapshot: HostBoardSnapshot?
        let localSeatedAtByReservationID: [Int: Date]
        let effectiveTableAssignments: [EffectiveReservationTableAssignment]
        let analyticsSummary: ReservationAnalyticsSummaryDTO?
        let sourceFingerprint: String

        init(
            now: Date,
            selectedDate: Date,
            dateKey: String,
            serviceMode: ServiceMode,
            dayReservations: [ReservationRecord],
            historyReservations: [ReservationRecord],
            serviceSnapshot: HostServiceIntelligenceSnapshot,
            decisionSnapshot: HostDecisionSnapshot,
            boardSnapshot: HostBoardSnapshot? = nil,
            localSeatedAtByReservationID: [Int: Date],
            effectiveTableAssignments: [EffectiveReservationTableAssignment] = [],
            analyticsSummary: ReservationAnalyticsSummaryDTO? = nil,
            sourceFingerprint: String
        ) {
            self.now = now
            self.selectedDate = selectedDate
            self.dateKey = dateKey
            self.serviceMode = serviceMode
            self.dayReservations = dayReservations
            self.historyReservations = historyReservations
            self.serviceSnapshot = serviceSnapshot
            self.decisionSnapshot = decisionSnapshot
            self.boardSnapshot = boardSnapshot
            self.localSeatedAtByReservationID = localSeatedAtByReservationID
            self.effectiveTableAssignments = effectiveTableAssignments
            self.analyticsSummary = analyticsSummary
            self.sourceFingerprint = sourceFingerprint
        }
    }

    static func build(_ input: Input) -> HostServiceBriefingPacket {
        let fingerprint = inputFingerprint(input)
        let assignmentsByReservationID = ReservationTableTruth.assignmentsByReservationID(
            input.effectiveTableAssignments
        )
        let reservationsByID = Dictionary(
            input.dayReservations.map { ($0.remoteID, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let activeReservations = input.dayReservations.filter(\.isHostBoardOperational)
        let waiting = activeReservations.filter { reservation in
            switch reservation.statusValue {
            case .new, .needsReview, .confirmed:
                guard let serviceDate = serviceDateTime(for: reservation) else { return false }
                return serviceDate <= input.now
            case .seated, .completed, .cancelled, .noShow:
                return false
            }
        }
        let completed = input.dayReservations.filter { $0.statusValue == .completed }
        let walkInCompleted = completed.filter { $0.sourceTypeValue == .manualWalkIn }
        let noShows = input.dayReservations.filter { $0.statusValue == .noShow }
        let noTableCount = activeReservations.filter { reservation in
            switch reservation.statusValue {
            case .new, .needsReview, .confirmed:
                return !ReservationTableTruth.hasEffectiveTableAssignment(
                    for: reservation,
                    assignmentsByReservationID: assignmentsByReservationID
                )
            case .seated, .completed, .cancelled, .noShow:
                return false
            }
        }.count

        let newGuestCount = supportedNewGuestCount(
            dayReservations: activeReservations,
            historyReservations: input.historyReservations
        )
        let counts = BriefingTruthCounts(
            activeReservations: activeReservations.count,
            expectedGuests: activeReservations.reduce(0) { $0 + $1.partySize },
            seatedReservations: activeReservations.filter { $0.statusValue == .seated }.count,
            waitingArrivals: waiting.count,
            noTable: noTableCount,
            completedReservations: completed.count,
            walkInCompleted: walkInCompleted.count,
            noShows: noShows.count,
            newGuests: newGuestCount
        )

        var facts: [BriefingFact] = []
        var semanticIndexByKey: [String: Int] = [:]
        var attemptedFactCount = 0
        var duplicatesRemoved = 0

        func add(_ fact: BriefingFact) {
            attemptedFactCount += 1
            let key = semanticKey(for: fact, dateKey: input.dateKey)
            if let existingIndex = semanticIndexByKey[key] {
                duplicatesRemoved += 1
                if fact.priority > facts[existingIndex].priority {
                    facts[existingIndex] = fact
                }
                return
            }
            semanticIndexByKey[key] = facts.count
            facts.append(fact)
        }

        if activeReservations.isEmpty && completed.isEmpty && noShows.isEmpty {
            add(BriefingFact(id: "calm-\(input.dateKey)", kind: .serviceCalm, priority: 5))
        } else {
            add(
                BriefingFact(
                    id: "overview-\(input.dateKey)",
                    kind: .dayOverview,
                    count: activeReservations.count,
                    secondaryCount: activeReservations.reduce(0) { $0 + $1.partySize },
                    priority: 40
                )
            )
        }

        if let busiest = input.decisionSnapshot.slotPressures.max(by: {
            ($0.guestCount, $0.reservationCount) < ($1.guestCount, $1.reservationCount)
        }), busiest.reservationCount > 0 {
            add(
                BriefingFact(
                    id: "arrival-window-\(input.dateKey)-\(busiest.slotTime)",
                    kind: .arrivalWindow,
                    timeLabel: displayTime(busiest.slotTime),
                    count: busiest.reservationCount,
                    secondaryCount: busiest.guestCount,
                    priority: 68
                )
            )
        }

        if let next = nextArrival(from: activeReservations, now: input.now) {
            add(
                BriefingFact(
                    id: "next-\(next.remoteID)",
                    kind: .nextArrival,
                    reservationID: next.remoteID,
                    guestName: next.guestName,
                    partySize: next.partySize,
                    timeLabel: displayTime(next.reservationTime),
                    tableLabel: ReservationTableTruth.effectiveTableLabel(
                        for: next,
                        assignmentsByReservationID: assignmentsByReservationID
                    ),
                    priority: 72
                )
            )
        }

        if counts.seatedReservations > 0 {
            add(
                BriefingFact(
                    id: "seated-overview-\(input.dateKey)",
                    kind: .seatedOverview,
                    count: counts.seatedReservations,
                    priority: 50
                )
            )
        }

        for reservation in activeReservations where reservation.statusValue == .seated {
            guard let seatedAt = input.localSeatedAtByReservationID[reservation.remoteID] else { continue }
            let minutes = max(1, Int(input.now.timeIntervalSince(seatedAt) / 60))
            guard let table = ReservationTableTruth.effectiveTableLabel(
                for: reservation,
                assignmentsByReservationID: assignmentsByReservationID
            ) else { continue }
            add(
                BriefingFact(
                    id: "seated-duration-\(reservation.remoteID)",
                    kind: .seatedDuration,
                    reservationID: reservation.remoteID,
                    guestName: reservation.guestName,
                    partySize: reservation.partySize,
                    tableLabel: table,
                    minutes: minutes,
                    priority: minutes >= 90 ? 82 : 54
                )
            )
        }

        if waiting.count > 0 {
            add(
                BriefingFact(
                    id: "waiting-\(input.dateKey)",
                    kind: .waitingArrivals,
                    count: waiting.count,
                    priority: 74
                )
            )
        }

        if noTableCount > 0 {
            add(
                BriefingFact(
                    id: "no-table-\(input.dateKey)",
                    kind: .noTableToday,
                    count: noTableCount,
                    priority: 64
                )
            )
        }

        if let newGuestCount, newGuestCount > 0 {
            add(
                BriefingFact(
                    id: "new-guests-\(input.dateKey)",
                    kind: .newGuestCount,
                    count: newGuestCount,
                    priority: 35
                )
            )
        }

        for fact in input.serviceSnapshot.rankedFacts {
            guard let kind = mappedFactKind(for: fact),
                  let reservation = fact.reservationID.flatMap({ reservationsByID[$0] }) else {
                if let kind = mappedDayFactKind(for: fact) {
                    if kind == .arrivalWindow, facts.contains(where: { $0.kind == .arrivalWindow }) {
                        continue
                    }
                    add(
                        BriefingFact(
                            id: "canonical-\(fact.id)",
                            kind: kind,
                            count: countFromSnapshotFact(fact),
                            priority: fact.priority
                        )
                    )
                }
                continue
            }
            let memoryLastVisit = kind == .guestMemory
                ? guestMemoryLastVisitDisplay(from: fact)
                : nil
            add(
                BriefingFact(
                    id: "canonical-\(fact.id)",
                    kind: kind,
                    reservationID: reservation.remoteID,
                    guestName: reservation.guestName,
                    partySize: reservation.partySize,
                    timeLabel: memoryLastVisit ?? displayTime(reservation.reservationTime),
                    tableLabel: ReservationTableTruth.effectiveTableLabel(
                        for: reservation,
                        assignmentsByReservationID: assignmentsByReservationID
                    ),
                    priority: fact.priority
                )
            )
        }

        for signal in input.decisionSnapshot.tableSignals {
            guard let kind = tableFactKind(for: signal) else { continue }
            add(
                BriefingFact(
                    id: "table-\(signal.id)",
                    kind: kind,
                    tableLabel: safeTableLabel(signal.tableName),
                    priority: tablePriority(signal.severity)
                )
            )
        }

        if completed.count > 0 {
            add(
                BriefingFact(
                    id: "completed-\(input.dateKey)",
                    kind: .completedRecap,
                    count: completed.count,
                    secondaryCount: walkInCompleted.count,
                    priority: input.serviceMode == .afterCloseFinished ? 58 : 28
                )
            )
        }

        if walkInCompleted.count > 0 {
            add(
                BriefingFact(
                    id: "walkins-\(input.dateKey)",
                    kind: .walkInCompleted,
                    count: walkInCompleted.count,
                    priority: 30
                )
            )
        }

        if noShows.count > 0 {
            add(
                BriefingFact(
                    id: "noshows-\(input.dateKey)",
                    kind: .noShowFollowUp,
                    count: noShows.count,
                    priority: 36
                )
            )
        }

        let longStayCount = facts.filter { $0.kind == .seatedDuration && ($0.minutes ?? 0) >= 90 }.count
        if longStayCount > 0 {
            add(
                BriefingFact(
                    id: "long-stay-\(input.dateKey)",
                    kind: .longStayRecap,
                    count: longStayCount,
                    priority: 46
                )
            )
        }

        if let peak = input.analyticsSummary?.byHour.max(by: {
            if $0.reservationsCount == $1.reservationsCount {
                return $0.guestsCount < $1.guestsCount
            }
            return $0.reservationsCount < $1.reservationsCount
        }), peak.reservationsCount > 0 {
            add(
                BriefingFact(
                    id: "business-peak-\(peak.hour)",
                    kind: .businessPeak,
                    timeLabel: displayTime(peak.hour),
                    count: peak.reservationsCount,
                    secondaryCount: peak.guestsCount,
                    priority: 18
                )
            )
        }

        // TODO: Add activity-history facts when a day activity snapshot is already
        // available to this builder without warming or fetching.
        // TODO: Add richer backend business intelligence once Host owns the cached
        // BusinessIntelligenceSummaryDTO input.
        // TODO: Add attachment-specific deposit/preorder/setup facts from typed
        // attachment metadata when those categories are passed directly to this builder.

        let sortedFacts = displaySortedFacts(facts, serviceMode: input.serviceMode)
        let presentation = HostServiceBriefingTemplateWriter.presentation(
            for: sortedFacts,
            dateKey: input.dateKey,
            serviceMode: input.serviceMode,
            truthCounts: counts,
            now: input.now
        )
        #if DEBUG
        print("[SERVICE_BRIEFING_PRESENTATION_TRACE] factsBefore=\(attemptedFactCount) factsAfter=\(sortedFacts.count) duplicatesRemoved=\(duplicatesRemoved) compact=\"\(presentation.compactLine)\"")
        #endif
        let guestNames = Set(input.dayReservations.map(\.guestName) + sortedFacts.compactMap(\.guestName))
        let tableLabels = Set(
            input.dayReservations.compactMap {
                ReservationTableTruth.effectiveTableLabel(
                    for: $0,
                    assignmentsByReservationID: assignmentsByReservationID
                )
            } + sortedFacts.compactMap(\.tableLabel)
        )

        return HostServiceBriefingPacket(
            dateKey: input.dateKey,
            serviceMode: input.serviceMode,
            generatedAt: input.now,
            inputFingerprint: fingerprint,
            truthCounts: counts,
            allowedGuestNames: guestNames.sorted(),
            allowedTableLabels: tableLabels.sorted(),
            compactLine: presentation.compactLine,
            compactChips: presentation.compactChips,
            sections: presentation.sections,
            facts: sortedFacts
        )
    }

    static func inputFingerprint(_ input: Input) -> String {
        let seatedStamp = input.localSeatedAtByReservationID
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(Int($0.value.timeIntervalSince1970))" }
            .joined(separator: ",")
        let boardStamp = input.boardSnapshot.map {
            [
                "\($0.upcoming.count)",
                "\($0.seated.count)",
                "\($0.noTableCount)",
                "\($0.expectedGuestCount)",
                $0.nextReservationText ?? "none",
                $0.peakTimeText
            ].joined(separator: ":")
        } ?? "board:none"
        let analyticsStamp = input.analyticsSummary.map {
            "\($0.byHour.count):\($0.summary?.reservationsCount ?? 0):\($0.summary?.guestsCount ?? 0)"
        } ?? "analytics:none"
        let minuteStamp = shouldRefreshByMinute(input)
            ? "minute:\(Int(input.now.timeIntervalSince1970 / 60))"
            : "minute:stable"
        let raw = [
            input.dateKey,
            input.serviceMode.rawValue,
            input.sourceFingerprint,
            input.serviceSnapshot.inputFingerprint,
            "\(Int(input.decisionSnapshot.generatedAt.timeIntervalSince1970))",
            ReservationTableTruth.assignmentFingerprint(from: input.effectiveTableAssignments),
            seatedStamp,
            minuteStamp,
            boardStamp,
            analyticsStamp
        ].joined(separator: "|")
        return HostAttentionStableDigest.hexDigest(raw)
    }

    private static func shouldRefreshByMinute(_ input: Input) -> Bool {
        if input.serviceMode == .duringService {
            return true
        }
        return input.dayReservations.contains { reservation in
            reservation.statusValue == .seated
                && input.localSeatedAtByReservationID[reservation.remoteID] != nil
        }
    }

    private static func semanticKey(for fact: BriefingFact, dateKey: String) -> String {
        if fact.kind == .noTableToday {
            return "\(fact.kind.rawValue):\(dateKey)"
        }
        if fact.kind == .arrivalWindow {
            return "\(fact.kind.rawValue):\(dateKey)"
        }
        if fact.kind == .reminder || fact.kind == .confirmation || fact.kind == .newGuestCount || fact.kind == .dayOverview {
            return "\(fact.kind.rawValue):\(dateKey)"
        }
        if let reservationID = fact.reservationID {
            return "\(fact.kind.rawValue):reservation:\(reservationID)"
        }
        if let tableLabel = fact.tableLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !tableLabel.isEmpty {
            return "\(fact.kind.rawValue):table:\(tableLabel.lowercased())"
        }
        if let timeLabel = fact.timeLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !timeLabel.isEmpty {
            return "\(fact.kind.rawValue):\(dateKey):\(timeLabel.lowercased())"
        }
        return "\(fact.kind.rawValue):\(dateKey):\(fact.id)"
    }

    private static func displaySortedFacts(_ facts: [BriefingFact], serviceMode: ServiceMode) -> [BriefingFact] {
        facts.sorted {
            let leftRank = displayRank(for: $0.kind, serviceMode: serviceMode)
            let rightRank = displayRank(for: $1.kind, serviceMode: serviceMode)
            if leftRank != rightRank { return leftRank < rightRank }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.id < $1.id
        }
    }

    private static func displayRank(for kind: BriefingFactKind, serviceMode: ServiceMode) -> Int {
        switch serviceMode {
        case .futurePlanning, .beforeService:
            switch kind {
            case .noTableToday: return 10
            case .nextArrival, .timedArrival: return 20
            case .arrivalWindow: return 30
            case .reminder, .confirmation: return 40
            case .occasion, .allergy, .seatingPreference, .guestMemory: return 50
            case .newGuestCount: return 60
            case .dayOverview: return 70
            default: return 90
            }
        case .duringService, .afterCloseNeedsCleanup:
            switch kind {
            case .waitingArrivals: return 10
            case .noTableToday: return 20
            case .seatedDuration, .tableWatch: return 30
            case .allergy, .occasion, .seatingPreference: return 40
            case .nextArrival, .timedArrival: return 50
            case .reminder, .confirmation: return 60
            case .dayOverview: return 70
            default: return 90
            }
        case .afterCloseFinished, .pastRecap:
            switch kind {
            case .completedRecap: return 10
            case .walkInCompleted: return 20
            case .noShowFollowUp: return 30
            case .longStayRecap: return 40
            case .guestMemory, .occasion, .allergy, .seatingPreference: return 50
            case .businessPeak: return 60
            default: return 90
            }
        }
    }

    private static func mappedFactKind(for fact: ServiceIntelligenceFact) -> BriefingFactKind? {
        switch fact.category {
        case .allergy:
            return .allergy
        case .occasion:
            return .occasion
        case .accessibility, .guestNote:
            return .seatingPreference
        case .returningGuest, .regularGuest:
            return .guestMemory
        case .attachment:
            return attachmentKind(from: fact)
        case .largeParty:
            return .setup
        case .staffNote:
            return safeStaffNoteKind(from: fact)
        case .mainWave, .reminder, .confirmation, .noTable, .cancellationNoShow:
            return nil
        }
    }

    private static func mappedDayFactKind(for fact: ServiceIntelligenceFact) -> BriefingFactKind? {
        switch fact.category {
        case .mainWave:
            return .arrivalWindow
        case .reminder:
            return .reminder
        case .confirmation:
            return .confirmation
        case .noTable:
            return .noTableToday
        case .cancellationNoShow:
            return .noShowFollowUp
        case .allergy, .staffNote, .attachment, .accessibility, .occasion,
             .returningGuest, .regularGuest, .guestNote, .largeParty:
            return nil
        }
    }

    private static func attachmentKind(from fact: ServiceIntelligenceFact) -> BriefingFactKind {
        let raw = [fact.id, fact.headline, fact.detail ?? ""]
            .joined(separator: " ")
            .lowercased()
        if raw.contains("deposit") {
            return .deposit
        }
        if raw.contains("preorder") || raw.contains("pre-order") {
            return .preorder
        }
        return .setup
    }

    private static func safeStaffNoteKind(from fact: ServiceIntelligenceFact) -> BriefingFactKind? {
        guard fact.reservationID != nil else { return nil }
        let raw = [fact.id, fact.headline, fact.detail ?? ""]
            .joined(separator: " ")
            .lowercased()
        if raw.contains("deposit") {
            return .deposit
        }
        if raw.contains("preorder") || raw.contains("pre-order") || raw.contains("pre order") {
            return .preorder
        }
        if raw.contains("setup") || raw.contains("set up") || raw.contains("banquet") || raw.contains("private") {
            return .setup
        }
        if raw.contains("quiet") || raw.contains("booth") || raw.contains("window")
            || raw.contains("patio") || raw.contains("seating") || raw.contains("seat") {
            return .seatingPreference
        }
        // TODO: Add a neutral staff-note packet kind if product wants safe generic
        // note presence without classifying it as setup, preorder, deposit, or seating.
        return nil
    }

    private static func tableFactKind(for signal: HostTableSignal) -> BriefingFactKind? {
        switch signal.kind {
        case .tableTurnRisk, .doubleBookedTable, .tableCapacityMismatch, .longSeated, .tableFreed:
            return .tableWatch
        case .noTableAssigned:
            return .noTableToday
        case .cancellationFreedTable, .unknown:
            return nil
        }
    }

    private static func tablePriority(_ severity: HostSeverity) -> Int {
        switch severity {
        case .critical:
            return 88
        case .warning:
            return 78
        case .watch:
            return 62
        case .info:
            return 32
        }
    }

    private static func countFromSnapshotFact(_ fact: ServiceIntelligenceFact) -> Int? {
        let text = [fact.headline, fact.detail ?? ""].joined(separator: " ")
        let token = text.split(separator: " ").first.flatMap { Int($0) }
        return token
    }

    private static func guestMemoryLastVisitDisplay(from fact: ServiceIntelligenceFact) -> String? {
        let text = [fact.headline, fact.detail ?? ""].joined(separator: " ")
        let marker = "Last visit "
        guard let range = text.range(of: marker, options: [.caseInsensitive]) else {
            return nil
        }
        let suffix = text[range.upperBound...]
        let terminators: [Character] = [".", "·", "\n"]
        let value = String(suffix.prefix { !terminators.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func supportedNewGuestCount(
        dayReservations: [ReservationRecord],
        historyReservations: [ReservationRecord]
    ) -> Int? {
        let dayIDs = Set(dayReservations.map(\.remoteID))
        let hasPastRows = historyReservations.contains { reservation in
            !dayIDs.contains(reservation.remoteID)
        }
        guard hasPastRows else { return nil }
        return dayReservations.reduce(0) { count, reservation in
            let truth = GuestOperationalTruth.evaluate(
                surface: "service_briefing_packet",
                selected: reservation,
                reservationPool: historyReservations,
                summary: nil
            )
            return count + (truth.seenBefore ? 0 : 1)
        }
    }

    private static func nextArrival(from reservations: [ReservationRecord], now: Date) -> ReservationRecord? {
        reservations
            .filter {
                switch $0.statusValue {
                case .new, .needsReview, .confirmed:
                    return serviceDateTime(for: $0) != nil
                case .seated, .completed, .cancelled, .noShow:
                    return false
                }
            }
            .sorted {
                (serviceDateTime(for: $0) ?? .distantFuture) < (serviceDateTime(for: $1) ?? .distantFuture)
            }
            .first { reservation in
                guard let date = serviceDateTime(for: reservation) else { return false }
                return date >= now.addingTimeInterval(-15 * 60)
            }
    }

    private static func serviceDateTime(for reservation: ReservationRecord) -> Date? {
        let rawTime = reservation.reservationTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reservation.reservationDate.isEmpty, !rawTime.isEmpty else { return nil }
        if let date = ReservationFormatters.serverDateTime.date(from: "\(reservation.reservationDate) \(rawTime)") {
            return date
        }
        let minuteTime = rawTime.count >= 5 ? String(rawTime.prefix(5)) : rawTime
        return ReservationFormatters.serverDateMinute.date(from: "\(reservation.reservationDate) \(minuteTime)")
    }

    private static func displayTime(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let minuteTime = trimmed.count >= 5 ? String(trimmed.prefix(5)) : trimmed
        if let date = ReservationFormatters.serverDateTime.date(from: "2000-01-01 \(trimmed)") {
            return ReservationFormatters.shortTime.string(from: date)
        }
        if let date = ReservationFormatters.serverDateMinute.date(from: "2000-01-01 \(minuteTime)") {
            return ReservationFormatters.shortTime.string(from: date)
        }
        return minuteTime
    }

    private static func safeTableLabel(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
