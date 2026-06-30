//
//  HostServiceIntelligenceSnapshotBuilder.swift
//  Tryzub Reservations
//
//  LOCAL-FIRST-OPS-4A — Deterministic per-date staff intelligence builder.
//
//  CONSTRAINTS (enforced, not advisory):
//  - Pure and deterministic: same inputs always produce same output.
//  - No network calls.
//  - No LLM calls.
//  - No full-history scan: dayReservations must be date-filtered by caller.
//  - No SwiftUI dependency. Never called from body.
//  - Called from HostIntelligenceController.updateServiceIntelligenceSnapshot()
//    which itself is called only from HostBoardView.rebuildServiceBriefing().
//
//  Fact sources (in priority order):
//  A. HostGuestSignal from HostDecisionSnapshot (allergy, occasion, returning, etc.)
//  B. NoteSignalAnalyzer per day reservation (deposit, preorder, banquet — not in Host pipeline)
//  C. HostBriefingFact with .largeParty category
//  D. Busiest HostSlotPressure → mainWave
//  E. No-table count for futurePlanning mode
//
//  Dedup: one ServiceIntelligenceFact per (reservationID, category).
//  Ranking: ServiceIntelligenceFactCategory.basePriority ± HostSeverity adjustment.
//  Cap: 12 facts maximum (detail views expand beyond this).
//
//  Emits: [SERVICE_INTEL_SNAPSHOT_TRACE] decision=build/skip ...
//

import Foundation

enum HostServiceIntelligenceSnapshotBuilder {

    // MARK: - Input

    struct Input {
        let now: Date
        let selectedDate: Date
        let dateKey: String
        let serviceMode: ServiceMode
        /// Day-filtered reservations only — no full-history pool.
        let dayReservations: [ReservationRecord]
        /// Already-computed by HostIntelligenceEngine; no re-evaluation.
        let snapshot: HostDecisionSnapshot
        let largePartyThreshold: Int

        init(
            now: Date,
            selectedDate: Date,
            dateKey: String,
            serviceMode: ServiceMode,
            dayReservations: [ReservationRecord],
            snapshot: HostDecisionSnapshot,
            largePartyThreshold: Int = 7
        ) {
            self.now = now
            self.selectedDate = selectedDate
            self.dateKey = dateKey
            self.serviceMode = serviceMode
            self.dayReservations = dayReservations
            self.snapshot = snapshot
            self.largePartyThreshold = largePartyThreshold
        }
    }

    // MARK: - Public entry point

