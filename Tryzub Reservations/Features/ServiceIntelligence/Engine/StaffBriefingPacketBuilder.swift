//
//  StaffBriefingPacketBuilder.swift
//  Tryzub Reservations
//
//  4F-1 — Builds a safe StaffBriefingPacket from already-computed deterministic
//  sources. Pure and deterministic: no network, no LLM, no mutations.
//
//  Fact sources (all safe):
//   - HostServiceBriefingPacket   → priority facts, truthCounts, allowlists
//   - day reservations            → deterministic status histogram + comms counts
//   - NoteSignalAnalyzer          → safe attachment tags (no raw note/OCR text)
//   - tomorrow reservations       → best-effort tomorrow preview counts
//   - pre-rendered business lines  → optional safe context
//
//  The packet never contains raw notes, OCR, emails, phones, or ReservationRecord.
//

import Foundation

enum StaffBriefingPacketBuilder {

    static let promptVersion = StaffBriefingPromptBuilder.promptVersion

    /// Fact cap to keep the prompt within the runtime context window.
    static let normalFactCap = 30
    static let busyFactCap = 40
    /// Active-reservation threshold above which the day is treated as "busy".
    static let busyThreshold = 15

    // MARK: - Input

    struct Input {
        let mode: StaffBriefingMode
        let dateKey: String
        let now: Date
        let serviceMode: ServiceMode
        let sourceFingerprint: String
        /// Compact packet — the safe fact + allowlist source of truth.
        let servicePacket: HostServiceBriefingPacket
        /// Day-filtered reservations for the selected date (deterministic counts only).
        let dayReservations: [ReservationRecord]
        /// Best-effort next-day reservations for closingRecap preview. May be empty.
        let tomorrowReservations: [ReservationRecord]
        /// Pre-rendered safe business insight lines (never raw backend JSON).
        let businessSummaryLines: [String]
        /// Large-party threshold from settings.
        let largePartyThreshold: Int

        init(
            mode: StaffBriefingMode,
            dateKey: String,
            now: Date,
            serviceMode: ServiceMode,
            sourceFingerprint: String,
            servicePacket: HostServiceBriefingPacket,
            dayReservations: [ReservationRecord],
            tomorrowReservations: [ReservationRecord] = [],
            businessSummaryLines: [String] = [],
            largePartyThreshold: Int = 7
        ) {
            self.mode = mode
            self.dateKey = dateKey
            self.now = now
            self.serviceMode = serviceMode
            self.sourceFingerprint = sourceFingerprint
            self.servicePacket = servicePacket
            self.dayReservations = dayReservations
            self.tomorrowReservations = tomorrowReservations
            self.businessSummaryLines = businessSummaryLines
            self.largePartyThreshold = largePartyThreshold
        }
    }

    // MARK: - Build

    static func build(_ input: Input) -> StaffBriefingPacket {
        let statusCounts = buildStatusCounts(
            reservations: input.dayReservations,
            expectedGuestsFallback: input.servicePacket.truthCounts.expectedGuests,
            serviceMode: input.serviceMode
        )
        let allowedNames = Set(input.servicePacket.allowedGuestNames)
        let attachmentSummaries = buildAttachmentSummaries(
            reservations: input.dayReservations,
            servicePacket: input.servicePacket,
            allowedNames: allowedNames
        )
        let communication = buildCommunicationSummary(reservations: input.dayReservations)
        let tomorrowPreview = input.mode == .closingRecap
            ? buildTomorrowPreview(
                reservations: input.tomorrowReservations,
                dateKey: nextDateKey(after: input.dateKey),
                largePartyThreshold: input.largePartyThreshold
              )
            : nil

        let isBusy = statusCounts.activeCount >= busyThreshold
        let cap = isBusy ? busyFactCap : normalFactCap
        let priorityFacts = rankFacts(
            input.servicePacket.facts,
            mode: input.mode,
            cap: cap
        )

        let serviceStateLabel = stateLabel(for: input.serviceMode)
        let fingerprint = buildFingerprint(
            input: input,
            statusCounts: statusCounts,
            communication: communication,
            tomorrowPreview: tomorrowPreview,
            factCount: priorityFacts.count
        )

        return StaffBriefingPacket(
            mode: input.mode,
            dateKey: input.dateKey,
            requestedAt: input.now,
            serviceMode: input.serviceMode,
            serviceStateLabel: serviceStateLabel,
            inputFingerprint: fingerprint,
            sourceFingerprint: input.sourceFingerprint,
            promptVersion: promptVersion,
            truthCounts: input.servicePacket.truthCounts,
            statusCounts: statusCounts,
            priorityFacts: priorityFacts,
            allowedGuestNames: input.servicePacket.allowedGuestNames,
            allowedTableLabels: input.servicePacket.allowedTableLabels,
            attachmentSummaries: attachmentSummaries,
            communicationSummary: communication,
            businessSummaryLines: input.businessSummaryLines,
            tomorrowPreview: tomorrowPreview
        )
    }

