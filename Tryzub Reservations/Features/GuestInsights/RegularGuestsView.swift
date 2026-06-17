//
//  RegularGuestsView.swift
//  Tryzub Reservations
//

import SwiftData
import SwiftUI

// MARK: - Regulars / Guest Memory View

struct RegularGuestsView: View {
    @EnvironmentObject private var guestIntelligenceStore: GuestIntelligenceStore
    @EnvironmentObject private var guestProfileStore: GuestProfileStore

    // Local SwiftData summaries remain an offline fallback when backend profiles are unavailable.
    @Query(sort: [
        SortDescriptor(\ReservationRecord.reservationDate),
        SortDescriptor(\ReservationRecord.reservationTime)
    ])
    private var reservations: [ReservationRecord]

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var filter: RegularGuestFilter = .allSeenBefore
    @State private var sort: RegularGuestSort = .mostReservations

    @StateObject private var store = RegularGuestsStore()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                summaryGrid
                controls
                results
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Guest Memory")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Name, phone, email, notes")
        .fontDesign(.rounded)
        .task(id: cacheKey) {
            store.updateRecords(
                reservations,
                cacheKey: cacheKey,
                searchText: debouncedSearchText,
                filter: filter,
                sort: sort
            )
        }
        .task(id: backendRequestKey) {
            await guestProfileStore.loadProfiles(
                query: debouncedSearchText,
                filter: backendFilter(for: filter),
                sort: backendSort(for: sort),
                page: 1,
                perPage: 25
            )
        }
        .task(id: searchText) {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
            store.updateDisplay(searchText: searchText, filter: filter, sort: sort)
        }
        .onChange(of: filter) { _, newValue in
            store.updateDisplay(searchText: debouncedSearchText, filter: newValue, sort: sort)
        }
        .onChange(of: sort) { _, newValue in
            store.updateDisplay(searchText: debouncedSearchText, filter: filter, sort: newValue)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Regulars / Seen Before")
                .font(.title3.weight(.medium))

            Text(sourceCopy)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let sourceCountCopy {
                Text(sourceCountCopy)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary Cards

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 10)], spacing: 10) {
            switch source {
            case .backend, .emptyBackend, .loading:
                let metrics = backendMetrics
                RegularGuestMetricCard(title: "Profiles", value: "\(metrics.profileCount)", caption: "Restaurant history")
                RegularGuestMetricCard(title: "Regulars", value: "\(metrics.regularCount)", caption: "Backend labels")
                RegularGuestMetricCard(title: "Notes found", value: "\(metrics.notesCount)", caption: "Reservation notes")
                RegularGuestMetricCard(title: "Upcoming", value: "\(metrics.upcomingCount)", caption: "Future visits")
            case .localFallback:
                RegularGuestMetricCard(title: "Regulars", value: "\(store.metrics.regularCount)", caption: "5+ visits")
                RegularGuestMetricCard(title: "Becoming", value: "\(store.metrics.becomingCount)", caption: "3-4 visits")
                RegularGuestMetricCard(title: "Notes found", value: "\(store.metrics.notesCount)", caption: "Reservation notes")
                RegularGuestMetricCard(title: "Possible matches", value: "\(store.metrics.possibleCount)", caption: "Review only")
            }
        }
    }

    // MARK: - Search / Filter / Sort Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filterOptions) { option in
                        Button {
                            filter = option
                        } label: {
                            Text(option.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(isSelectedFilter(option) ? Color(.systemBackground) : Color(.secondaryLabel))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(isSelectedFilter(option) ? ReservationUIStyle.selectedControlColor : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                                        .stroke(Color.primary.opacity(isSelectedFilter(option) ? 0.12 : 0.08), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }

            HStack {
                Text("\(visibleCount) \(visibleCount == 1 ? "guest" : "guests")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(sortOptions) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    Label(sortLabel, systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.medium))
                }
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        switch source {
        case .loading:
            HStack {
                Spacer()
                ProgressView("Loading guest profiles…")
                    .font(.caption)
                Spacer()
            }
            .padding(.vertical, 24)
        case .emptyBackend:
            ContentUnavailableView(
                "No guest profiles found yet.",
                systemImage: "person.2",
                description: Text("Try a different search.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        case .backend:
            LazyVStack(spacing: 10) {
                ForEach(guestProfileStore.listProfiles) { profile in
                    BackendGuestProfileRow(profile: profile)
                }
            }
        case .localFallback:
            if store.isComputing && store.displayedSummaries.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading guest profiles…")
                        .font(.caption)
                    Spacer()
                }
                .padding(.vertical, 24)
            } else if store.displayedSummaries.isEmpty {
                ContentUnavailableView(
                    "No Guests Found",
                    systemImage: "person.2",
                    description: Text("Try a different filter or search.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(store.displayedSummaries) { summary in
                        if let representative = representativeRecord(for: summary) {
                            NavigationLink {
                                GuestInsightsView(
                                    selectedReservation: representative,
                                    allReservations: reservations
                                )
                                .environmentObject(guestIntelligenceStore)
                            } label: {
                                RegularGuestRow(summary: summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func representativeRecord(for summary: RegularGuestSummary) -> ReservationRecord? {
        reservations.first { $0.remoteID == summary.representativeReservationID }
    }

    private var cacheKey: RegularGuestsCacheKey {
        RegularGuestsCacheKey(reservations: reservations)
    }

    private var backendRequestKey: String {
        [
            debouncedSearchText,
            backendFilter(for: filter)?.apiValue ?? "all",
            backendSort(for: sort)?.apiValue ?? "default"
        ].joined(separator: "|")
    }

    private var source: GuestMemorySource {
        if guestProfileStore.isLoadingList && !guestProfileStore.hasLoadedList && guestProfileStore.listProfiles.isEmpty {
            return .loading
        }
        if guestProfileStore.listErrorMessage != nil {
            return .localFallback
        }
        if guestProfileStore.hasLoadedList && guestProfileStore.listProfiles.isEmpty {
            return .emptyBackend
        }
        if !guestProfileStore.listProfiles.isEmpty {
            return .backend
        }
        return .loading
    }

    private var sourceCopy: String {
        switch source {
        case .backend, .emptyBackend:
            return "Based on restaurant guest profiles from the backend."
        case .localFallback:
            return "Offline view based on reservations saved on this device."
        case .loading:
            return "Loading guest profiles…"
        }
    }

    private var sourceCountCopy: String? {
        switch source {
        case .backend, .emptyBackend:
            let visible = guestProfileStore.listProfiles.count
            let total = guestProfileStore.listTotal
            if total > visible {
                return "Showing \(visible) of \(total) profiles."
            }
            return "Showing \(visible) \(visible == 1 ? "profile" : "profiles")."
        case .localFallback, .loading:
            return nil
        }
    }

    private var visibleCount: Int {
        switch source {
        case .backend:
            return guestProfileStore.listProfiles.count
        case .localFallback:
            return store.displayedSummaries.count
        case .loading, .emptyBackend:
            return 0
        }
    }

    private var filterOptions: [RegularGuestFilter] {
        switch source {
        case .localFallback:
            return RegularGuestFilter.allCases
        case .backend, .loading, .emptyBackend:
            return [.allSeenBefore, .regulars, .notesFound, .upcoming]
        }
    }

    private var backendMetrics: BackendGuestProfileMetrics {
        BackendGuestProfileMetrics(profiles: guestProfileStore.listProfiles)
    }

    private var sortOptions: [RegularGuestSort] {
        switch source {
        case .localFallback:
            return RegularGuestSort.allCases
        case .backend, .loading, .emptyBackend:
            return [.mostReservations, .upcomingFirst]
        }
    }

    private var sortLabel: String {
        sortOptions.contains(sort) ? sort.displayName : "Backend default"
    }

    private func isSelectedFilter(_ option: RegularGuestFilter) -> Bool {
        if filterOptions.contains(filter) {
            return filter == option
        }
        return option == .allSeenBefore
    }

    private func backendFilter(for filter: RegularGuestFilter) -> GuestProfileFilter? {
        switch filter {
        case .allSeenBefore:
            return .all
        case .regulars, .becomingRegular:
            return .regular
        case .notesFound, .staffNotesFound:
            return .notes
        case .upcoming:
            return .upcoming
        case .callIn, .possibleMatches, .cancellationOrNoShow:
            return .all
        }
    }

    private func backendSort(for sort: RegularGuestSort) -> GuestProfileSort? {
        switch sort {
        case .mostReservations:
            return .visitCount
        case .recentlyBooked, .firstSeen:
            return .lastSeen
        case .mostNotes:
            // Backend aggregate sorting does not expose note-count order yet.
            return nil
        case .upcomingFirst:
            return .upcoming
        case .name:
            return .name
        }
    }
}

private enum GuestMemorySource {
    case backend
    case localFallback
    case loading
    case emptyBackend
}

private struct BackendGuestProfileMetrics {
    let profileCount: Int
    let regularCount: Int
    let notesCount: Int
    let upcomingCount: Int

    init(profiles: [GuestProfileDTO]) {
        profileCount = profiles.count
        regularCount = profiles.filter { profile in
            profile.labels?.contains { $0.id == "regular_guest" } == true
                || (profile.cleanVisitCount ?? profile.totalReservations ?? 0) >= 5
        }.count
        notesCount = profiles.filter { profile in
            (profile.counts?.guestNotes ?? 0) + (profile.counts?.staffNotes ?? 0) > 0
                || profile.labels?.contains { label in
                    ["often_leaves_notes", "staff_notes_found", "birthday_note", "occasion_note", "group_details", "dietary_note", "may_expect_reply"].contains(label.id ?? "")
                } == true
        }.count
        upcomingCount = profiles.filter { ($0.upcomingCount ?? 0) > 0 || $0.nextReservation != nil }.count
    }
}

// MARK: - Regular Guest Store

private struct RegularGuestsCacheKey: Hashable {
    let visibleCount: Int
    let maxLastSyncedAt: Date?
    let maxUpdatedAt: Date?
    let maxRemoteID: Int

    init(reservations: [ReservationRecord]) {
        let visible = reservations.filter { !$0.isHidden }
        visibleCount = visible.count
        maxLastSyncedAt = visible.map(\.lastSyncedAt).max()
        maxUpdatedAt = visible.compactMap(\.updatedAt).max()
        maxRemoteID = visible.map(\.remoteID).max() ?? 0
    }
}

@MainActor
private final class RegularGuestsStore: ObservableObject {
    @Published private(set) var metrics = RegularGuestSummaryMetrics()
    @Published private(set) var displayedSummaries: [RegularGuestSummary] = []
    @Published private(set) var isComputing = false

    private let controller = RegularGuestsController()
    private var cacheKey: RegularGuestsCacheKey?
    private var allSummaries: [RegularGuestSummary] = []

    func updateRecords(
        _ reservations: [ReservationRecord],
        cacheKey: RegularGuestsCacheKey,
        searchText: String,
        filter: RegularGuestFilter,
        sort: RegularGuestSort
    ) {
        guard self.cacheKey != cacheKey else {
            updateDisplay(searchText: searchText, filter: filter, sort: sort)
            return
        }

        self.cacheKey = cacheKey
        isComputing = true
        let summaries = controller.buildSummaries(from: reservations)
        allSummaries = summaries
        metrics = controller.metrics(from: summaries)
        displayedSummaries = controller.displayedSummaries(
            from: summaries,
            searchText: searchText,
            filter: filter,
            sort: sort
        )
        isComputing = false
    }

    func updateDisplay(
        searchText: String,
        filter: RegularGuestFilter,
        sort: RegularGuestSort
    ) {
        displayedSummaries = controller.displayedSummaries(
            from: allSummaries,
            searchText: searchText,
            filter: filter,
            sort: sort
        )
    }
}

// MARK: - Regular Guest Row

private struct RegularGuestRow: View {
    let summary: RegularGuestSummary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 2) {
                Text(initials)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("\(summary.totalReservations)x")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.displayName)
                        .font(.headline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    GuestRegularityBadge(level: summary.regularityLevel)
                }

                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                FlowLayout(spacing: 6) {
                    if summary.hasStaffNotes {
                        GuestInsightBadge("Internal notes", systemImage: "note.text")
                    }
                    if summary.hasGuestNotes {
                        GuestInsightBadge("Guest notes", systemImage: "text.bubble")
                    }
                    if summary.isLikelyManualGuest {
                        GuestInsightBadge("Call-in", systemImage: "phone")
                    }
                    if summary.possibleMatchCount > 0 {
                        GuestInsightBadge("Possible match", systemImage: "person.2")
                    }
                    if summary.cancelledNoShowCount > 0 {
                        GuestInsightBadge("Prior cancellation/no-show", systemImage: "exclamationmark.circle")
                    }
                    if summary.upcomingCount > 0 {
                        GuestInsightBadge("Upcoming", systemImage: "calendar")
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var initials: String {
        let parts = summary.displayName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
        let value = String(parts).uppercased()
        return value.isEmpty ? "?" : value
    }

    private var detailLine: String {
        var parts: [String] = []

        if let time = summary.mostCommonTime {
            parts.append("Usually \(time)")
        }

        if let partySize = summary.mostCommonPartySize {
            parts.append("Party of \(partySize)")
        }

        if let lastBooked = summary.lastBookedDate {
            parts.append("Last booked \(lastBooked)")
        }

        if summary.visitsLast90Days > 0 {
            parts.append("\(summary.visitsLast90Days) recent")
        }

        return parts.isEmpty ? "\(summary.totalReservations) visits" : parts.joined(separator: " · ")
    }
}

// MARK: - Backend Guest Profile Row

private struct BackendGuestProfileRow: View {
    let profile: GuestProfileDTO

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 2) {
                Text(initials)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("\(visitCount)x")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(displayName)
                        .font(.headline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    if profile.stale == true {
                        Text("Profile updating")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                    }
                }

                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                FlowLayout(spacing: 6) {
                    ForEach(labelTitles, id: \.self) { title in
                        GuestInsightBadge(title, systemImage: "tag")
                    }
                    if let nextReservationLine {
                        GuestInsightBadge(nextReservationLine, systemImage: "calendar")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var displayName: String {
        cleaned(profile.primaryName) ?? "Guest"
    }

    private var visitCount: Int {
        max(0, profile.cleanVisitCount ?? profile.totalReservations ?? 0)
    }

    private var initials: String {
        let parts = displayName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
        let value = String(parts).uppercased()
        return value.isEmpty ? "?" : value
    }

    private var detailLine: String {
        var parts: [String] = []

        if let lastSeen = cleaned(profile.lastSeenDate) {
            parts.append("Last seen \(lastSeen)")
        }
        if let partySize = profile.usualPartySize ?? profile.preferences?.usualPartySize {
            parts.append("Usually party of \(partySize)")
        }
        if let hour = profile.usualHour ?? profile.preferences?.usualHour {
            parts.append("Usually \(hourDisplay(hour))")
        }
        if let weekday = profile.usualWeekday ?? profile.preferences?.usualWeekday {
            parts.append(weekdayDisplay(weekday))
        }

        return parts.isEmpty ? "\(visitCount) \(visitCount == 1 ? "visit" : "visits")" : parts.joined(separator: " · ")
    }

    private var nextReservationLine: String? {
        guard let next = profile.nextReservation else { return nil }
        let date = cleaned(next.reservationDate) ?? cleaned(next.date)
        let time = cleaned(next.reservationTime) ?? cleaned(next.time)
        let party = next.partySize.map { "\($0) guests" }
        let parts = [date, time, party].compactMap { $0 }
        guard !parts.isEmpty else { return "Upcoming" }
        return "Next " + parts.joined(separator: " · ")
    }

    private var labelTitles: [String] {
        return Array(
            (profile.labels ?? [])
                .compactMap { safeLabelTitle($0) }
                .prefix(4)
        )
    }

    private func safeLabelTitle(_ label: GuestProfileLabelDTO) -> String? {
        guard let title = cleaned(label.title) else { return nil }
        let values = [
            label.id,
            label.title,
            label.category,
            label.source
        ]
        if values.contains(where: containsUnsupportedLabelToken) {
            return nil
        }
        return title
    }

    private func containsUnsupportedLabelToken(_ value: String?) -> Bool {
        guard let value = cleaned(value) else { return false }
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        let exactBlocked = [
            "vip",
            "high spender",
            "highspender",
            "wine drinker",
            "winedrinker",
            "cocktail guest",
            "cocktailguest",
            "risky",
            "risk",
            "problem",
            "problem guest",
            "problemguest",
            "suspicious",
            "suspicious guest",
            "suspiciousguest",
            "concerned",
            "concerned guest",
            "concernedguest"
        ]
        if exactBlocked.contains(normalized) || exactBlocked.contains(compact) {
            return true
        }
        return normalized.contains("high spender")
            || normalized.contains("wine")
            || normalized.contains("cocktail")
            || normalized.contains("risky")
            || normalized.contains("problem guest")
            || normalized.contains("suspicious")
            || normalized.contains("concerned guest")
    }

    private func hourDisplay(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        let suffix = normalized >= 12 ? "PM" : "AM"
        let displayHour = normalized % 12 == 0 ? 12 : normalized % 12
        return "\(displayHour) \(suffix)"
    }

    private func weekdayDisplay(_ weekday: Int) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard weekday >= 0, weekday < names.count else { return "Often same weekday" }
        return "Often \(names[weekday])"
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Metric Card

private struct RegularGuestMetricCard: View {
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
                .monospacedDigit()
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Guest Memory") {
    NavigationStack {
        RegularGuestsView()
    }
    .modelContainer(ReservationPreviewData.previewContainer)
    .environmentObject(GuestIntelligenceStore(apiClient: ReservationsAPIClient.preview))
    .environmentObject(GuestProfileStore(apiClient: ReservationsAPIClient.preview))
}
#endif