    static func build(_ input: Input) -> HostServiceIntelligenceSnapshot {
        let startTime = Date()
        let fingerprint = inputFingerprint(input)

        // Guest name lookup — O(n) on day reservations only.
        let guestNameByID: [Int: String] = Dictionary(
            uniqueKeysWithValues: input.dayReservations.map { ($0.remoteID, $0.guestName) }
        )

        var seenKeys = Set<String>()
        var rawFacts: [ServiceIntelligenceFact] = []

        func addFact(_ fact: ServiceIntelligenceFact, dedupeKey: String) {
            guard !seenKeys.contains(dedupeKey) else { return }
            seenKeys.insert(dedupeKey)
            rawFacts.append(fact)
        }

        // ── Source A: HostGuestSignal (allergy, occasion, returning, etc.) ────
        // Already built by HostIntelligenceEngine — no re-scan of guest data.
        for signal in input.snapshot.guestSignals {
            guard let (category, baseP) = guestSignalMapping(signal.kind) else { continue }
            let dedupeKey = "\(signal.reservationID)|\(category.rawValue)"
            let headline = guestSignalHeadline(signal: signal, category: category)
            addFact(
                ServiceIntelligenceFact(
                    id: "gsig-\(signal.id)",
                    reservationID: signal.reservationID,
                    guestName: signal.guestName,
                    category: category,
                    priority: priorityAdjusted(base: baseP, severity: signal.severity),
                    headline: headline,
                    detail: signal.message.isEmpty ? nil : signal.message
                ),
                dedupeKey: dedupeKey
            )
        }

        // ── Source B: deposit / preorder / banquet via NoteSignalAnalyzer ─────
        // These signal types don't exist in HostGuestSignalKind, so the Host
        // pipeline omits them. Only day reservations are scanned — no history pool.
        let attachmentSignalTypes: Set<ReservationSignalType> = [
            .depositMentioned, .preorderMentioned, .banquetMentioned
        ]
        for reservation in input.dayReservations {
            let nsInput = NoteSignalAnalyzer.Input(
                reservationID: String(reservation.remoteID),
                guestNote: reservation.guestNotes,
                staffNote: reservation.staffNotes
            )
            let signals = NoteSignalAnalyzer.analyze(nsInput)
            for signal in signals where attachmentSignalTypes.contains(signal.type) {
                let dedupeKey = "\(reservation.remoteID)|attachment"
                addFact(
                    ServiceIntelligenceFact(
                        id: "att-\(reservation.remoteID)-\(signal.type.rawValue)",
                        reservationID: reservation.remoteID,
                        guestName: reservation.guestName,
                        category: .attachment,
                        priority: ServiceIntelligenceFactCategory.attachment.basePriority,
                        headline: attachmentHeadline(signal: signal, guestName: reservation.guestName),
                        detail: signal.staffText
                    ),
                    dedupeKey: dedupeKey
                )
                break // one attachment fact per reservation
            }
        }

        // ── Source C: large party from HostBriefingFact ───────────────────────
        for fact in input.snapshot.briefingFacts where fact.category == .largeParty {
            let rid = fact.relatedReservationIDs.first
            let dedupeKey = rid.map { "\($0)|largeParty" } ?? "day|largeParty"
            let matchedReservation = rid.flatMap { rID in
                input.dayReservations.first { $0.remoteID == rID }
            }
            addFact(
                ServiceIntelligenceFact(
                    id: "lp-\(fact.id)",
                    reservationID: rid,
                    guestName: rid.flatMap { guestNameByID[$0] },
                    category: .largeParty,
                    priority: ServiceIntelligenceFactCategory.largeParty.basePriority,
                    headline: largePartyHeadline(fact: fact, reservation: matchedReservation),
                    detail: fact.detail.isEmpty ? nil : fact.detail
                ),
                dedupeKey: dedupeKey
            )
        }

        // ── Source D: main service wave from slot pressures ───────────────────
        if let busiestSlot = input.snapshot.slotPressures.max(by: {
            ($0.guestCount, $0.reservationCount) < ($1.guestCount, $1.reservationCount)
        }), busiestSlot.guestCount > 0 {
            let dedupeKey = "day|mainWave"
            let timeLabel = formatTime(busiestSlot.slotTime)
            addFact(
                ServiceIntelligenceFact(
                    id: "wave-\(input.dateKey)",
                    reservationID: nil,
                    guestName: nil,
                    category: .mainWave,
                    priority: ServiceIntelligenceFactCategory.mainWave.basePriority,
                    headline: "Main wave around \(timeLabel).",
                    detail: "\(busiestSlot.reservationCount) reservations · \(busiestSlot.guestCount) guests"
                ),
                dedupeKey: dedupeKey
            )
        }

        // ── Source E: future no-table planning ────────────────────────────────
        if input.serviceMode == .futurePlanning {
            let noTableCount = input.dayReservations.filter { reservation in
                reservation.reservationDate == input.dateKey
                    && !reservation.hasTableAssignment
                    && (
                        reservation.statusValue == .new
                        || reservation.statusValue == .confirmed
                        || reservation.statusValue == .needsReview
                    )
            }.count
            if noTableCount > 0 {
                let dedupeKey = "day|noTable"
                let headline = noTableCount == 1
                    ? "1 reservation still needs a table."
                    : "\(noTableCount) reservations still need tables."
                addFact(
                    ServiceIntelligenceFact(
                        id: "notable-\(input.dateKey)",
                        reservationID: nil,
                        guestName: nil,
                        category: .noTable,
                        priority: ServiceIntelligenceFactCategory.noTable.basePriority,
                        headline: headline,
                        detail: nil
                    ),
                    dedupeKey: dedupeKey
                )
            }
        }

        // ── Sort, cap, and aggregate ──────────────────────────────────────────
        let rankedFacts = Array(
            rawFacts.sorted { $0.priority > $1.priority }.prefix(12)
        )

        let active = input.dayReservations.filter {
            switch $0.statusValue {
            case .new, .needsReview, .confirmed, .seated: return true
            default: return false
            }
        }
        let reservationCount = active.count
        let guestCount = active.reduce(0) { $0 + max(0, $1.partySize) }

        // ── Headline ──────────────────────────────────────────────────────────
        let (headline, subline) = buildHeadline(
            input: input,
            reservationCount: reservationCount,
            guestCount: guestCount,
            rankedFacts: rankedFacts
        )

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        #if DEBUG
        print(
            "[SERVICE_INTEL_SNAPSHOT_TRACE] decision=build date=\(input.dateKey) mode=\(input.serviceMode.rawValue) " +
            "facts=\(rankedFacts.count) reservations=\(reservationCount) guests=\(guestCount) " +
            "durationMs=\(durationMs) fingerprint=\(String(fingerprint.prefix(16)))"
        )
        #endif

        return HostServiceIntelligenceSnapshot(
            dateKey: input.dateKey,
            generatedAt: input.now,
            serviceMode: input.serviceMode,
            headline: headline,
            subline: subline,
            reservationCount: reservationCount,
            guestCount: guestCount,
            rankedFacts: rankedFacts,
            inputFingerprint: fingerprint
        )
    }