    // MARK: - Status counts

    static func buildStatusCounts(
        reservations: [ReservationRecord],
        expectedGuestsFallback: Int,
        serviceMode: ServiceMode
    ) -> StaffBriefingStatusCounts {
        var newCount = 0, needsReview = 0, confirmed = 0, seated = 0
        var completed = 0, cancelled = 0, noShow = 0
        var seatedGuests = 0
        var operationalGuests = 0

        for reservation in reservations where !reservation.isHidden {
            switch reservation.statusValue {
            case .new:
                newCount += 1
                operationalGuests += reservation.partySize
            case .needsReview:
                needsReview += 1
                operationalGuests += reservation.partySize
            case .confirmed:
                confirmed += 1
                operationalGuests += reservation.partySize
            case .seated:
                seated += 1
                seatedGuests += reservation.partySize
                operationalGuests += reservation.partySize
            case .completed:
                completed += 1
            case .cancelled:
                cancelled += 1
            case .noShow:
                noShow += 1
            }
        }

        let total = reservations.filter { !$0.isHidden }.count
        let active = newCount + needsReview + confirmed + seated
        let remainingArrivals = newCount + needsReview + confirmed
        let expectedGuests = operationalGuests > 0 ? operationalGuests : expectedGuestsFallback
        // Unresolved: after close, open + seated still need a status decision.
        let unresolved: Int
        switch serviceMode {
        case .afterCloseNeedsCleanup, .afterCloseFinished, .pastRecap:
            unresolved = remainingArrivals + seated
        case .beforeService, .duringService, .futurePlanning:
            unresolved = needsReview
        }

        return StaffBriefingStatusCounts(
            totalReservations: total,
            expectedGuests: expectedGuests,
            newCount: newCount,
            needsReviewCount: needsReview,
            confirmedCount: confirmed,
            seatedCount: seated,
            completedCount: completed,
            cancelledCount: cancelled,
            noShowCount: noShow,
            activeCount: active,
            remainingArrivalsCount: remainingArrivals,
            currentlySeatedGuests: seatedGuests,
            stillSeatedReservations: seated,
            unresolvedCount: unresolved
        )
    }

    // MARK: - Attachments

