//
//  HostServiceIntelligenceSnapshotBuilder.swift
//  Tryzub Reservations
//
//  LOCAL-FIRST-OPS-4A/4B — Deterministic per-date staff intelligence builder.
//
//  CONSTRAINTS (enforced, not advisory):
//  - Pure and deterministic: same inputs always produce same output.
//  - No network calls. No LLM calls. No full-history scan.
//  - dayReservations must be date-filtered by the caller.
//  - Never called from SwiftUI body.
//  - Only entry point: HostIntelligenceController.updateServiceIntelligenceSnapshot(),
//    which guards on isEvaluatedForSelectedDate before calling this.
//
//  Fact sources (evaluated in order; dedup prevents duplicates):
//  A. HostGuestSignal   — engine-computed: allergy, occasion, returning, accessibility, etc.
//  B. NoteSignalAnalyzer — per day reservation: all signal types mapped to snapshot categories.
//     Fills gaps where engine guest-signal pipeline didn't run (future dates, no backend intel).
//  C. Attachment metadata/signals — local labels + cached OCR-derived signal types.
//  D. HostBriefingFact.largeParty — engine-computed large-party context.
//  E. HostSlotPressure busiest slot → mainWave.
//  F. No-table aggregate count for futurePlanning mode.
//  G. Plain-note fallback — reservation has notes but no note-derived fact yet.
//  H. Confirmation / reminder day-level facts from local reservation fields.
//
//  Dedup: one ServiceIntelligenceFact per (reservationID, category).
//  Ranking: ServiceIntelligenceFactCategory.basePriority ± signal-severity adjustment.
//  Cap: 12 facts maximum (detail views may expand beyond this).
//
//  Emits: [SERVICE_INTEL_SNAPSHOT_TRACE] decision=build/skip/awaiting_evaluate ...
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
        /// Already-computed by HostIntelligenceEngine — no re-evaluation.
        let snapshot: HostDecisionSnapshot
        /// Day-scoped attachment metadata only. No image bytes, no network, no raw OCR text.
        let attachmentMetadata: [ServiceIntelligenceAttachmentMetadata]
        let largePartyThreshold: Int

        init(
            now: Date,
            selectedDate: Date,
            dateKey: String,
            serviceMode: ServiceMode,
            dayReservations: [ReservationRecord],
            snapshot: HostDecisionSnapshot,
            attachmentMetadata: [ServiceIntelligenceAttachmentMetadata] = [],
            largePartyThreshold: Int = 7
        ) {
            self.now = now
            self.selectedDate = selectedDate
            self.dateKey = dateKey
            self.serviceMode = serviceMode
            self.dayReservations = dayReservations
            self.snapshot = snapshot
            self.attachmentMetadata = attachmentMetadata
            self.largePartyThreshold = largePartyThreshold
        }
    }

    // MARK: - Public entry point

    static func build(_ input: Input) -> HostServiceIntelligenceSnapshot {
        let startTime = Date()
        let fingerprint = inputFingerprint(input)

        // O(n) on day reservations only.
        let guestNameByID: [Int: String] = Dictionary(
            uniqueKeysWithValues: input.dayReservations.map { ($0.remoteID, $0.guestName) }
        )

        var seenKeys = Set<String>()
        var factIndexByDedupeKey: [String: Int] = [:]
        var rawFacts: [ServiceIntelligenceFact] = []

        func addFact(_ fact: ServiceIntelligenceFact, dedupeKey: String) {
            guard !seenKeys.contains(dedupeKey) else { return }
            seenKeys.insert(dedupeKey)
            factIndexByDedupeKey[dedupeKey] = rawFacts.count
            rawFacts.append(fact)
        }

        func addOrReplaceFact(_ fact: ServiceIntelligenceFact, dedupeKey: String) {
            if let existingIndex = factIndexByDedupeKey[dedupeKey] {
                if fact.priority >= rawFacts[existingIndex].priority {
                    rawFacts[existingIndex] = fact
                }
                return
            }
            addFact(fact, dedupeKey: dedupeKey)
        }

        // ── Source A: HostGuestSignal ─────────────────────────────────────────
        // Already built by HostIntelligenceEngine — no re-scan of guest data.
        // Uses engine-derived copy (richer: visit counts, occasion specifics).
        for signal in input.snapshot.guestSignals {
            guard let (category, baseP) = guestSignalMapping(signal.kind) else { continue }
            let dedupeKey = "\(signal.reservationID)|\(category.rawValue)"
            addFact(
                ServiceIntelligenceFact(
                    id: "gsig-\(signal.id)",
                    reservationID: signal.reservationID,
                    guestName: signal.guestName,
                    category: category,
                    priority: priorityAdjusted(base: baseP, severity: signal.severity),
                    // Prefer engine's already-crafted summary over generic rewrites.
                    // Exception: .guestNote (noteReminder) may carry raw dietary text
                    // — use the safe generic headline there.
                    headline: guestSignalHeadline(signal: signal, category: category),
                    detail: signal.message.isEmpty ? nil : signal.message
                ),
                dedupeKey: dedupeKey
            )
        }

        // ── Source B: NoteSignalAnalyzer (all types, bounded to day rows) ─────
        // Fills gaps for fact categories the engine guest-signal pipeline does not
        // produce (deposit/preorder/banquet, some future-date cases, etc.).
        // NoteSignalAnalyzer is pure; dedup prevents double-counting with Source A.
        for reservation in input.dayReservations {
            guard reservation.isHostBoardOperational else { continue }
            let nsInput = NoteSignalAnalyzer.Input(
                reservationID: String(reservation.remoteID),
                guestNote: reservation.guestNotes,
                staffNote: reservation.staffNotes
            )
            let signals = NoteSignalAnalyzer.analyze(nsInput)
            for signal in signals {
                guard let category = noteSignalCategory(signal.type) else { continue }
                let dedupeKey = factDedupeKey(
                    reservationID: reservation.remoteID,
                    category: category,
                    signalType: signal.type
                )
                addFact(
                    ServiceIntelligenceFact(
                        id: "note-\(reservation.remoteID)-\(signal.type.rawValue)",
                        reservationID: reservation.remoteID,
                        guestName: reservation.guestName,
                        category: category,
                        priority: noteSignalPriority(signal, category: category),
                        headline: noteSignalFactHeadline(
                            signal: signal, reservation: reservation, category: category
                        ),
                        detail: signal.evidence
                    ),
                    dedupeKey: dedupeKey
                )
            }
        }

        // ── Source C: attachment metadata + cached OCR-derived signal types ───
        let dayReservationIDs = Set(input.dayReservations.map(\.remoteID))
        var attachmentFactKeys = Set<String>()
        var attachmentReservationIDs = Set<Int>()
        for metadata in input.attachmentMetadata where dayReservationIDs.contains(metadata.reservationID) {
            guard let reservation = input.dayReservations.first(where: { $0.remoteID == metadata.reservationID }),
                  reservation.isHostBoardOperational,
                  reservation.reservationDate == input.dateKey else { continue }
            let categories = attachmentCategories(for: metadata)
            for category in categories {
                let dedupeKey = "\(metadata.reservationID)|\(ServiceIntelligenceFactCategory.attachment.rawValue)|\(category.rawValue)"
                let fact = ServiceIntelligenceFact(
                    id: "att-\(metadata.reservationID)-\(metadata.attachmentID)-\(category.rawValue)",
                    reservationID: metadata.reservationID,
                    guestName: reservation.guestName,
                    category: .attachment,
                    priority: attachmentPriority(category),
                    headline: attachmentFactHeadline(metadata: metadata, category: category),
                    detail: attachmentFactDetail(metadata: metadata, guestName: reservation.guestName)
                )
                addOrReplaceFact(fact, dedupeKey: dedupeKey)
                if rawFacts.contains(where: { $0.id == fact.id }) {
                    attachmentFactKeys.insert(dedupeKey)
                    attachmentReservationIDs.insert(metadata.reservationID)
                }
            }
        }
        #if DEBUG
        if !input.attachmentMetadata.isEmpty {
            let ids = attachmentReservationIDs.sorted().map(String.init).joined(separator: ",")
            print(
                "[SERVICE_INTEL_SNAPSHOT_TRACE] source=attachments date=\(input.dateKey) " +
                "facts=\(attachmentFactKeys.count) reservations=\(ids.isEmpty ? "none" : ids)"
            )
        }
        #endif

        // ── Source D: large party from HostBriefingFact ───────────────────────
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

        // ── Source E: main service wave from slot pressures ───────────────────
        if let busiestSlot = input.snapshot.slotPressures.max(by: {
            ($0.guestCount, $0.reservationCount) < ($1.guestCount, $1.reservationCount)
        }), busiestSlot.guestCount > 0 {
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
                dedupeKey: "day|mainWave"
            )
        }

        // ── Source F: future no-table planning ────────────────────────────────
        if input.serviceMode == .futurePlanning {
            let noTableCount = input.dayReservations.filter { r in
                r.reservationDate == input.dateKey
                    && !r.hasTableAssignment
                    && (r.statusValue == .new || r.statusValue == .confirmed || r.statusValue == .needsReview)
            }.count
            if noTableCount > 0 {
                let plural = noTableCount == 1 ? "reservation" : "reservations"
                addFact(
                    ServiceIntelligenceFact(
                        id: "notable-\(input.dateKey)",
                        reservationID: nil,
                        guestName: nil,
                        category: .noTable,
                        priority: ServiceIntelligenceFactCategory.noTable.basePriority,
                        headline: "\(noTableCount) \(plural) still need tables.",
                        detail: nil
                    ),
                    dedupeKey: "day|noTable"
                )
            }
        }

        // ── Source G: plain-note fallback ─────────────────────────────────────
        // Catches reservations with notes that didn't match any NoteSignalAnalyzer
        // keyword (e.g. "Please ask manager about the arrangement"). Surfaces a
        // low-priority generic note fact so staff know to check.
        let noteCategories: [ServiceIntelligenceFactCategory] = [
            .allergy, .staffNote, .attachment, .accessibility, .occasion, .guestNote
        ]
        for reservation in input.dayReservations {
            guard reservation.isHostBoardOperational,
                  reservation.reservationDate == input.dateKey,
                  GuestHistorySemantics.hasActualReservationNotes(reservation) else { continue }
            let hasNoteFact = noteCategories.contains { cat in
                seenKeys.contains("\(reservation.remoteID)|\(cat.rawValue)")
            }
            guard !hasNoteFact else { continue }
            let name = reservation.guestName
            let firstName = name.components(separatedBy: " ").first ?? name
            let headline = reservation.hasGuestNotes
                ? "\(firstName) has a guest note."
                : "Check staff note for \(firstName)."
            addFact(
                ServiceIntelligenceFact(
                    id: "note-plain-\(reservation.remoteID)",
                    reservationID: reservation.remoteID,
                    guestName: name,
                    category: .guestNote,
                    // Slightly below keyword-matched guest-note facts so they rank higher.
                    priority: ServiceIntelligenceFactCategory.guestNote.basePriority - 2,
                    headline: headline,
                    detail: nil  // never expose raw note text in the snapshot
                ),
                dedupeKey: "\(reservation.remoteID)|\(ServiceIntelligenceFactCategory.guestNote.rawValue)"
            )
        }

        // ── Source H: confirmation / reminder status ──────────────────────────
        // Day-level facts from local reservation fields. No network required.
        // Confirmation: reservations that are still new/needsReview and have neither
        //   confirmedAt nor a confirmation email sent.
        let unconfirmedCount = input.dayReservations.filter { r in
            r.reservationDate == input.dateKey
                && (r.statusValue == .new || r.statusValue == .needsReview)
                && r.confirmedAt == nil
                && r.confirmationEmailSentAt == nil
        }.count
        if unconfirmedCount > 0 {
            let plural = unconfirmedCount == 1 ? "reservation" : "reservations"
            addFact(
                ServiceIntelligenceFact(
                    id: "conf-\(input.dateKey)",
                    reservationID: nil,
                    guestName: nil,
                    category: .confirmation,
                    priority: ServiceIntelligenceFactCategory.confirmation.basePriority,
                    headline: "\(unconfirmedCount) \(plural) awaiting confirmation.",
                    detail: nil
                ),
                dedupeKey: "day|confirmation"
            )
        }

        // Reminder: reservations with no reminder sent, only surfaced before service
        // and for future planning (during/after-close, reminders are no longer actionable).
        if input.serviceMode == .beforeService || input.serviceMode == .futurePlanning {
            let unremindedCount = input.dayReservations.filter { r in
                r.reservationDate == input.dateKey
                    && (r.statusValue == .new || r.statusValue == .confirmed || r.statusValue == .needsReview)
                    && r.reminderEmailSentAt == nil
            }.count
            if unremindedCount > 0 {
                let plural = unremindedCount == 1 ? "reservation" : "reservations"
                addFact(
                    ServiceIntelligenceFact(
                        id: "remind-\(input.dateKey)",
                        reservationID: nil,
                        guestName: nil,
                        category: .reminder,
                        priority: ServiceIntelligenceFactCategory.reminder.basePriority,
                        headline: "\(unremindedCount) \(plural) with no reminder sent.",
                        detail: nil
                    ),
                    dedupeKey: "day|reminder"
                )
            }
        }

        // ── Sort, cap ─────────────────────────────────────────────────────────
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

        // ── Trace ─────────────────────────────────────────────────────────────
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        #if DEBUG
        let categoryBreakdown = Dictionary(grouping: rankedFacts, by: { $0.category.rawValue })
            .map { "\($0.key):\($0.value.count)" }
            .sorted()
            .joined(separator: ",")
        print(
            "[SERVICE_INTEL_SNAPSHOT_TRACE] decision=build date=\(input.dateKey) " +
            "mode=\(input.serviceMode.rawValue) facts=\(rankedFacts.count) " +
            "categories=\(categoryBreakdown.isEmpty ? "none" : categoryBreakdown) " +
            "reservations=\(reservationCount) guests=\(guestCount) " +
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

    /// FNV-1a fingerprint of all builder inputs.
    /// 4B fix: uses note-content hash instead of character count so same-length
    /// edits (e.g. "birthday dinner" → "anniversary dinner") change the fingerprint.
    /// Includes confirmedAt + reminderEmailSentAt so reminder/confirmation facts
    /// rebuild when those fields change.
    static func inputFingerprint(_ input: Input) -> String {
        let reservationStamp = input.dayReservations
            .map { r -> String in
                // Note content hash — never logs raw note text, just a stable token.
                let noteHash = HostAttentionStableDigest.hexDigest(
                    "\(r.guestNotes ?? "")|\(r.staffNotes ?? "")"
                )
                return [
                    String(r.remoteID),
                    r.status,
                    String(r.partySize),
                    noteHash,
                    r.tableName ?? "",
                    r.confirmedAt ?? "none",
                    r.reminderEmailSentAt ?? "none"
                ].joined(separator: ":")
            }
            .joined(separator: "|")

        // Include signal messages so copy changes (e.g. visit-count updates) rebuild.
        let guestSignalStamp = input.snapshot.guestSignals
            .map { sig in
                "\(sig.id):\(sig.kind.rawValue):\(sig.severity.rawValue):"
                + HostAttentionStableDigest.hexDigest(sig.message)
            }
            .joined(separator: ";")

        // Include slot details so wave-time changes rebuild.
        let slotStamp = input.snapshot.slotPressures
            .map { "\($0.slotTime):\($0.guestCount):\($0.reservationCount)" }
            .joined(separator: ";")

        // Include briefing fact IDs for Source C (largeParty facts changing).
        let briefingStamp = input.snapshot.briefingFacts
            .map { "\($0.id):\($0.category.rawValue)" }
            .joined(separator: ";")

        let attachmentStamp = input.attachmentMetadata
            .sorted {
                if $0.reservationID != $1.reservationID { return $0.reservationID < $1.reservationID }
                return $0.attachmentID < $1.attachmentID
            }
            .map { metadata in
                let signalTypeDigest = HostAttentionStableDigest.hexDigest(
                    metadata.signalTypes.map(\.rawValue).sorted().joined(separator: ",")
                )
                return [
                    String(metadata.reservationID),
                    metadata.attachmentID,
                    metadata.label.backendValue,
                    signalTypeDigest,
                    metadata.updatedAt ?? "none"
                ].joined(separator: ":")
            }
            .joined(separator: ";")

        let raw = [
            input.dateKey,
            input.serviceMode.rawValue,
            String(input.dayReservations.count),
            reservationStamp,
            guestSignalStamp,
            slotStamp,
            briefingStamp,
            attachmentStamp
        ].joined(separator: "||")
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
            let subline = rankedFacts.first(where: { $0.category != .largeParty })?.headline
                ?? "Check setup and notes before service."
            return (headline, subline)
        }

        // Future / recap — counts + top fact as subline
        let rWord = reservationCount == 1 ? "reservation" : "reservations"
        let headline = "\(weekday): \(reservationCount) \(rWord) · \(guestCount) guests."
        let subline = rankedFacts.first?.headline
        return (headline, subline)
    }

    // MARK: - Guest signal mapping (Source A)

    /// Maps HostGuestSignalKind → (ServiceIntelligenceFactCategory, basePriority).
    /// Returns nil for signal kinds that have no staff-visible snapshot fact.
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

    /// Maps HostSeverity → a ±5 priority offset applied on top of basePriority.
    private static func priorityAdjusted(base: Int, severity: HostSeverity) -> Int {
        switch severity {
        case .critical: return base + 5
        case .warning:  return base + 2
        case .watch:    return base
        case .info:     return max(0, base - 2)
        }
    }

    /// Headline for Source A (HostGuestSignal) facts.
    ///
    /// Strategy (4B): prefer signal.message where the engine already produced a
    /// clean staff-facing summary (occasion specifics, visit counts, allergy copy).
    /// For .guestNote (noteReminder), signal.message may carry raw dietary text —
    /// use safe generic headline there and let `detail` carry the message.
    private static func guestSignalHeadline(
        signal: HostGuestSignal,
        category: ServiceIntelligenceFactCategory
    ) -> String {
        let firstName = signal.guestName.components(separatedBy: " ").first ?? signal.guestName
        let hasRichMessage = !signal.message.isEmpty

        switch category {
        case .allergy:
            // Engine: "Check allergy notes before seating {name}." — always clean.
            return hasRichMessage ? signal.message : "\(firstName) has an allergy note — check before seating."
        case .staffNote:
            // Engine service-issue message is usually informative.
            return hasRichMessage ? signal.message : "\(firstName) — check staff notes before service."
        case .accessibility:
            // Engine: "{name} needs wheelchair-accessible seating noted." — clean.
            return hasRichMessage ? signal.message : "\(firstName) has an accessibility request."
        case .occasion:
            // Engine uses GuestHistorySemantics.occasionNoteMessage → "mentioned a birthday."
            // Always prefer engine copy over the generic "has an occasion note."
            return hasRichMessage ? signal.message : "\(firstName) has an occasion note."
        case .returningGuest:
            // Engine: "Seen before · Last visit Jan 5" or visit-ordinal copy.
            return hasRichMessage ? signal.message : "\(firstName) is a returning guest."
        case .regularGuest:
            // Engine: "Julie Bachman, 3rd visit." with last-visit details.
            return hasRichMessage ? signal.message : "\(firstName) is a regular."
        case .guestNote:
            // noteReminder signal.message may carry raw dietary text (≤80 chars).
            // Keep generic headline; raw text surfaces in `detail` only.
            return "\(firstName) has a guest note."
        case .cancellationNoShow:
            return "\(firstName) — cancellation or no-show risk."
        default:
            return hasRichMessage ? signal.message : "\(firstName) — check notes."
        }
    }

    // MARK: - Note signal mapping (Source B)

    /// Maps ReservationSignalType → ServiceIntelligenceFactCategory.
    /// Returns nil for operational/meta signals that don't belong in the snapshot.
    private static func noteSignalCategory(
        _ type: ReservationSignalType
    ) -> ServiceIntelligenceFactCategory? {
        switch type {
        case .allergyOrDietary:
            return .allergy
        case .accessibility, .guestPreference:
            return .accessibility
        case .occasion:
            return .occasion
        case .depositMentioned, .depositVerified, .preorderMentioned,
             .banquetMentioned, .attachmentNeedsReview:
            return .attachment
        case .serviceIssue, .managerNote:
            return .staffNote
        case .kitchenNote, .barNote, .guestCommunicationNeeded:
            return .guestNote
        case .largeParty, .setupNeeded:
            return .largeParty
        // Operational status signals, booking-load suggestions, meta: skip.
        default:
            return nil
        }
    }

    private static func factDedupeKey(
        reservationID: Int,
        category: ServiceIntelligenceFactCategory,
        signalType: ReservationSignalType?
    ) -> String {
        if category == .attachment,
           let signalType,
           let attachmentCategory = attachmentCategory(for: signalType) {
            return "\(reservationID)|\(category.rawValue)|\(attachmentCategory.rawValue)"
        }
        return "\(reservationID)|\(category.rawValue)"
    }

    private static func attachmentCategories(
        for metadata: ServiceIntelligenceAttachmentMetadata
    ) -> [ServiceIntelligenceAttachmentCategory] {
        var categories: [ServiceIntelligenceAttachmentCategory] = []

        func append(_ category: ServiceIntelligenceAttachmentCategory) {
            guard !categories.contains(category) else { return }
            categories.append(category)
        }

        if let labelCategory = attachmentCategory(for: metadata.label), labelCategory != .genericPhoto {
            append(labelCategory)
        }
        for type in metadata.signalTypes {
            if let signalCategory = attachmentCategory(for: type), signalCategory != .genericPhoto {
                append(signalCategory)
            }
        }

        if categories.isEmpty {
            append(.genericPhoto)
        }

        return categories
    }

    private static func attachmentCategory(
        for label: AttachmentLabel
    ) -> ServiceIntelligenceAttachmentCategory? {
        switch label {
        case .deposit, .receipt:
            return .deposit
        case .preorder:
            return .preorder
        case .banquet:
            return .banquetMenu
        case .setup, .signedAgreement:
            return .setup
        case .guestScreenshot, .referenceImage, .other:
            return .genericPhoto
        }
    }

    private static func attachmentCategory(
        for signalType: ReservationSignalType
    ) -> ServiceIntelligenceAttachmentCategory? {
        switch signalType {
        case .depositMentioned, .depositVerified:
            return .deposit
        case .preorderMentioned:
            return .preorder
        case .banquetMentioned:
            return .banquetMenu
        case .setupNeeded:
            return .setup
        case .attachmentNeedsReview:
            return .genericPhoto
        default:
            return nil
        }
    }

    private static func attachmentPriority(_ category: ServiceIntelligenceAttachmentCategory) -> Int {
        switch category {
        case .deposit, .preorder, .banquetMenu:
            return ServiceIntelligenceFactCategory.attachment.basePriority + 4
        case .setup:
            return ServiceIntelligenceFactCategory.attachment.basePriority - 2
        case .genericPhoto:
            return ServiceIntelligenceFactCategory.guestNote.basePriority + 2
        }
    }

    private static func attachmentFactHeadline(
        metadata: ServiceIntelligenceAttachmentMetadata,
        category: ServiceIntelligenceAttachmentCategory
    ) -> String {
        switch category {
        case .preorder:
            return "Preorder attached — check kitchen before service."
        case .deposit:
            if metadata.label == .receipt {
                return "Receipt attachment on file — check before confirming details."
            }
            return "Deposit attachment on file — check before confirming details."
        case .banquetMenu:
            return "Banquet/menu photo attached — review before setup."
        case .setup:
            return "Special setup attachment on file — check before service."
        case .genericPhoto:
            return "Photo attached — check before service."
        }
    }

    private static func attachmentFactDetail(
        metadata: ServiceIntelligenceAttachmentMetadata,
        guestName: String
    ) -> String {
        let signalTypes = metadata.signalTypes
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        let signalDetail = signalTypes.isEmpty ? "none" : signalTypes
        return "\(guestName) · \(metadata.label.rawValue) · signals: \(signalDetail)"
    }

    /// Maps ReservationSignal priority + category basePriority to a snapshot integer priority.
    private static func noteSignalPriority(
        _ signal: ReservationSignal,
        category: ServiceIntelligenceFactCategory
    ) -> Int {
        let base = category.basePriority
        switch signal.priority {
        case .critical: return base + 4
        case .high:     return base + 2
        case .medium:   return base
        case .low:      return max(0, base - 2)
        case .info:     return max(0, base - 4)
        }
    }

    /// Headline for Source B (NoteSignalAnalyzer) facts.
    ///
    /// For .occasion: uses GuestHistorySemantics.occasionNoteMessage to produce
    /// specific copy ("mentioned a birthday") instead of generic "has an occasion note."
    private static func noteSignalFactHeadline(
        signal: ReservationSignal,
        reservation: ReservationRecord,
        category: ServiceIntelligenceFactCategory
    ) -> String {
        let firstName = reservation.guestName.components(separatedBy: " ").first ?? reservation.guestName
        switch category {
        case .allergy:
            return "\(firstName) has an allergy or dietary note — check before seating."
        case .attachment:
            return attachmentHeadline(signal: signal, guestName: reservation.guestName)
        case .occasion:
            // GuestHistorySemantics provides specific copy ("mentioned a birthday").
            return GuestHistorySemantics.occasionNoteMessage(
                guestName: reservation.guestName,
                reservation: reservation
            )
        case .accessibility:
            return "\(firstName) has an accessibility or seating note."
        case .staffNote:
            return "\(firstName) — check staff notes before service."
        case .guestNote:
            switch signal.type {
            case .kitchenNote:            return "\(firstName) — kitchen note, tell the kitchen."
            case .barNote:                return "\(firstName) — bar or drinks note."
            case .guestCommunicationNeeded: return "\(firstName) — guest may expect a reply."
            default:                      return "\(firstName) has a guest note."
            }
        case .largeParty:
            return "\(firstName) — large group details in notes."
        default:
            return "\(firstName) — check notes."
        }
    }

    // MARK: - Attachment headline helper (shared by Sources A/B)

    private static func attachmentHeadline(
        signal: ReservationSignal,
        guestName: String
    ) -> String {
        let firstName = guestName.components(separatedBy: " ").first ?? guestName
        switch signal.type {
        case .depositMentioned, .depositVerified:
            return "\(firstName) — deposit mentioned, verify before service."
        case .preorderMentioned:
            return "\(firstName) — preorder noted, check with kitchen."
        case .banquetMentioned:
            return "\(firstName) — group/banquet details in notes."
        default:
            return "\(firstName) — note needs review."
        }
    }

    // MARK: - Large party headline helper (Source C)

    private static func largePartyHeadline(
        fact: HostBriefingFact,
        reservation: ReservationRecord?
    ) -> String {
        if let r = reservation {
            let timeLabel = formatTime(r.reservationTime)
            return "\(r.partySize)-person party at \(timeLabel) — check setup."
        }
        return fact.title
    }

    // MARK: - Time formatting

    /// Normalises "HH:mm:ss" or "HH:mm" to "H:mm" (24-hour, no leading zero).
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