    // MARK: - Fingerprint (skip gate)

    /// Stable FNV-1a fingerprint of all meaningful builder inputs.
    /// Uses HostAttentionStableDigest to match the project's existing hash pattern.
    static func inputFingerprint(_ input: Input) -> String {
        let reservationStamp = input.dayReservations
            .map {
                "\($0.remoteID):\($0.status):\($0.partySize):"
                + "\($0.guestNotes?.count ?? 0):\($0.staffNotes?.count ?? 0):"
                + "\($0.tableName ?? "")"
            }
            .joined(separator: "|")
        let guestSignalStamp = input.snapshot.guestSignals
            .map { "\($0.id):\($0.kind.rawValue):\($0.severity.rawValue)" }
            .joined(separator: ";")
        let slotStamp = "\(input.snapshot.slotPressures.count):\(input.snapshot.briefingFacts.count)"
        let raw = [
            input.dateKey,
            input.serviceMode.rawValue,
            "\(input.dayReservations.count)",
            reservationStamp,
            guestSignalStamp,
            slotStamp
        ].joined(separator: "|")
        return HostAttentionStableDigest.hexDigest(raw)
    }

    // MARK: - Headline builder

    private static func buildHeadline(
        input: Input,
        reservationCount: Int,
        guestCount: Int,
        rankedFacts: [ServiceIntelligenceFact]
    ) -> (headline: String, subline: String?) {
        let weekday = input.selectedDate.formatted(.dateTime.weekday(.wide))

        // Empty day
        guard reservationCount > 0 else {
            return ("No reservations for \(weekday).", nil)
        }

        // Today (live modes) — lead with next upcoming guest
        if input.serviceMode == .beforeService || input.serviceMode == .duringService {
            let nextGuest = input.dayReservations
                .filter {
                    ($0.statusValue == .new || $0.statusValue == .confirmed || $0.statusValue == .needsReview)
                        && $0.reservationDate == input.dateKey
                }
                .sorted {
                    $0.reservationTime == $1.reservationTime
                        ? $0.remoteID < $1.remoteID
                        : $0.reservationTime < $1.reservationTime
                }
                .first
            if let next = nextGuest {
                let firstName = next.guestName.components(separatedBy: " ").first ?? next.guestName
                let timeLabel = formatTime(next.reservationTime)
                let party = max(1, next.partySize)
                let guestWord = party == 1 ? "guest" : "guests"
                let headline = "\(firstName) is next at \(timeLabel) · \(party) \(guestWord)."
                // Top fact that is about this reservation, or top fact overall
                let subline = rankedFacts.first(where: { $0.reservationID == next.remoteID })?.headline
                    ?? rankedFacts.first?.headline
                return (headline, subline)
            }
        }

        // Future date — large party leads when size ≥ threshold
        let largestParty = input.dayReservations
            .filter { $0.reservationDate == input.dateKey }
            .max(by: { $0.partySize < $1.partySize })
        if let big = largestParty, big.partySize >= input.largePartyThreshold {
            let timeLabel = formatTime(big.reservationTime)
            let headline = "\(weekday) has a \(big.partySize)-person party at \(timeLabel)."
            // Top non-largeParty fact, or fallback setup copy
            let subline = rankedFacts.first(where: { $0.category != .largeParty })?.headline
                ?? "Check setup and notes before service."
            return (headline, subline)
        }

        // Future / recap — generic counts + top fact as subline
        let rWord = reservationCount == 1 ? "reservation" : "reservations"
        let headline = "\(weekday): \(reservationCount) \(rWord) · \(guestCount) guests."
        let subline = rankedFacts.first?.headline
        return (headline, subline)
    }