    private static func buildAttachmentSummaries(
        reservations: [ReservationRecord],
        servicePacket: HostServiceBriefingPacket,
        allowedNames: Set<String>
    ) -> [StaffBriefingAttachmentSummary] {
        var byReservation: [Int: (name: String?, time: String?, tags: Set<StaffBriefingAttachmentTag>)] = [:]

        // Source 1: deterministic note signals (safe — tags only, never raw text).
        for reservation in reservations where reservation.isHostBoardOperational {
            let signals = NoteSignalAnalyzer.analyze(
                NoteSignalAnalyzer.Input(
                    reservationID: String(reservation.remoteID),
                    guestNote: reservation.guestNotes,
                    staffNote: reservation.staffNotes
                )
            )
            let tags = attachmentTags(from: signals)
            guard !tags.isEmpty else { continue }
            let name = allowedNames.contains(reservation.guestName) ? reservation.guestName : nil
            byReservation[reservation.remoteID, default: (name, displayTime(reservation.reservationTime), [])]
                .tags.formUnion(tags)
        }

        // Source 2: packet facts already reduced to safe attachment kinds.
        for fact in servicePacket.facts {
            guard let tag = tag(for: fact.kind), let id = fact.reservationID else { continue }
            let name = fact.guestName.flatMap { allowedNames.contains($0) ? $0 : nil }
            byReservation[id, default: (name, fact.timeLabel, [])].tags.insert(tag)
        }

        return byReservation
            .sorted { $0.key < $1.key }
            .map { id, value in
                StaffBriefingAttachmentSummary(
                    id: String(id),
                    guestName: value.name,
                    timeLabel: value.time,
                    tags: value.tags.sorted { $0.rawValue < $1.rawValue },
                    reviewNeeded: value.tags.contains(.deposit) || value.tags.contains(.preorder)
                        || value.tags.contains(.banquet) || value.tags.contains(.setup)
                )
            }
    }

    private static func attachmentTags(from signals: [ReservationSignal]) -> Set<StaffBriefingAttachmentTag> {
        var tags: Set<StaffBriefingAttachmentTag> = []
        for signal in signals {
            switch signal.type {
            case .depositMentioned, .depositVerified: tags.insert(.deposit)
            case .preorderMentioned: tags.insert(.preorder)
            case .banquetMentioned: tags.insert(.banquet)
            case .setupNeeded: tags.insert(.setup)
            case .attachmentNeedsReview: tags.insert(.other)
            default: break
            }
        }
        return tags
    }

    private static func tag(for kind: BriefingFactKind) -> StaffBriefingAttachmentTag? {
        switch kind {
        case .deposit: return .deposit
        case .preorder: return .preorder
        case .setup: return .setup
        default: return nil
        }
    }

    // MARK: - Communication

    private static func buildCommunicationSummary(
        reservations: [ReservationRecord]
    ) -> StaffBriefingCommunicationSummary {
        var confirmMissing = 0, confirmSent = 0, remindMissing = 0, remindSent = 0
        var confirmDelivered = 0, confirmPending = 0, confirmFailed = 0, confirmNeedsCorrection = 0
        var reminderDelivered = 0, reminderPending = 0, reminderFailed = 0, reminderNeedsCorrection = 0
        for reservation in reservations where !reservation.isHidden {
            let operationalPreArrival = reservation.statusValue == .new
                || reservation.statusValue == .needsReview
                || reservation.statusValue == .confirmed

            if reservation.hasConfirmationEmailRecord {
                confirmSent += 1
                switch reservation.confirmationDeliveryStatus {
                case .delivered:
                    confirmDelivered += 1
                case .pendingDelivery, .sentToProvider, .deliveryDelayed:
                    confirmPending += 1
                case .failed, .suppressed, .complained:
                    confirmFailed += 1
                case .notApplicable, .deliveryUnknown, .legacyRecorded, .manualRecorded, .unknown:
                    break
                }
            } else if operationalPreArrival,
                      reservation.confirmedAt?.nilIfBlank == nil,
                      reservation.statusValue != .confirmed {
                confirmMissing += 1
            }
            if reservation.needsEmailCorrection {
                confirmNeedsCorrection += 1
            }

            if reservation.hasReminderEmailRecord {
                remindSent += 1
                switch reservation.reminderDeliveryStatus {
                case .delivered:
                    reminderDelivered += 1
                case .pendingDelivery, .sentToProvider, .deliveryDelayed:
                    reminderPending += 1
                case .failed, .suppressed, .complained:
                    reminderFailed += 1
                case .notApplicable, .deliveryUnknown, .legacyRecorded, .manualRecorded, .unknown:
                    break
                }
            } else if operationalPreArrival {
                remindMissing += 1
            }
            if reservation.needsReminderCorrection {
                reminderNeedsCorrection += 1
            }
        }
        return StaffBriefingCommunicationSummary(
            confirmationsMissingCount: confirmMissing,
            confirmationsSentCount: confirmSent > 0 ? confirmSent : nil,
            confirmationDeliveredCount: confirmDelivered,
            confirmationPendingDeliveryCount: confirmPending,
            confirmationFailedDeliveryCount: confirmFailed,
            confirmationNeedsCorrectionCount: confirmNeedsCorrection,
            remindersMissingCount: remindMissing,
            remindersSentCount: remindSent > 0 ? remindSent : nil,
            reminderDeliveredCount: reminderDelivered,
            reminderPendingDeliveryCount: reminderPending,
            reminderFailedDeliveryCount: reminderFailed,
            reminderNeedsCorrectionCount: reminderNeedsCorrection,
            // Not reliably derivable from local deterministic metadata — never faked.
            autoConfirmedCount: nil
        )
    }

