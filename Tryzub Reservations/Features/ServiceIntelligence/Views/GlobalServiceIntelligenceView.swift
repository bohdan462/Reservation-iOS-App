//
//  GlobalServiceIntelligenceView.swift
//  Tryzub Reservations
//
//  Service Intelligence — backend-fed operations hub.
//
//  RENDER POLICY:
//   • First render is always immediate from cache (no spinner, no blank state).
//   • Backend guest intelligence and business analytics are scheduled as background
//     loads on appear. When they arrive, `rebuildStamp` changes and the view rebuilds
//     automatically — staff see richer intelligence without a reload tap.
//
//  DATA SOURCES:
//   • ReservationsController — live reservation cache
//   • GuestIntelligenceStore — GET /guest-intelligence?date={today}
//   • BusinessIntelligenceStore — GET /business-intelligence/summary
//   • RestaurantSettingsStore.analyticsSummary — GET /reservation-analytics/summary
//
//  SOURCE LABELLING:
//   • [SERVICE_CONTEXT_TRACE] source=cache_only|mixed|backend_enriched proves what
//     data was used for each rebuild.
//

import SwiftUI
import SwiftData
import UIKit

struct GlobalServiceIntelligenceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hostIntelligenceController: HostIntelligenceController
    @EnvironmentObject private var settingsStore: RestaurantSettingsStore
    @EnvironmentObject private var hostIntelligenceSettingsStore: HostIntelligenceSettingsStore
    @EnvironmentObject private var hostTableConfigStore: HostTableConfigStore
    @EnvironmentObject private var floorPlanStore: FloorPlanStore
    @EnvironmentObject private var guestIntelligenceStore: GuestIntelligenceStore
    @EnvironmentObject private var businessIntelligenceStore: BusinessIntelligenceStore

    @Query private var windowReservations: [ReservationRecord]
    /// All attachment records — joined with today's reservations in rebuild() for attachment signals.
    @Query(sort: \ReservationAttachmentRecord.createdAt) private var allAttachmentRecords: [ReservationAttachmentRecord]

    @State private var briefing: HostServiceBriefingViewState?
    @State private var usesBriefingPacket = false
    @State private var packetSections: [BriefingSection] = []
    @State private var usesCanonicalSnapshot = false
    @State private var snapshotFacts: [ServiceIntelligenceFact] = []
    @State private var bookingItems: [BookingSuggestionViewItem] = []
    @State private var bookingKnownOnlyNote: String = ""
    /// Reservations that have actionable note signals (Phase 6 — Note intelligence).
    @State private var signalledReservations: [(reservation: ReservationRecord, topSignals: [ReservationSignal])] = []
    /// Backend-enriched guest signals for today — "Guests to know" section.
    @State private var guestsToKnow: [ServiceGuestTruthRow] = []
    /// Staff-language lines from BusinessIntelligenceInsightBuilder (upgrades analytics section).
    @State private var businessInsightLines: [String] = []
    /// Source label for [SERVICE_CONTEXT_TRACE] — "cache_only", "mixed", "backend_enriched".
    @State private var intelligenceSource: String = "cache_only"
    /// Subtle freshness note (nil when data is current).
    @State private var freshnessNote: String?
    @State private var clockTick = Date()
    @State private var selectedReservation: ReservationRecord?
    @State private var showBlockedSlots = false
    /// Slot value pre-selected when "Review close slot" is tapped for a specific suggestion.
    @State private var blockedSlotsPreselectedSlot: String?

    let environment: AppEnvironment
    let showsCloseButton: Bool

    private let clockTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(environment: AppEnvironment, showsCloseButton: Bool = false) {
        self.environment = environment
        self.showsCloseButton = showsCloseButton
        let bounds = activeReservationWindowQueryBounds()
        let fromDate = bounds.from
        let toDate = bounds.to
        _windowReservations = Query(
            filter: #Predicate<ReservationRecord> { reservation in
                !reservation.isHidden
                    && reservation.reservationDate >= fromDate
                    && reservation.reservationDate <= toDate
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate),
                SortDescriptor(\ReservationRecord.reservationTime)
            ]
        )
    }

    var body: some View {
        TryzubHostBoardCanvas {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let briefing {
                        HostServiceBriefingCard(state: briefing) { intent in
                            openReservation(for: intent)
                        }
                        if briefing.unresolvedCount > 0 {
                            unresolvedFooter(briefing.unresolvedCount)
                        }
                    } else {
                        HostServiceBriefingCardPlaceholder()
                    }

                    snapshotFactsSection

                    if !bookingItems.isEmpty {
                        bookingSuggestionsSection
                    }

                    guestsToKnowSection

                    noteSignalsSection

                    upcomingSection

                    analyticsSection

                    if let note = freshnessNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(12)
            }
        }
        .navigationTitle("Service Intelligence")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .navigationDestination(item: $selectedReservation) { reservation in
            ReservationDetailView(reservation: reservation, environment: environment)
        }
        .sheet(isPresented: $showBlockedSlots) {
            NavigationStack {
                BlockedTimeSlotsView(
                    settingsStore: settingsStore,
                    preselectedSlotValue: blockedSlotsPreselectedSlot
                )
            }
        }
        .onAppear {
            rebuild()
            scheduleBackendLoads()
        }
        .onChange(of: rebuildStamp) { _, _ in rebuild() }
        .onReceive(clockTimer) { now in clockTick = now }
    }

    // MARK: - Sections

    @ViewBuilder
    private var snapshotFactsSection: some View {
        if usesBriefingPacket && !packetSections.isEmpty {
            ForEach(packetSections) { section in
                sectionCard(
                    title: section.title,
                    systemImage: packetSectionIcon(section.id)
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(section.lines.prefix(3).enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            if index != min(section.lines.count, 3) - 1 {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                }
            }
        } else if usesCanonicalSnapshot && !snapshotFacts.isEmpty {
                sectionCard(
                    title: "Service facts",
                    systemImage: "list.bullet.clipboard"
                ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshotFacts) { fact in
                        if let reservationID = fact.reservationID,
                           let reservation = windowReservations.first(where: { $0.remoteID == reservationID }) {
                            Button {
                                selectedReservation = reservation
                            } label: {
                                SnapshotFactRow(fact: fact)
                            }
                            .buttonStyle(.plain)
                        } else {
                            SnapshotFactRow(fact: fact)
                        }
                        if fact.id != snapshotFacts.last?.id {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bookingSuggestionsSection: some View {
        sectionCard(
            title: "Booking Suggestions",
            systemImage: "clock.badge.exclamationmark"
        ) {
            if bookingItems.isEmpty {
                Text("No booking slots need attention right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bookingItems) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        BookingSuggestionContent(item: item)
                        bookingActionButton(for: item)
                    }
                    if item.id != bookingItems.last?.id {
                        Divider()
                    }
                }
                if !bookingKnownOnlyNote.isEmpty {
                    Text(bookingKnownOnlyNote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func bookingActionButton(for item: BookingSuggestionViewItem) -> some View {
        // Backend close-slot support exists (POST /restaurant-blocked-slots). We never
        // call it automatically — staff confirm on the blocked-slots screen. Staff
        // without settings permission get a non-mutating "Copy suggestion" fallback.
        if controller.capabilities.canManageRestaurantSettings {
            Button {
                    blockedSlotsPreselectedSlot = item.slotValue
                    showBlockedSlots = true
                } label: {
                    Label("Review close slot", systemImage: "calendar.badge.minus")
                    .font(.caption.weight(.semibold))
                }
            } else {
                Button {
                    UIPasteboard.general.string = "\(item.headline). \(item.loadLine). \(item.closeLine). \(item.alternateLine)"
                } label: {
                    Label("Copy suggestion", systemImage: "doc.on.doc")
                    .font(.caption.weight(.semibold))
                }
            }
    }

    // MARK: - Guests to know (backend-enriched)

    @ViewBuilder
    private var guestsToKnowSection: some View {
        if !guestsToKnow.isEmpty && !packetHasGuestCoverage {
            sectionCard(
                title: "Guests to know today",
                systemImage: "person.crop.circle.badge.exclamationmark"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(guestsToKnow.prefix(6)) { guest in
                        if let reservation = windowReservations.first(where: { $0.remoteID == guest.id }) {
                            Button {
                                selectedReservation = reservation
                            } label: {
                                GuestToKnowRow(row: guest)
                            }
                            .buttonStyle(.plain)
                        } else {
                            GuestToKnowRow(row: guest)
                        }
                        if guest.id != guestsToKnow.prefix(6).last?.id {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var noteSignalsSection: some View {
        let visibleEntries = visibleNoteSignalEntries
        if !visibleEntries.isEmpty {
            sectionCard(
                title: "Note signals",
                systemImage: "lightbulb"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleEntries, id: \.reservation.remoteID) { entry in
                        Button {
                            selectedReservation = entry.reservation
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.reservation.guestName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(entry.topSignals.map(\.title).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    if entry.topSignals.contains(where: { $0.requiresReview }) {
                                        Text(entry.topSignals.first(where: { $0.requiresReview })?.staffText ?? "")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        if entry.reservation.remoteID != visibleEntries.last?.reservation.remoteID {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var visibleNoteSignalEntries: [(reservation: ReservationRecord, topSignals: [ReservationSignal])] {
        let coveredReservationIDs = Set(guestsToKnow.map(\.id))
        guard !coveredReservationIDs.isEmpty else { return signalledReservations }
        return signalledReservations.filter { entry in
            !coveredReservationIDs.contains(entry.reservation.remoteID)
                || entry.topSignals.contains(where: { $0.requiresReview })
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        let upcoming = upcomingReservationCount
        if upcoming > 0 {
            sectionCard(
                title: "Upcoming",
                systemImage: "calendar.badge.clock"
            ) {
                Text(upcoming == 1
                     ? "1 reservation booked beyond this date."
                     : "\(upcoming) reservations booked beyond this date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var analyticsSection: some View {
        sectionCard(
            title: "Business",
            systemImage: "chart.bar"
        ) {
            // Business intelligence backend summary (richer than reservation analytics).
            if !businessInsightLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(businessInsightLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if let metrics = settingsStore.analyticsSummary?.summary {
                // Fallback: reservation analytics summary (already cached).
                VStack(alignment: .leading, spacing: 6) {
                    analyticsRow("Reservations", value: "\(metrics.reservationsCount)")
                    analyticsRow("Guests", value: "\(metrics.guestsCount)")
                    if let avg = metrics.avgPartySize {
                        analyticsRow("Avg party", value: String(format: "%.1f", avg))
                    }
                    if let range = settingsStore.analyticsSummary?.range,
                       let from = range.from, let to = range.to {
                        Text("\(from) – \(to)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("Open Business Analytics to load the latest numbers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if controller.capabilities.canViewAnalytics {
                NavigationLink {
                    BusinessAnalyticsView(settingsStore: settingsStore)
                } label: {
                    Label("Open Business Analytics", systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
                .padding(.top, 2)
            }
        }
    }

    private func unresolvedFooter(_ count: Int) -> some View {
        Text(count == 1
             ? "1 item still needs a status update."
             : "\(count) items still need a status update.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 15, alignment: .center)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hostBoardGlassPanel(cornerRadius: 12, strokeOpacity: 0.10)
    }

    private func analyticsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private func packetSectionIcon(_ id: String) -> String {
        switch id {
        case "arrivals":
            return "clock"
        case "seated":
            return "table.furniture"
        case "guests":
            return "person.2"
        case "followup":
            return "bell"
        case "recap":
            return "checkmark.circle"
        default:
            return "sparkles"
        }
    }

    private var packetHasGuestCoverage: Bool {
        usesBriefingPacket && packetSections.contains { section in
            section.id == "guests" && !section.lines.isEmpty
        }
    }

    // MARK: - Data

    /// The hub follows the Host Board's evaluated service date when available.
    /// Cold opens still default to calendar today.
    private var serviceDateKey: String {
        let hostKey = hostIntelligenceController.evaluatedSelectedDateKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !hostKey.isEmpty,
           hostIntelligenceController.isEvaluatedForSelectedDate(hostKey) {
            return hostKey
        }
        return Date.reservationDateString()
    }

    private var serviceDate: Date {
        ReservationFormatters.reservationDateKey.date(from: serviceDateKey) ?? Date()
    }

    private var serviceDateReservations: [ReservationRecord] {
        windowReservations.filter { $0.reservationDate == serviceDateKey }
    }

    private var serviceDateIntelligenceSourceFingerprint: String {
        HostIntelligenceController.serviceIntelligenceSourceFingerprint(
            dateKey: serviceDateKey,
            reservations: serviceDateReservations
        )
    }

    private var upcomingReservationCount: Int {
        windowReservations.filter { reservation in
            reservation.reservationDate > serviceDateKey
                && reservation.statusValue != .cancelled
                && reservation.statusValue != .noShow
        }.count
    }

    private var serviceDateBounds: (open: Date?, close: Date?) {
        guard let availability = controller.availabilitySummary(for: serviceDateKey)?.availability else {
            return (nil, nil)
        }
        func serviceDate(from timeValue: String?) -> Date? {
            guard let timeValue else { return nil }
            let trimmed = timeValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let time = trimmed.count >= 5 ? String(trimmed.prefix(5)) : trimmed
            return ReservationFormatters.serverDateMinute.date(from: "\(serviceDateKey) \(time)")
        }
        guard let open = serviceDate(from: availability.openTime),
              let close = serviceDate(from: availability.closeTime),
              open <= close else {
            return (nil, nil)
        }
        return (open, close)
    }

    /// Recomputes whenever reservations, the snapshot, clock-minute, or backend
    /// intelligence stores change. Covers cache-only → backend-enriched transitions.
    private var rebuildStamp: String {
        let minute = Int(clockTick.timeIntervalSince1970 / 60)
        // Include attachment OCR count so rebuild fires when extractedText is written.
        let ocrCompleted = allAttachmentRecords.filter { $0.ocrRanAt != nil }.count
        return [
            serviceDateKey,
            String(serviceDateReservations.count),
            String(Int(hostIntelligenceController.decisionSnapshot.generatedAt.timeIntervalSince1970)),
            hostIntelligenceController.serviceIntelligenceSnapshot.inputFingerprint,
            hostIntelligenceController.serviceBriefingPacket.inputFingerprint,
            hostIntelligenceController.serviceIntelligenceSourceFingerprint,
            serviceDateIntelligenceSourceFingerprint,
            String(minute),
            guestIntelligenceStore.cacheStamp(for: serviceDateKey),
            businessIntelligenceStore.cacheStamp(from: businessRangeFrom, to: serviceDateKey),
            String(ocrCompleted)
        ].joined(separator: "|")
    }

    /// 30-day rolling window start for business intelligence.
    private var businessRangeFrom: String {
        let d = Calendar.current.date(byAdding: .day, value: -30, to: serviceDate) ?? serviceDate
        return d.reservationDateString()
    }

    /// Rebuild from cache. Automatically enriches with backend data when available.
    /// Never blocks: first call is instant; subsequent calls (after backend loads) are equally fast.
    private func rebuild() {
        let rebuildStarted = ContinuousClock.now
        let dateKey = serviceDateKey
        let activeDate = serviceDate
        let activeReservations = serviceDateReservations
        let bounds = serviceDateBounds
        let now = Date()

        // ── Service Briefing ──────────────────────────────────────────────────────
        let state = HostServiceBriefingViewStateBuilder.build(
            HostServiceBriefingViewStateBuilder.Input(
                now: now,
                selectedDate: activeDate,
                reservations: activeReservations,
                snapshot: hostIntelligenceController.decisionSnapshot,
                openTime: bounds.open,
                closeTime: bounds.close,
                selectedDateLabel: activeDate.formatted(.dateTime.weekday(.wide))
            )
        )
        let currentSourceFingerprint = serviceDateIntelligenceSourceFingerprint
        let readiness = canonicalSnapshotReadiness(
            for: dateKey,
            sourceFingerprint: currentSourceFingerprint
        )
        let packetReadiness = serviceBriefingPacketReadiness(
            for: dateKey,
            sourceFingerprint: currentSourceFingerprint
        )
        let snapshotReady = readiness.snapshot != nil
        let packetReady = packetReadiness.packet != nil
        if let packet = packetReadiness.packet {
            #if DEBUG
            print("[SERVICE_INTEL_UI_TRACE] surface=more_service_intelligence decision=use_packet reason=ready date=\(dateKey)")
            #endif
            let summaryParts = packet.compactChips
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            briefing = state.overridingHeadline(
                packet.compactLine,
                summary: summaryParts.joined(separator: " · ")
            )
            usesBriefingPacket = true
            packetSections = packet.sections
            usesCanonicalSnapshot = false
            snapshotFacts = []
        } else if let snapshot = readiness.snapshot {
            #if DEBUG
            print("[SERVICE_INTEL_UI_TRACE] surface=more_service_intelligence decision=use_snapshot reason=ready date=\(dateKey)")
            #endif
            briefing = state.overridingHeadline(snapshot.headline, summary: snapshot.subline ?? "")
            usesBriefingPacket = false
            packetSections = []
            usesCanonicalSnapshot = true
            snapshotFacts = snapshot.rankedFacts
        } else {
            #if DEBUG
            print("[SERVICE_INTEL_UI_TRACE] surface=more_service_intelligence decision=legacy reason=\(readiness.reason) date=\(dateKey)")
            #endif
            briefing = state
            usesBriefingPacket = false
            packetSections = []
            usesCanonicalSnapshot = false
            snapshotFacts = []
        }

        // ── Booking load ──────────────────────────────────────────────────────────
        if state.mode == .beforeService || state.mode == .duringService || state.mode == .futurePlanning {
            let report = buildBookingLoadReport(bounds: bounds)
            bookingItems = BookingLoadActionBuilder.items(from: report)
            bookingKnownOnlyNote = report.knownOnlyNote
        } else {
            bookingItems = []
            bookingKnownOnlyNote = ""
        }
        ServiceIntelligenceTrace.bookingSection(count: bookingItems.count)

        // ── Note + attachment signals (Phase 6 + Phase 9) ────────────────────────
        if snapshotReady || packetReady {
            signalledReservations = []
            ServiceIntelligenceTrace.noteSignals(count: 0)
        } else {
            let signalled: [(reservation: ReservationRecord, topSignals: [ReservationSignal])] = activeReservations
                .compactMap { res in
                    // Note-based signals.
                    let input = NoteSignalAnalyzer.Input(
                        reservationID: String(res.remoteID),
                        guestNote: res.guestNotes,
                        staffNote: res.staffNotes
                    )
                    var signals = NoteSignalAnalyzer.analyze(input)

                    // Attachment-based signals (label + OCR) — Phase 9.
                    let resAttachments = allAttachmentRecords.filter { $0.reservationRemoteID == res.remoteID }
                    for att in resAttachments {
                        let attInput = AttachmentSignalAnalyzer.Input(
                            reservationID: String(res.remoteID),
                            attachmentID: att.id,
                            label: att.label,
                            extractedText: att.extractedText
                        )
                        let attSignals = AttachmentSignalAnalyzer.analyze(attInput)
                        // Deduplicate by type — note signals take precedence.
                        let existingTypes = Set(signals.map { $0.type })
                        signals.append(contentsOf: attSignals.filter { !existingTypes.contains($0.type) })
                    }

                    guard !signals.isEmpty else { return nil }
                    return (res, signals)
                }
                .sorted { a, b in
                    (a.topSignals.first?.priority ?? .info) > (b.topSignals.first?.priority ?? .info)
                }
            signalledReservations = signalled
            ServiceIntelligenceTrace.noteSignals(count: signalled.count)
        }

        // ── Backend guest intelligence ────────────────────────────────────────────
        let dayResponse = guestIntelligenceStore.response(for: dateKey)
        let guestSummaries = dayResponse?.items ?? []
        let guestStatus: IntelligenceDataStatus = guestSummaries.isEmpty
            ? (guestIntelligenceStore.hasDateSummaryLoaded(dateKey: dateKey) ? .stale : .missing)
            : .loaded

        let ctx = ServiceIntelligenceContext(
            selectedDate: activeDate,
            selectedDateKey: dateKey,
            serviceMode: state.mode,
            dayReservations: activeReservations,
            historyReservations: windowReservations,
            guestSummaries: guestSummaries,
            profilePacks: [:],
            businessSummary: businessIntelligenceStore.response(
                from: businessRangeFrom, to: dateKey
            ),
            reservationAnalyticsSummary: settingsStore.analyticsSummary,
            freshness: ServiceIntelligenceFreshness(
                reservationCacheFresh: true,
                guestSummaryStatus: guestStatus,
                businessSummaryStatus: businessIntelligenceStore.response(
                    from: businessRangeFrom, to: dateKey
                ) != nil ? .loaded : .missing,
                profilePacksLoadedCount: 0,
                evaluatedAt: now
            )
        )

        guestsToKnow = ctx.prioritisedGuestTruthRows
        intelligenceSource = ctx.freshness.sourceToken
        freshnessNote = ctx.freshness.staffNote

        // ── Business insight lines ────────────────────────────────────────────────
        if let biz = ctx.businessSummary {
            businessInsightLines = BusinessIntelligenceInsightBuilder.build(
                summary: biz, systemStatus: nil
            )
        } else {
            businessInsightLines = []
        }

        // ── Traces ────────────────────────────────────────────────────────────────
        ServiceIntelligenceTrace.context(
            dateKey: dateKey,
            reservations: activeReservations.count,
            guestSummaryStatus: ctx.freshness.guestSummaryStatus.rawValue,
            businessSummaryStatus: ctx.freshness.businessSummaryStatus.rawValue,
            profilePacks: ctx.freshness.profilePacksLoadedCount,
            source: intelligenceSource
        )

        ServiceIntelligenceTrace.globalView(
            mode: state.mode,
            actions: state.primaryActions.count + state.secondaryActions.count,
            analyticsCached: settingsStore.analyticsSummary?.summary != nil,
            upcomingCount: upcomingReservationCount
        )
        #if DEBUG
        let rebuildMs = Int(rebuildStarted.duration(to: .now).pressureTraceTimeInterval * 1_000)
        print("[INTEL_PERF_TRACE] operation=Service Intelligence rebuild reservations=\(windowReservations.count) guests=\(guestsToKnow.count) durationMs=\(rebuildMs)")
        #endif
    }

    /// Schedules non-blocking background backend loads. Called once on `.onAppear`.
    /// The view automatically rebuilds when stores update via `rebuildStamp`.
    private func scheduleBackendLoads() {
        let dateKey = serviceDateKey
        // Guest intelligence for the active service date — same endpoint the Host Board already uses.
        Task(priority: .utility) {
            await guestIntelligenceStore.load(dateKey: dateKey, force: false)
        }
        // Business intelligence for the last 30 days.
        let from = businessRangeFrom
        let to = dateKey
        ServiceIntelligenceTrace.backendFeed(type: "guest_date_summary", status: "scheduled")
        ServiceIntelligenceTrace.backendFeed(type: "business_summary", status: "scheduled")
        Task(priority: .utility) {
            await businessIntelligenceStore.load(from: from, to: to)
        }
    }

    private func buildBookingLoadReport(bounds: (open: Date?, close: Date?)) -> BookingLoadReport {
        let dateKey = serviceDateKey
        let activeReservations = serviceDateReservations
        let allowsLegacy = hostIntelligenceSettingsStore.settings.useLegacyAdvisoryTableFallback
        let localActiveCount = hostTableConfigStore.activeTables.count
        let source = floorPlanStore.floorSourceStatus(
            for: dateKey,
            allowsLegacyFallback: allowsLegacy,
            localActiveTableCount: localActiveCount
        )
        let capacitySummary: TableCapacitySummary
        switch source {
        case .backend:
            capacitySummary = floorPlanStore.capacitySummary(
                for: dateKey,
                allowsLegacyFallback: allowsLegacy,
                localActiveTableCount: localActiveCount
            )
        case .legacyFallback:
            capacitySummary = TableCapacitySummary.build(
                from: hostTableConfigStore.activeTables,
                source: .legacyFallback
            )
            TableCapacityTrace.summary(capacitySummary)
        default:
            capacitySummary = TableCapacitySummary.empty(source: source)
            TableCapacityTrace.summary(capacitySummary)
        }
        let (seats, isBackendLayout) = BookingLoadSupport.plannedSeats(
            from: capacitySummary,
            localCapacity: hostTableConfigStore.totalActiveCapacity
        )
        let blocked = BookingLoadSupport.blockedMinutes(
            from: controller.availabilitySummary(for: dateKey)?.blockedSlots ?? []
        )
        var thresholds = BookingLoadThresholds.default
        thresholds.largePartyThreshold = hostIntelligenceSettingsStore.settings.largePartyThreshold
        return BookingLoadAnalyzer.analyze(
            BookingLoadAnalyzer.Input(
                date: dateKey,
                reservations: activeReservations,
                openMinutes: BookingLoadSupport.minutesOfDay(from: bounds.open),
                closeMinutes: BookingLoadSupport.minutesOfDay(from: bounds.close),
                plannedReservableSeats: seats,
                hasBackendLayout: isBackendLayout,
                blockedSlotMinutes: blocked,
                thresholds: thresholds
            )
        )
    }

    private func openReservation(for intent: StaffActionIntent) {
        guard let idString = intent.reservationID, let remoteID = Int(idString) else { return }
        guard let reservation = windowReservations.first(where: { $0.remoteID == remoteID }) else { return }
        selectedReservation = reservation
    }

    private func reservationFor(guestSummary: GuestIntelligenceSummaryDTO) -> ReservationRecord? {
        windowReservations.first { $0.remoteID == guestSummary.reservationId }
    }

    private func canonicalSnapshotReadiness(
        for dateKey: String,
        sourceFingerprint: String
    ) -> (snapshot: HostServiceIntelligenceSnapshot?, reason: String) {
        let snapshot = hostIntelligenceController.serviceIntelligenceSnapshot
        guard snapshot.dateKey == dateKey else { return (nil, "date_mismatch") }
        guard hostIntelligenceController.isEvaluatedForSelectedDate(dateKey) else {
            return (nil, "awaiting_evaluate")
        }
        let fingerprint = snapshot.inputFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fingerprint.isEmpty, fingerprint != "empty" else {
            return (nil, "empty_fingerprint")
        }
        guard hostIntelligenceController.isServiceIntelligenceSnapshotCurrent(
            dateKey: dateKey,
            sourceFingerprint: sourceFingerprint
        ) else {
            return (nil, "stale_source_fingerprint")
        }
        return (snapshot, "ready")
    }

    private func serviceBriefingPacketReadiness(
        for dateKey: String,
        sourceFingerprint: String
    ) -> (packet: HostServiceBriefingPacket?, reason: String) {
        let packet = hostIntelligenceController.serviceBriefingPacket
        guard packet.dateKey == dateKey else { return (nil, "date_mismatch") }
        guard hostIntelligenceController.isEvaluatedForSelectedDate(dateKey) else {
            return (nil, "awaiting_evaluate")
        }
        let fingerprint = packet.inputFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fingerprint.isEmpty, fingerprint != "empty" else {
            return (nil, "empty_fingerprint")
        }
        guard hostIntelligenceController.isServiceBriefingPacketCurrent(
            dateKey: dateKey,
            sourceFingerprint: sourceFingerprint
        ) else {
            return (nil, "stale_source_fingerprint")
        }
        return (packet, "ready")
    }

}

// MARK: - Guest to know row (backend-enriched)

private struct SnapshotFactRow: View {
    let fact: ServiceIntelligenceFact

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(priorityColor)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(displayHeadline)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = displayDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if fact.reservationID != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var priorityColor: Color {
        .secondary
    }

    private var displayHeadline: String {
        switch fact.category {
        case .returningGuest, .regularGuest:
            guard let name = displayName(fact.guestName) else { return fact.headline }
            if fact.headline.localizedCaseInsensitiveContains(name) {
                return fact.headline
            }
            if let lastVisit = lastVisitDisplay(from: [fact.headline, fact.detail].compactMap { $0 }) {
                return "\(firstName(from: name)) has been here before. Last visit \(lastVisit)."
            }
            return "\(firstName(from: name)) has been here before."
        case .accessibility, .guestNote:
            guard let name = displayName(fact.guestName),
                  !fact.headline.localizedCaseInsensitiveContains(name) else {
                return fact.headline
            }
            return "\(firstName(from: name)) has a seating note. Open reservation to review."
        default:
            return fact.headline
        }
    }

    private var displayDetail: String? {
        guard let detail = fact.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty else {
            return nil
        }
        if fact.category == .returningGuest || fact.category == .regularGuest,
           detail.localizedCaseInsensitiveContains("seen before") {
            return nil
        }
        return detail
    }

    private func displayName(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func firstName(from name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    private func lastVisitDisplay(from lines: [String]) -> String? {
        let marker = "Last visit "
        let terminators: [Character] = [".", "·", "\n"]
        for line in lines {
            guard let range = line.range(of: marker, options: [.caseInsensitive]) else { continue }
            let suffix = line[range.upperBound...]
            let value = String(suffix.prefix { !terminators.contains($0) })
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }
}

private struct GuestToKnowRow: View {
    let row: ServiceGuestTruthRow

    private var summary: GuestIntelligenceSummaryDTO? { row.summary }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.guestName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .foregroundStyle(.secondary)
                            .cornerRadius(4)
                    }
                }
            }
            Spacer(minLength: 0)
            if row.truth.seenBefore {
                Text(row.truth.regularity == .regular ? "Regular" : "Seen before")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var badges: [String] {
        var b: [String] = []
        if summary?.hasPriorServiceIssue == true  { b.append("Service issue") }
        if summary?.hasAllergyNote == true        { b.append("Allergy") }
        if summary?.hasAccessibilityNote == true  { b.append("Accessibility") }
        if summary?.hasSpecialOccasionNote == true { b.append("Occasion") }
        if row.truth.seenBefore && b.isEmpty {
            b.append(row.truth.regularity == .regular ? "Regular" : "Seen before")
        }
        return b
    }

}

/// Lightweight placeholder shown for the brief moment before the first cache-only build.
private struct HostServiceBriefingCardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                Text("Reading today's service…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hostBoardGlassPanel(cornerRadius: 12, strokeOpacity: 0.10)
    }
}
