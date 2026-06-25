//
//  RegularGuestsView.swift
//  Tryzub Reservations
//

import SwiftData
import SwiftUI

// MARK: - Regulars / Guest Memory View

struct RegularGuestsView: View {
    @Query(sort: [
        SortDescriptor(\GuestProfileCacheRecord.cleanVisitCount, order: .reverse),
        SortDescriptor(\GuestProfileCacheRecord.totalReservations, order: .reverse),
        SortDescriptor(\GuestProfileCacheRecord.fetchedAt, order: .reverse)
    ])
    private var cachedProfiles: [GuestProfileCacheRecord]

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var filter: RegularGuestFilter = .allSeenBefore
    @State private var sort: RegularGuestSort = .mostReservations

    @AppStorage("tryzub.guestProfiles.fullListSyncCompleted.v1")
    private var fullListSyncCompleted = false
    @AppStorage("tryzub.guestProfiles.backendProfileTotal.v1")
    private var backendProfileTotal = -1

    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

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
        .task(id: searchText) {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
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
            let metrics = cacheMetrics
            RegularGuestMetricCard(title: "Profiles", value: "\(metrics.profileCount)", caption: "Saved on iPad")
            RegularGuestMetricCard(title: "Regulars", value: "\(metrics.regularCount)", caption: "Guest history")
            RegularGuestMetricCard(title: "Notes found", value: "\(metrics.notesCount)", caption: "Reservation notes")
            RegularGuestMetricCard(title: "Upcoming", value: "\(metrics.upcomingCount)", caption: "Future visits")
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
        if cachedProfiles.isEmpty {
            ContentUnavailableView(
                "No guest profiles saved yet.",
                systemImage: "person.2",
                description: Text("Guest profiles load in the background after sign-in.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if displayedProfiles.isEmpty {
            ContentUnavailableView(
                "No guests found.",
                systemImage: "person.2",
                description: Text("Try a different filter or search.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(displayedProfiles) { profile in
                    NavigationLink {
                        GuestProfileDetailView(
                            guestKey: profile.guestKey,
                            environment: environment
                        )
                    } label: {
                        CachedGuestProfileRow(profile: profile)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sourceCopy: String {
        profileCountStatusCopy
    }

    private var sourceCountCopy: String? {
        if cachedProfiles.isEmpty {
            return "Guest profiles load in the background after sign-in."
        }
        if !fullListSyncCompleted {
            return "Guest profiles load in the background after sign-in."
        }
        return nil
    }

    private var visibleCount: Int {
        displayedProfiles.count
    }

    private var filterOptions: [RegularGuestFilter] {
        [.allSeenBefore, .regulars, .notesFound, .upcoming]
    }

    private var cacheMetrics: CachedGuestProfileMetrics {
        CachedGuestProfileMetrics(profiles: cachedProfiles)
    }

    private var sortOptions: [RegularGuestSort] {
        [.mostReservations, .recentlyBooked, .upcomingFirst, .name]
    }

    private var sortLabel: String {
        sortOptions.contains(sort) ? sort.displayName : "Guest history"
    }

    private func isSelectedFilter(_ option: RegularGuestFilter) -> Bool {
        if filterOptions.contains(filter) {
            return filter == option
        }
        return option == .allSeenBefore
    }

    private var displayedProfiles: [GuestProfileCacheRecord] {
        let query = GuestProfileCacheQuery(debouncedSearchText)
        let filtered = cachedProfiles.filter { profile in
            includes(profile, filter: filter)
                && matches(profile, query: query)
        }
        return sorted(filtered, by: sort)
    }

    private var profileCountStatusCopy: String {
        let count = cachedProfiles.count
        if count == 0 {
            return "No guest profiles saved yet."
        }

        if !fullListSyncCompleted {
            if backendProfileTotal >= 0 {
                return "\(count) of \(backendProfileTotal) guest profiles saved on this iPad. Still syncing…"
            }
            return "\(count) \(profileNoun(count)) saved on this iPad. Still syncing…"
        }

        return "\(count) \(profileNoun(count)) saved on this iPad."
    }

    private func includes(_ profile: GuestProfileCacheRecord, filter: RegularGuestFilter) -> Bool {
        switch filter {
        case .allSeenBefore:
            return true
        case .regulars:
            return profile.isLikelyRegular
        case .notesFound:
            return hasNoteSignal(profile)
        case .upcoming:
            return profile.upcomingCount > 0 || profile.nextReservationDate?.nilIfBlank != nil
        case .becomingRegular, .staffNotesFound, .callIn, .possibleMatches, .cancellationOrNoShow:
            return true
        }
    }

    private func matches(_ profile: GuestProfileCacheRecord, query: GuestProfileCacheQuery) -> Bool {
        guard query.isActive else { return true }
        if query.phoneDigits.count >= 4, profile.matchesPhoneDigits(query.phoneDigits) {
            return true
        }
        return searchableText(for: profile).contains(query.text)
    }

    private func sorted(
        _ profiles: [GuestProfileCacheRecord],
        by sort: RegularGuestSort
    ) -> [GuestProfileCacheRecord] {
        profiles.sorted { lhs, rhs in
            switch sort {
            case .mostReservations, .mostNotes:
                if lhs.cleanVisitCount != rhs.cleanVisitCount {
                    return lhs.cleanVisitCount > rhs.cleanVisitCount
                }
                if lhs.totalReservations != rhs.totalReservations {
                    return lhs.totalReservations > rhs.totalReservations
                }
                return dateSortKey(lhs) > dateSortKey(rhs)
            case .recentlyBooked:
                if dateSortKey(lhs) != dateSortKey(rhs) {
                    return dateSortKey(lhs) > dateSortKey(rhs)
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            case .firstSeen:
                let left = lhs.firstSeenDate ?? ""
                let right = rhs.firstSeenDate ?? ""
                if left != right {
                    return left < right
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            case .upcomingFirst:
                if lhs.hasUpcomingSignal != rhs.hasUpcomingSignal {
                    return lhs.hasUpcomingSignal
                }
                if (lhs.nextReservationDate ?? "") != (rhs.nextReservationDate ?? "") {
                    return (lhs.nextReservationDate ?? "9999-99-99") < (rhs.nextReservationDate ?? "9999-99-99")
                }
                return dateSortKey(lhs) > dateSortKey(rhs)
            case .name:
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    private func searchableText(for profile: GuestProfileCacheRecord) -> String {
        [
            profile.displayName,
            profile.email,
            profile.primaryPhone,
            profile.topLabelTitles,
            profile.summaryLine,
            profile.latestGuestNotePreview,
            profile.latestStaffNotePreview
        ]
        .compactMap { $0?.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased() }
        .joined(separator: " ")
    }

    private func hasNoteSignal(_ profile: GuestProfileCacheRecord) -> Bool {
        if profile.latestGuestNotePreview?.nilIfBlank != nil || profile.latestStaffNotePreview?.nilIfBlank != nil {
            return true
        }
        if profile.hasDietaryNote {
            return true
        }
        let text = [
            profile.topLabelTitles,
            profile.summaryLine
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        return text.contains("note")
            || text.contains("dietary")
            || text.contains("allerg")
            || text.contains("preference")
    }

    private func dateSortKey(_ profile: GuestProfileCacheRecord) -> String {
        profile.lastSeenDate ?? profile.lastBookedAt ?? profile.firstSeenDate ?? ""
    }

    private func profileNoun(_ count: Int) -> String {
        count == 1 ? "guest profile" : "guest profiles"
    }
}

private struct GuestProfileCacheQuery {
    let text: String
    let phoneDigits: String

    init(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        text = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        phoneDigits = GuestLookupPhoneNormalizer.digits(trimmed)
    }

    var isActive: Bool {
        !text.isEmpty || phoneDigits.count >= 4
    }
}

private struct CachedGuestProfileMetrics {
    let profileCount: Int
    let regularCount: Int
    let notesCount: Int
    let upcomingCount: Int

    init(profiles: [GuestProfileCacheRecord]) {
        profileCount = profiles.count
        regularCount = profiles.filter(\.isLikelyRegular).count
        notesCount = profiles.filter { profile in
            profile.latestGuestNotePreview?.nilIfBlank != nil
                || profile.latestStaffNotePreview?.nilIfBlank != nil
                || profile.hasDietaryNote
                || profile.topLabelTitles?.localizedCaseInsensitiveContains("note") == true
                || profile.summaryLine?.localizedCaseInsensitiveContains("note") == true
        }.count
        upcomingCount = profiles.filter(\.hasUpcomingSignal).count
    }
}

private extension GuestProfileCacheRecord {
    var hasUpcomingSignal: Bool {
        upcomingCount > 0 || nextReservationDate?.nilIfBlank != nil
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

private struct CachedGuestProfileRow: View {
    let profile: GuestProfileCacheRecord

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

                    if profile.isLikelyRegular {
                        Text("Regular")
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
                    if profile.latestGuestNotePreview?.nilIfBlank != nil {
                        GuestInsightBadge("Guest notes", systemImage: "text.bubble")
                    }
                    if profile.latestStaffNotePreview?.nilIfBlank != nil {
                        GuestInsightBadge("Staff notes", systemImage: "note.text")
                    }
                    if profile.hasDietaryNote {
                        GuestInsightBadge("Dietary note", systemImage: "fork.knife")
                    }
                    if let nextReservationLine {
                        GuestInsightBadge(nextReservationLine, systemImage: "calendar")
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

    private var displayName: String {
        profile.displayName.nilIfBlank ?? "Guest"
    }

    private var visitCount: Int {
        max(profile.cleanVisitCount, profile.totalReservations)
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

        if let phone = profile.primaryPhone?.nilIfBlank ?? profile.normalizedPhone?.nilIfBlank {
            parts.append(GuestLookupFormatting.phoneDisplay(phone))
        } else if let email = profile.email?.nilIfBlank {
            parts.append(email)
        }

        if profile.totalReservations > 0 {
            parts.append("\(profile.totalReservations) \(profile.totalReservations == 1 ? "reservation" : "reservations")")
        } else if profile.cleanVisitCount > 0 {
            parts.append("\(profile.cleanVisitCount) \(profile.cleanVisitCount == 1 ? "visit" : "visits")")
        }

        if let lastSeen = profile.lastSeenDate?.nilIfBlank ?? profile.lastBookedAt?.nilIfBlank {
            parts.append("Last seen \(GuestProfileCacheDateFormatter.display(lastSeen))")
        }

        if let summary = profile.summaryLine?.nilIfBlank {
            parts.append(summary)
        }

        return parts.isEmpty ? profile.displaySubtitle : parts.joined(separator: " · ")
    }

    private var nextReservationLine: String? {
        guard let date = profile.nextReservationDate?.nilIfBlank else {
            return profile.upcomingCount > 0 ? "Upcoming" : nil
        }
        let time = profile.nextReservationTime?.nilIfBlank
        let pieces = [GuestProfileCacheDateFormatter.display(date), time].compactMap { $0 }
        return "Next " + pieces.joined(separator: " · ")
    }

    private var labelTitles: [String] {
        guard let topLabelTitles = profile.topLabelTitles?.nilIfBlank else { return [] }
        return Array(
            topLabelTitles
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(4)
        )
    }
}

private enum GuestProfileCacheDateFormatter {
    static func display(_ value: String) -> String {
        guard let date = ReservationFormatters.reservationDateKey.date(from: value) else {
            return value
        }

        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

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
                        Text("Updating guest history")
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
        max(0, profile.cleanVisitCount ?? 0)
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

        if let lastSeen = GuestOperationalTruth.acceptedBackendLastVisit(
            profile.lastSeenDate,
            referenceDate: Date()
        ) {
            parts.append("Last visit \(ReservationFormatters.mediumDate.string(from: lastSeen))")
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
        if label.id == "regular_guest" {
            let classificationOnlyRegular = profile.cleanVisitCount == nil
                && ["exact", "strong"].contains(profile.identityConfidence?.lowercased() ?? "")
            guard (profile.cleanVisitCount ?? 0) >= 3 || classificationOnlyRegular else { return nil }
        }
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Guest Memory") {
    NavigationStack {
        RegularGuestsView(environment: AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer))
    }
    .modelContainer(ReservationPreviewData.previewContainer)
    .environmentObject(GuestIntelligenceStore(apiClient: ReservationsAPIClient.preview))
    .environmentObject(GuestProfileStore(apiClient: ReservationsAPIClient.preview))
}
#endif