    // MARK: - Guest signal mapping

    /// Maps HostGuestSignalKind → (ServiceIntelligenceFactCategory, basePriority).
    /// Returns nil for signal kinds that don't map to a staff-visible fact.
    private static func guestSignalMapping(
        _ kind: HostGuestSignalKind
    ) -> (ServiceIntelligenceFactCategory, Int)? {
        switch kind {
        case .allergy:
            return (.allergy, ServiceIntelligenceFactCategory.allergy.basePriority)
        case .previousServiceIssue:
            return (.staffNote, ServiceIntelligenceFactCategory.staffNote.basePriority)
        case .accessibility, .seatingPreference:
            return (.accessibility, ServiceIntelligenceFactCategory.accessibility.basePriority)
        case .specialOccasion:
            return (.occasion, ServiceIntelligenceFactCategory.occasion.basePriority)
        case .importantGuest, .vip:
            return (.returningGuest, ServiceIntelligenceFactCategory.returningGuest.basePriority)
        case .regularGuest:
            return (.regularGuest, ServiceIntelligenceFactCategory.regularGuest.basePriority)
        case .noteReminder:
            return (.guestNote, ServiceIntelligenceFactCategory.guestNote.basePriority)
        case .cancellationRisk, .noShowRisk:
            return (.cancellationNoShow, ServiceIntelligenceFactCategory.cancellationNoShow.basePriority)
        case .manualCallIn, .possibleDuplicate, .unknown:
            return nil
        }
    }

    private static func priorityAdjusted(base: Int, severity: HostSeverity) -> Int {
        switch severity {
        case .critical: return base + 5
        case .warning:  return base + 2
        case .watch:    return base
        case .info:     return max(0, base - 2)
        }
    }

    // MARK: - Headline strings per category

    private static func guestSignalHeadline(
        signal: HostGuestSignal,
        category: ServiceIntelligenceFactCategory
    ) -> String {
        let firstName = signal.guestName.components(separatedBy: " ").first ?? signal.guestName
        switch category {
        case .allergy:
            return "\(firstName) has an allergy note — check before seating."
        case .staffNote:
            return "\(firstName) — check staff notes before service."
        case .accessibility:
            return "\(firstName) has an accessibility request."
        case .occasion:
            return "\(firstName) has an occasion note."
        case .returningGuest:
            return "\(firstName) is a returning guest."
        case .regularGuest:
            return "\(firstName) is a regular."
        case .guestNote:
            return "\(firstName) has a guest note."
        case .cancellationNoShow:
            return "\(firstName) — cancellation or no-show risk."
        default:
            return signal.message.isEmpty ? "\(firstName) — check notes." : signal.message
        }
    }

    private static func attachmentHeadline(
        signal: ReservationSignal,
        guestName: String
    ) -> String {
        let firstName = guestName.components(separatedBy: " ").first ?? guestName
        switch signal.type {
        case .depositMentioned:
            return "\(firstName) — deposit mentioned, verify before service."
        case .preorderMentioned:
            return "\(firstName) — preorder noted, check with kitchen."
        case .banquetMentioned:
            return "\(firstName) — group/banquet details in notes."
        default:
            return "\(firstName) — note needs review."
        }
    }

    private static func largePartyHeadline(
        fact: HostBriefingFact,
        reservation: ReservationRecord?
    ) -> String {
        if let r = reservation {
            let timeLabel = formatTime(r.reservationTime)
            return "\(r.partySize)-person party at \(timeLabel) — check setup."
        }
        // Fallback to engine fact title (already formatted by HostIntelligenceEngine)
        return fact.title
    }

    // MARK: - Time formatting

    /// Normalises "HH:mm:ss" or "HH:mm" to "H:mm" (24-hour, no leading zero on hour).
    /// Matches the time style shown throughout the app (e.g. "15:15", "9:00").
    private static func formatTime(_ reservationTime: String) -> String {
        let parts = reservationTime.components(separatedBy: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return reservationTime
        }
        return String(format: "%d:%02d", hour, minute)
    }
}