    // MARK: - Tomorrow preview

    private static func buildTomorrowPreview(
        reservations: [ReservationRecord],
        dateKey: String,
        largePartyThreshold: Int
    ) -> StaffBriefingTomorrowPreview? {
        let operational = reservations.filter { !$0.isHidden && $0.isHostBoardOperational }
        guard !operational.isEmpty else {
            return StaffBriefingTomorrowPreview(
                dateKey: dateKey, reservationCount: 0, expectedGuests: 0,
                needsReviewCount: 0, noTableCount: 0, largePartyCount: 0,
                attachmentCount: 0, allergyCount: 0, occasionCount: 0,
                regularGuestCount: 0, priorityFacts: [], hasData: false
            )
        }

        let expectedGuests = operational.reduce(0) { $0 + $1.partySize }
        let needsReview = operational.filter { $0.statusValue == .needsReview }.count
        let noTable = operational.filter { ($0.tableName?.nilIfBlank) == nil }.count
        let largeParty = operational.filter { $0.partySize >= largePartyThreshold }.count

        var attachment = 0, allergy = 0, occasion = 0
        for reservation in operational {
            let signals = NoteSignalAnalyzer.analyze(
                NoteSignalAnalyzer.Input(
                    reservationID: String(reservation.remoteID),
                    guestNote: reservation.guestNotes,
                    staffNote: reservation.staffNotes
                )
            )
            if signals.contains(where: { $0.type == .allergyOrDietary }) { allergy += 1 }
            if signals.contains(where: { $0.type == .occasion }) { occasion += 1 }
            if signals.contains(where: {
                $0.type == .depositMentioned || $0.type == .preorderMentioned
                    || $0.type == .banquetMentioned || $0.type == .setupNeeded
            }) { attachment += 1 }
        }

        var facts: [BriefingFact] = []
        if largeParty > 0 {
            facts.append(BriefingFact(id: "tom-large", kind: .setup, count: largeParty, priority: 60))
        }
        if noTable > 0 {
            facts.append(BriefingFact(id: "tom-notable", kind: .noTableToday, count: noTable, priority: 55))
        }
        if allergy > 0 {
            facts.append(BriefingFact(id: "tom-allergy", kind: .allergy, count: allergy, priority: 90))
        }
        if occasion > 0 {
            facts.append(BriefingFact(id: "tom-occasion", kind: .occasion, count: occasion, priority: 50))
        }

        return StaffBriefingTomorrowPreview(
            dateKey: dateKey,
            reservationCount: operational.count,
            expectedGuests: expectedGuests,
            needsReviewCount: needsReview,
            noTableCount: noTable,
            largePartyCount: largeParty,
            attachmentCount: attachment,
            allergyCount: allergy,
            occasionCount: occasion,
            // Not safely derivable without loaded guest history — never faked.
            regularGuestCount: 0,
            priorityFacts: facts,
            hasData: true
        )
    }

