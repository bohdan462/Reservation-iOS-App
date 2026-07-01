//
//  GuestInsightsView.swift
//  Tryzub Reservations
//

import SwiftUI
import Charts

// MARK: - Guest Insights View

struct GuestInsightsView: View {
    let selectedReservation: ReservationRecord
    let allReservations: [ReservationRecord]

    @EnvironmentObject private var guestIntelligenceStore: GuestIntelligenceStore
    @EnvironmentObject private var guestProfileStore: GuestProfileStore
    @StateObject private var profileFacade = GuestProfileFacade()

    private var report: GuestInsightReport? {
        profileFacade.localReport
    }

    private var viewState: GuestProfileViewState? {
        profileFacade.viewState
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let viewState {
                    GuestServiceProfileContent(presentation: viewState.serviceProfile)
                } else {
                    GuestInsightReservationShell(reservation: selectedReservation)
                    TryzubLoadingRow(title: "Loading guest history…")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .padding(.bottom, ReservationLayout.scrollBottomInset)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Guest history")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fontDesign(.rounded)
        .onChange(of: cacheKey, initial: true) { _, _ in
            profileFacade.updateReservationProvider {
                (selectedReservation, allReservations)
            }
        }
        .task(id: cacheKey) {
            profileFacade.loadIfNeeded(
                reservation: selectedReservation,
                historyPool: allReservations,
                store: guestIntelligenceStore,
                guestProfileStore: guestProfileStore
            )
        }
        .task(id: guestInsightsMergeTraceKey) {
            guard let report else { return }
            guestIntelligenceStore.recordMergePresentation(
                surface: "guest_insights",
                reservationID: selectedReservation.remoteID,
                guestName: selectedReservation.guestName,
                localReport: report,
                selectedReservation: selectedReservation,
                reservationPool: allReservations,
                dateKey: selectedReservation.reservationDate,
                semanticStamp: guestIntelligenceStore.semanticProfileStamp(
                    for: selectedReservation.remoteID,
                    dateKey: selectedReservation.reservationDate
                )
            )
        }
    }

    private var profilePack: GuestIntelligenceProfilePackDTO? {
        guestIntelligenceStore.profilePack(for: selectedReservation.remoteID)
    }

    private var serverVisitRows: [GuestInsightsProfilePresentation.ServerVisitRow] {
        GuestInsightsProfilePresentation.serverVisitRows(from: profilePack)
    }

    private var localCachedHistory: GuestHistorySemantics.GuestInsightsBookingHistoryPresentation? {
        guard let report else { return nil }
        return GuestHistorySemantics.localCachedHistoryPresentation(
            localReport: report,
            profilePack: profilePack
        )
    }

    private var mergedContext: GuestHistorySemantics.GuestInsightsMergedContext? {
        guard let report else { return nil }
        let reservationID = selectedReservation.remoteID
        let dateKey = selectedReservation.reservationDate
        let serverSummary = guestIntelligenceStore.summary(for: reservationID, dateKey: dateKey)
        let serverAnswered = guestIntelligenceStore.hasServerAnswer(for: reservationID, dateKey: dateKey)
        return GuestHistorySemantics.insightsMergedContext(
            guestName: selectedReservation.guestName,
            localReport: report,
            serverSummary: serverSummary,
            serverAnswered: serverAnswered,
            profileStamp: guestIntelligenceStore.semanticProfileStamp(for: reservationID, dateKey: dateKey),
            profilePack: profilePack,
            selectedReservation: selectedReservation,
            reservationPool: allReservations
        )
    }

    private func hasProfileSummaryContent(_ pack: GuestIntelligenceProfilePackDTO) -> Bool {
        let summary = pack.profileSummary?.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !summary.isEmpty || !(pack.profileSummary?.managementNotes.isEmpty ?? true)
    }

    private var cacheKey: GuestInsightsCacheKey {
        GuestInsightsCacheKey(
            selectedReservation: selectedReservation,
            reservations: allReservations
        )
    }

    private var guestInsightsMergeTraceKey: String? {
        guard let report else { return nil }
        let reservationID = selectedReservation.remoteID
        let dateKey = selectedReservation.reservationDate
        return GuestHistorySemantics.mergePresentationTaskKey(
            surface: "guest_insights",
            guestName: selectedReservation.guestName,
            localReport: report,
            serverSummary: guestIntelligenceStore.summary(for: reservationID, dateKey: dateKey),
            serverAnswered: guestIntelligenceStore.hasServerAnswer(for: reservationID, dateKey: dateKey),
            profilePack: guestIntelligenceStore.profilePack(for: reservationID),
            selectedReservation: selectedReservation,
            reservationPool: allReservations
        )
    }

    @ViewBuilder
    private func guestProfileShell(state: GuestProfileViewState) -> some View {
        GuestInsightCard(title: "Guest", systemImage: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 6) {
                Text(state.header.guestName)
                    .font(.title3.weight(.semibold))
                Text(state.header.reservationLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(state.header.historyTitle)
                    .font(.subheadline.weight(.semibold))
                Text(state.header.historyDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        if let profilePack {
            if hasProfileSummaryContent(profilePack) {
                GuestInsightProfileSummarySection(pack: profilePack)
            }
            if !state.preferenceLines.isEmpty {
                GuestInsightBackendPreferencesSection(pack: profilePack)
            }
            if !state.priorNoteLines.isEmpty {
                GuestInsightPriorNotesSection(pack: profilePack)
            }
            if !state.visitAnalyticsLines.isEmpty {
                GuestInsightVisitPatternSection(pack: profilePack)
            }
            if !state.serverHistory.isEmpty {
                GuestInsightServerHistorySection(rows: serverVisitRows)
            }
        } else if state.loadingState == .loadingServerProfile || state.loadingState == .loadingBoth {
            GuestInsightCard(title: "Guest history", systemImage: "arrow.triangle.2.circlepath") {
                TryzubLoadingRow(title: "Loading guest history…")
            }
        }

        if state.loadingState == .calculatingLocalCache || state.loadingState == .loadingBoth {
            GuestInsightCard(title: "Local cache insights", systemImage: "internaldrive") {
                TryzubLoadingRow(title: "Calculating local cache insights...")
            }
        }
    }

}

private struct GuestServiceProfileContent: View {
    let presentation: GuestServiceProfilePresentation
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    guestHeader
                    todaySection
                    historyMetrics
                    patternsSection
                    watchoutsSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 14) {
                    pastVisitsSection
                    notesSection
                    upcomingSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                guestHeader
                todaySection
                historyMetrics
                watchoutsSection
                pastVisitsSection
                notesSection
                patternsSection
                upcomingSection
            }
        }
    }

    private var guestHeader: some View {
        GuestInsightCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.guestName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Text(presentation.status.title)
                    .font(.headline.weight(.semibold))
                if let detail = presentation.status.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var todaySection: some View {
        GuestInsightCard(title: presentation.today.sectionTitle, systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 9) {
                if let dateLine = presentation.today.dateLine {
                    Text(dateLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(presentation.today.primaryLine)
                    .font(.headline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                GuestServiceFactLine(
                    text: presentation.today.tableLine,
                    systemImage: presentation.today.tableLine == "No table picked" ? "tablecells.badge.ellipsis" : "tablecells"
                )
                if let reminder = presentation.today.reminderLine {
                    GuestServiceFactLine(
                        text: reminder,
                        systemImage: reminder == "Reminder follow-up needed" ? "bell.slash" : "bell.badge.checkmark"
                    )
                }
                ForEach(presentation.today.noteLines, id: \.self) { line in
                    GuestServiceFactLine(text: line, systemImage: "note.text")
                }
            }
        }
    }

    private var historyMetrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
            ForEach(presentation.metrics) { metric in
                GuestInsightMetricCard(title: metric.title, value: metric.value, caption: metric.caption)
            }
        }
    }

    private var pastVisitsSection: some View {
        GuestInsightCard(title: "Past visits", systemImage: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                if presentation.pastVisits.isEmpty {
                    GuestInsightEmptyState("No past visits found.")
                } else {
                    ForEach(Array(presentation.pastVisits.prefix(5))) { visit in
                        GuestVisitEvidenceRow(visit: visit, showsNotes: true)
                    }
                    if presentation.pastVisits.count > 5 {
                        Text("Showing 5 of \(presentation.pastVisits.count) most recent visits.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var upcomingSection: some View {
        GuestInsightCard(title: "Upcoming", systemImage: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 12) {
                if presentation.upcomingReservations.isEmpty {
                    GuestInsightEmptyState("No upcoming reservations found.")
                } else {
                    ForEach(presentation.upcomingReservations) { visit in
                        GuestVisitEvidenceRow(visit: visit, showsNotes: false)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        GuestInsightCard(title: "Notes history", systemImage: "note.text") {
            VStack(alignment: .leading, spacing: 12) {
                if presentation.notes.isEmpty {
                    GuestInsightEmptyState("No guest or staff notes saved yet.")
                } else {
                    ForEach(presentation.notes) { note in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(note.displayDate) · \(note.kind.rawValue)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(note.text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var patternsSection: some View {
        GuestInsightCard(title: "Patterns", systemImage: "chart.bar.doc.horizontal") {
            VStack(alignment: .leading, spacing: 10) {
                if presentation.patterns.isEmpty {
                    GuestInsightEmptyState("Not enough history for patterns yet.")
                } else {
                    ForEach(presentation.patterns) { pattern in
                        GuestServiceFactLine(text: pattern.text, systemImage: pattern.systemImage)
                    }
                }
            }
        }
    }

    private var watchoutsSection: some View {
        GuestInsightCard(title: "Watchouts", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 11) {
                if presentation.watchouts.isEmpty {
                    GuestInsightEmptyState("Nothing special to check.")
                } else {
                    ForEach(presentation.watchouts) { item in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: item.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                if let detail = item.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct GuestServiceFactLine: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label {
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }
}

private struct GuestVisitEvidenceRow: View {
    let visit: GuestServiceProfilePresentation.Visit
    let showsNotes: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(visit.displayDate) · \(visit.displayTime) · Party of \(visit.partySize)")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(visit.status) · \(visit.table)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if showsNotes, let note = visit.guestNote {
                Text("Guest note: \(note)")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsNotes, let note = visit.staffNote {
                Text("Staff note: \(note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct GuestInsightEmptyState: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GuestInsightAggregateHeader: View {
    let state: GuestProfileViewState

    var body: some View {
        GuestInsightCard(title: "Guest", systemImage: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(state.header.guestName)
                        .font(.title3.weight(.semibold))
                    Spacer(minLength: 0)
                    if state.aggregateProfile?.showsUpdatingBadge == true {
                        GuestInsightBadge("Updating guest history", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Text(state.header.reservationLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(state.header.historyTitle)
                    .font(.subheadline.weight(.semibold))
                Text(state.header.historyDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GuestInsightAggregateProfileSection: View {
    let aggregateProfile: GuestInsightsProfilePresentation.AggregateProfileState

    var body: some View {
        if !aggregateProfile.countCards.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 10)], spacing: 10) {
                ForEach(aggregateProfile.countCards) { metric in
                    GuestInsightMetricCard(
                        title: metric.title,
                        value: metric.value,
                        caption: metric.caption
                    )
                }
            }
        }

        GuestInsightCard(title: "Guest history", systemImage: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                Text(aggregateProfile.sourceLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(aggregateProfile.summaryLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.subheadline)
                }

                if !aggregateProfile.labels.isEmpty {
                    FlowLayout(spacing: 7) {
                        ForEach(aggregateProfile.labels) { label in
                            GuestInsightBadge(label.title, systemImage: "tag")
                        }
                    }
                }

                if let upcomingLine = aggregateProfile.upcomingLine {
                    Text(upcomingLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if !aggregateProfile.preferenceLines.isEmpty {
            GuestInsightCard(title: "Patterns", systemImage: "chart.bar.doc.horizontal") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(aggregateProfile.preferenceLines, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                    }
                }
            }
        }

        if !aggregateProfile.noteLines.isEmpty || aggregateProfile.labels.contains(where: { $0.detail != nil || $0.evidence != nil }) {
            GuestInsightCard(title: "Notes and evidence", systemImage: "note.text") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(aggregateProfile.noteLines, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                    }
                    ForEach(aggregateProfile.labels) { label in
                        if let detail = label.detail {
                            Text("\(label.title): \(detail)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let evidence = label.evidence {
                            Text("\(label.title): \(evidence)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct GuestInsightReservationShell: View {
    let reservation: ReservationRecord

    var body: some View {
        GuestInsightCard(title: "Guest", systemImage: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 6) {
                Text(reservation.guestName)
                    .font(.title3.weight(.semibold))
                Text("\(reservation.displayDate) at \(reservation.displayTime) · party of \(reservation.partySize)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GuestInsightsCacheKey: Hashable {
    let selectedID: Int
    let visibleCount: Int
    let maxLastSyncedAt: Date?
    let maxUpdatedAt: Date?
    let guestIntelligenceStamp: String

    init(
        selectedReservation: ReservationRecord,
        reservations: [ReservationRecord],
        guestIntelligenceStamp: String = ""
    ) {
        selectedID = selectedReservation.remoteID
        let visible = reservations.filter { !$0.isHidden }
        visibleCount = visible.count
        maxLastSyncedAt = visible.map(\.lastSyncedAt).max()
        maxUpdatedAt = visible.compactMap(\.updatedAt).max()
        self.guestIntelligenceStamp = guestIntelligenceStamp
    }
}

// MARK: - Header

private struct GuestInsightHeader: View {
    let report: GuestInsightReport
    let mergedContext: GuestHistorySemantics.GuestInsightsMergedContext

    var body: some View {
        GuestInsightCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.text.rectangle")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(Color(.systemGray6), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.displayName)
                            .font(.title3.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        VStack(alignment: .leading, spacing: 2) {
                            if let phone = report.primaryPhone {
                                Text(phone)
                                    .lineLimit(1)
                            }
                            if let email = report.primaryEmail {
                                Text(email)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            if !report.hasReliableContactIdentity {
                                Text("No reliable contact on file")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(mergedContext.historyTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(mergedContext.historyDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let lastSeen = mergedContext.serverLastSeenDisplay {
                        Text("Last seen \(lastSeen)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                FlowLayout(spacing: 7) {
                    if let mergedRegularity = mergedContext.mergedRegularity,
                       !shouldHideRegularityBadge(
                           historyTitle: mergedContext.historyTitle,
                           regularity: mergedRegularity
                       ) {
                        GuestRegularityBadge(level: mergedRegularity)
                    }
                    if report.isLikelyManualGuest {
                        GuestInsightBadge("Manual / Call-in", systemImage: "phone")
                    }
                    if !report.possibleMatches.isEmpty {
                        GuestInsightBadge("Possible matches", systemImage: "person.2")
                    }
                    if report.primaryEmail == nil {
                        GuestInsightBadge("No real email", systemImage: "envelope.badge")
                    }
                    if !report.staffMentionHistory.isEmpty {
                        GuestInsightBadge("Staff notes found", systemImage: "note.text")
                    }
                }
            }
        }
    }

    private func shouldHideRegularityBadge(
        historyTitle: String,
        regularity: GuestRegularityLevel
    ) -> Bool {
        historyTitle == "Seen before" && regularity == .seenBefore
    }
}

// MARK: - Snapshot Cards

private struct GuestInsightSnapshotGrid: View {
    let report: GuestInsightReport
    let metrics: GuestHistorySemantics.GuestInsightsMetricsPresentation
    let mergedSource: GuestHistorySemantics.MergedHistorySource

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 142), spacing: 10)]
    }

    private var scopeCaption: String? {
        switch metrics.source {
        case .backendSummary:
            return "Server-backed summary for this guest."
        case .localCache:
            return "Local cache supplement - counts from this device only."
        case .merged:
            if mergedSource == .unknownNotLoaded {
                return "Guest history loading."
            }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let scopeCaption {
                Text(scopeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 10) {
            GuestInsightMetricCard(
                title: metrics.title,
                value: metrics.value,
                caption: metrics.caption
            )

            GuestInsightMetricCard(
                title: "Last booked",
                value: report.summary.lastBookedDate ?? "-",
                caption: recencyCaption
            )

            GuestInsightMetricCard(
                title: "Usual time",
                value: report.summary.mostCommonReservationTime ?? "-",
                caption: report.summary.mostCommonWeekday ?? "Based on cached records"
            )

            GuestInsightMetricCard(
                title: "Party size",
                value: report.summary.mostCommonPartySize.map { "\($0)" } ?? "-",
                caption: partySizeCaption
            )

            GuestInsightMetricCard(
                title: "Source",
                value: sourceValue,
                caption: sourceCaption
            )

            GuestInsightMetricCard(
                title: "Notes",
                value: "\(report.hospitalitySnapshot.noteCount)",
                caption: notesCaption
            )
            }
        }
    }

    private var recencyCaption: String {
        if let upcoming = report.hospitalitySnapshot.lastUpcomingReservationDate {
            return "Next: \(upcoming)"
        }

        if report.hospitalitySnapshot.isNotRecent {
            return "Not recent"
        }

        if report.hospitalitySnapshot.isRecent {
            return "Recent"
        }

        return "\(report.summary.pastReservationsCount) past"
    }

    private var partySizeCaption: String {
        if let average = report.hospitalitySnapshot.averagePartySize,
           let largest = report.hospitalitySnapshot.largestPartySize {
            return "Avg \(String(format: "%.1f", average)) · Max \(largest)"
        }

        return "No pattern yet"
    }

    private var sourceValue: String {
        if report.bookingBehavior.manualCount > 0,
           report.bookingBehavior.onlineCount > 0 {
            return "Mixed"
        }

        if report.bookingBehavior.manualCount > 0 {
            return "Call-in"
        }

        return "Online"
    }

    private var sourceCaption: String {
        "\(report.bookingBehavior.onlineCount) online · \(report.bookingBehavior.manualCount) call-in"
    }

    private var notesCaption: String {
        if report.hospitalitySnapshot.hasStaffNotes {
            return "Staff notes found"
        }

        if report.hospitalitySnapshot.hasGuestNotes {
            return "Guest notes found"
        }

        return "No prior notes found"
    }
}

// MARK: - Operational Notes

private struct GuestInsightNotesSection: View {
    let report: GuestInsightReport

    var body: some View {
        GuestInsightCard(title: "Operational Notes", systemImage: "note.text") {
            VStack(alignment: .leading, spacing: 12) {
                if let staffNote = report.summary.lastStaffNote {
                    GuestInsightNoteBlock(
                        title: "Most recent staff note",
                        note: staffNote,
                        emphasized: true
                    )
                }

                if let guestNote = report.summary.lastGuestNote {
                    GuestInsightNoteBlock(
                        title: "Recent guest note",
                        note: guestNote,
                        emphasized: false
                    )
                }

                if report.noteHistory.isEmpty {
                    Text("No previous guest or staff notes found in the local cache.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(report.noteHistory) { note in
                                GuestInsightNoteBlock(
                                    title: "\(note.noteType.displayName) note",
                                    note: note,
                                    emphasized: false
                                )
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("View all notes")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary.opacity(0.82))
                    }
                }
            }
        }
    }
}

// MARK: - Backend Profile Sections

private struct GuestInsightProfileSummarySection: View {
    let pack: GuestIntelligenceProfilePackDTO

    var body: some View {
        GuestInsightCard(title: "Guest history", systemImage: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: 8) {
                if let summary = pack.profileSummary?.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                }
                if let managementNotes = pack.profileSummary?.managementNotes,
                   !managementNotes.isEmpty {
                    ForEach(managementNotes, id: \.self) { note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct GuestInsightBackendPreferencesSection: View {
    let pack: GuestIntelligenceProfilePackDTO

    var body: some View {
        GuestInsightCard(title: "Preferences", systemImage: "chart.bar.doc.horizontal") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(GuestInsightsProfilePresentation.preferenceLines(from: pack), id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                }
            }
        }
    }
}

private struct GuestInsightPriorNotesSection: View {
    let pack: GuestIntelligenceProfilePackDTO

    var body: some View {
        GuestInsightCard(title: "Prior Notes", systemImage: "note.text") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(GuestInsightsProfilePresentation.priorNoteLines(from: pack), id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                }
            }
        }
    }
}

private struct GuestInsightVisitPatternSection: View {
    let pack: GuestIntelligenceProfilePackDTO

    var body: some View {
        GuestInsightCard(title: "Visit Pattern", systemImage: "chart.xyaxis.line") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(GuestInsightsProfilePresentation.visitAnalyticsLines(from: pack), id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                }
            }
        }
    }
}

private struct GuestInsightServerHistorySection: View {
    let rows: [GuestInsightsProfilePresentation.ServerVisitRow]

    var body: some View {
        GuestInsightCard(title: "Past visits", systemImage: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Earlier guest visits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.headline)
                            .font(.subheadline.weight(.semibold))
                        Text(row.detailLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let guestNoteLine = row.guestNoteLine {
                            Text(guestNoteLine)
                                .font(.caption)
                        }
                        if let staffNoteLine = row.staffNoteLine {
                            Text(staffNoteLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Booking History

private struct GuestInsightBookingHistorySection: View {
    let report: GuestInsightReport
    let bookingHistory: GuestHistorySemantics.GuestInsightsBookingHistoryPresentation

    var body: some View {
        GuestInsightCard(title: bookingHistory.sectionTitle, systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 10) {
                if let scopeNote = bookingHistory.scopeNote {
                    Text(scopeNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if report.bookingHistory.isEmpty {
                    Text("No locally cached bookings found.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    if !pastVisits.isEmpty {
                        Text("Past visits")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(pastVisits) { item in
                            GuestInsightBookingRow(item: item)
                        }
                    }
                    if !upcomingReservations.isEmpty {
                        Text("Upcoming reservations")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(upcomingReservations) { item in
                            GuestInsightBookingRow(item: item)
                        }
                    }
                }
            }
        }
    }

    private var selectedSortKey: String {
        guard let selected = report.bookingHistory.first(where: {
            $0.reservationID == report.selectedReservationID
        }) else { return "" }
        return "\(selected.date) \(selected.time)"
    }

    private var pastVisits: [GuestBookingHistoryItem] {
        report.bookingHistory.filter { item in
            let clean = item.status == .confirmed || item.status == .seated || item.status == .completed
            return clean && "\(item.date) \(item.time)" < selectedSortKey
        }
    }

    private var upcomingReservations: [GuestBookingHistoryItem] {
        report.bookingHistory.filter { item in
            "\(item.date) \(item.time)" >= selectedSortKey
                && item.status != .cancelled
                && item.status != .noShow
        }
    }
}

// MARK: - Preferences

private struct GuestInsightPreferencesSection: View {
    let report: GuestInsightReport

    var body: some View {
        GuestInsightCard(title: "Local cache preferences", systemImage: "internaldrive") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Patterns from reservations stored on this device only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if report.preferredTimes.isEmpty,
                   report.preferredWeekdays.isEmpty,
                   report.partySizeStats.mostCommon == nil {
                    Text("Not enough matching history for useful patterns yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    if !report.preferredTimes.isEmpty {
                        GuestInsightBarChart(
                            title: "Common times",
                            bars: report.preferredTimes.prefix(5).map {
                                GuestInsightBar(label: $0.bucket, count: $0.count)
                            }
                        )
                    }

                    if !report.preferredWeekdays.isEmpty {
                        GuestInsightBarChart(
                            title: "Common weekdays",
                            bars: report.preferredWeekdays.prefix(7).map {
                                GuestInsightBar(label: String($0.weekday.prefix(3)), count: $0.count)
                            }
                        )
                    }

                    preferenceGroup(
                        title: "Party sizes",
                        values: partySizeValues
                    )

                    preferenceGroup(
                        title: "Booking source",
                        values: bookingSourceValues
                    )
                }
            }
        }
    }

    private var partySizeValues: [String] {
        var values: [String] = []
        if let mostCommon = report.partySizeStats.mostCommon {
            values.append("Often party of \(mostCommon)")
        }
        if let min = report.partySizeStats.min, let max = report.partySizeStats.max, min != max {
            values.append("Range \(min)-\(max)")
        }
        if report.partySizeStats.largePartyCount > 0 {
            values.append("\(report.partySizeStats.largePartyCount) large party")
        }
        return values
    }

    private var bookingSourceValues: [String] {
        var values = [
            "\(report.bookingBehavior.onlineCount) online",
            "\(report.bookingBehavior.manualCount) call-in"
        ]

        if let table = report.bookingBehavior.commonTable {
            values.append("Common table \(table)")
        }

        if report.bookingBehavior.upcomingActiveCount > 0 {
            values.append("\(report.bookingBehavior.upcomingActiveCount) upcoming")
        }

        if report.bookingBehavior.cancelledNoShowCount > 0 {
            values.append("\(report.bookingBehavior.cancelledNoShowCount) cancelled/no-show")
        }

        return values
    }

    private func preferenceGroup(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if values.isEmpty {
                Text("-")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 7) {
                    ForEach(values, id: \.self) { value in
                        GuestInsightBadge(value, systemImage: nil)
                    }
                }
            }
        }
    }
}

// MARK: - Possible Matches

private struct GuestInsightPossibleMatchesSection: View {
    let report: GuestInsightReport

    var body: some View {
        if !report.possibleMatches.isEmpty {
            GuestInsightCard(title: "Possible Same Guest", systemImage: "person.2") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Possible same guest matches with shared phone/email or similar full name evidence. Review only; nothing is merged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(report.possibleMatches) { match in
                        GuestInsightMatchRow(match: match)
                    }
                }
            }
        }
    }
}

// MARK: - Watchouts

private struct GuestInsightWarningsSection: View {
    let warnings: [GuestInsightWarning]

    var body: some View {
        if !warnings.isEmpty {
            GuestInsightCard(title: "Watchouts", systemImage: "exclamationmark.circle") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(warnings) { warning in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: warning.systemImage)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(warning.title)
                                    .font(.subheadline.weight(.medium))
                                Text(warning.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - History Rows

private struct GuestInsightBookingRow: View {
    let item: GuestBookingHistoryItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayDate)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(item.displayTime)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            .frame(width: 78, alignment: .leading)

            ReservationDashedLine(isVertical: true)
                .frame(width: 1, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(item.partySize) \(item.partySize == 1 ? "guest" : "guests")")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 7) {
                    Text(item.status.displayName)
                    Text(item.table.map { "Table \($0)" } ?? "No table")
                    if item.hasNotes {
                        Text("Notes")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(item.source.displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
        .padding(.vertical, 4)
    }
}

private struct GuestInsightMatchRow: View {
    let match: GuestMatchedReservation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(match.guestName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(match.confidence.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }

            Text("\(match.displayDate) at \(match.displayTime) · \(match.partySize) \(match.partySize == 1 ? "guest" : "guests")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            FlowLayout(spacing: 6) {
                ForEach(match.matchReasons, id: \.self) { reason in
                    GuestInsightBadge(reason, systemImage: nil)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct GuestInsightNoteBlock: View {
    let title: String
    let note: GuestNoteHistoryItem
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(note.displayDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(note.text)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(emphasized ? 12 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            emphasized ? Color(.systemGray6) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

// MARK: - Shared Guest Insight Components

struct GuestInsightBar: Identifiable {
    let label: String
    let count: Int
    var id: String { label }
}

private struct GuestInsightBarChart: View {
    let title: String
    let bars: [GuestInsightBar]

    private var maxCount: Int { max(bars.map(\.count).max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Chart(bars) { bar in
                BarMark(
                    x: .value("Count", bar.count),
                    y: .value("Label", bar.label),
                    height: .ratio(0.62)
                )
                .foregroundStyle(TryzubColors.primaryControl.opacity(bar.count == maxCount ? 0.85 : 0.32))
                .cornerRadius(5)
                .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                    Text("\(bar.count)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: Array(bars.map(\.label).reversed()))
            .chartXScale(domain: 0...max(Double(maxCount) * 1.18, 1))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(preset: .aligned, position: .leading) { _ in
                    AxisValueLabel()
                        .font(.caption.weight(.medium))
                }
            }
            .frame(height: (CGFloat(bars.count) * 30 + 4).tryzubFinitePositiveLayoutValue)
        }
    }
}

private struct GuestInsightMetricCard: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct GuestInsightCard<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label(title, systemImage: systemImage ?? "circle")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

struct GuestRegularityBadge: View {
    let level: GuestRegularityLevel

    var body: some View {
        Label(level.displayName, systemImage: systemImage)
            .font(.caption.weight(level.rank >= GuestRegularityLevel.regular.rank ? .semibold : .medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                    .stroke(Color.primary.opacity(level.rank >= GuestRegularityLevel.regular.rank ? 0.16 : 0.08), lineWidth: 1)
            }
    }

    private var systemImage: String {
        switch level {
        case .firstTime:
            return "person"
        case .seenBefore:
            return "checkmark.circle"
        case .becomingRegular:
            return "leaf"
        case .regular:
            return "star"
        case .frequentRegular:
            return "star.fill"
        }
    }

    private var foreground: Color {
        switch level {
        case .regular, .frequentRegular:
            return Color(.label)
        case .becomingRegular:
            return Color(.secondaryLabel)
        case .firstTime, .seenBefore:
            return Color(.secondaryLabel)
        }
    }

    private var background: Color {
        switch level {
        case .regular, .frequentRegular:
            return Color(.label).opacity(0.08)
        case .becomingRegular:
            return Color(.systemGray5).opacity(0.72)
        case .firstTime, .seenBefore:
            return Color(.systemGray6)
        }
    }
}

struct GuestInsightBadge: View {
    let text: String
    let systemImage: String?

    init(_ text: String, systemImage: String?) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Shared Flow Layout

struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                content
            }
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Guest Insights") {
    NavigationStack {
        GuestInsightsView(
            selectedReservation: ReservationPreviewData.guestInsightsRecord,
            allReservations: ReservationPreviewData.allRecords
        )
    }
    .modelContainer(ReservationPreviewData.previewContainer)
    .environmentObject(GuestIntelligenceStore(apiClient: ReservationsAPIClient.preview))
    .environmentObject(GuestProfileStore(apiClient: ReservationsAPIClient.preview))
}
#endif