    // MARK: - Fact ranking

    static func rankFacts(_ facts: [BriefingFact], mode: StaffBriefingMode, cap: Int) -> [BriefingFact] {
        let ranked = facts
            .filter { $0.kind != .serviceCalm }
            .sorted { lhs, rhs in
                let lw = modeWeight(lhs.kind, mode: mode)
                let rw = modeWeight(rhs.kind, mode: mode)
                if lw != rw { return lw > rw }
                return lhs.priority > rhs.priority
            }
        return Array(ranked.prefix(cap))
    }

    /// Mode-specific boost so the most relevant facts survive the cap.
    private static func modeWeight(_ kind: BriefingFactKind, mode: StaffBriefingMode) -> Int {
        switch mode {
        case .preService:
            switch kind {
            case .allergy: return 100
            case .noTableToday: return 90
            case .confirmation, .reminder: return 85
            case .occasion: return 80
            case .deposit, .preorder, .setup: return 75
            case .arrivalWindow, .businessPeak: return 70
            case .guestMemory: return 60
            case .newGuestCount: return 40
            default: return 30
            }
        case .liveService:
            switch kind {
            case .allergy: return 100
            case .seatedDuration, .longStayRecap: return 92
            case .waitingArrivals, .timedArrival, .nextArrival: return 88
            case .noTableToday: return 80
            case .seatedOverview, .tableWatch: return 70
            case .occasion, .guestMemory: return 60
            case .noShowFollowUp: return 55
            default: return 30
            }
        case .closingRecap:
            switch kind {
            case .completedRecap: return 95
            case .noShowFollowUp: return 90
            case .longStayRecap, .seatedOverview: return 80
            case .walkInCompleted: return 70
            case .businessPeak: return 60
            case .occasion, .guestMemory: return 50
            default: return 30
            }
        }
    }

    // MARK: - Labels + fingerprint

    private static func stateLabel(for mode: ServiceMode) -> String {
        switch mode {
        case .beforeService: return "Before open"
        case .duringService: return "Service is live"
        case .afterCloseNeedsCleanup: return "After close — cleanup pending"
        case .afterCloseFinished: return "Service wrapped"
        case .futurePlanning: return "Future planning"
        case .pastRecap: return "Past service"
        }
    }

    private static func buildFingerprint(
        input: Input,
        statusCounts: StaffBriefingStatusCounts,
        communication: StaffBriefingCommunicationSummary,
        tomorrowPreview: StaffBriefingTomorrowPreview?,
        factCount: Int
    ) -> String {
        let parts: [String] = [
            input.mode.rawValue,
            input.dateKey,
            input.servicePacket.inputFingerprint,
            "s:\(statusCounts.totalReservations),\(statusCounts.activeCount),\(statusCounts.seatedCount),\(statusCounts.completedCount),\(statusCounts.cancelledCount),\(statusCounts.noShowCount),\(statusCounts.needsReviewCount)",
            "c:\(communication.confirmationsMissingCount),\(communication.remindersMissingCount)",
            "f:\(factCount)",
            "t:\(tomorrowPreview.map { "\($0.reservationCount),\($0.expectedGuests),\($0.needsReviewCount),\($0.noTableCount),\($0.largePartyCount),\($0.allergyCount),\($0.occasionCount)" } ?? "none")",
            "b:\(input.businessSummaryLines.count)"
        ]
        return HostAttentionStableDigest.hexDigest(parts.joined(separator: "|"))
    }

    private static func displayTime(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nextDateKey(after dateKey: String) -> String {
        guard let date = ReservationFormatters.reservationDateKey.date(from: dateKey),
              let next = Calendar.current.date(byAdding: .day, value: 1, to: date) else {
            return dateKey
        }
        return next.reservationDateString()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
