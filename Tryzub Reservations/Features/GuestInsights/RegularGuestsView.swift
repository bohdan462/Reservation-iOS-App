//
//  RegularGuestsView.swift
//  Tryzub Reservations
//

import SwiftData
import SwiftUI

// MARK: - Regulars / Guest Memory View

struct RegularGuestsView: View {
    // Reads cached reservations only; Guest Memory does not call network or mutate data.
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

            Text("Based on cached reservations on this device.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary Cards

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 10)], spacing: 10) {
            RegularGuestMetricCard(title: "Regulars", value: "\(store.metrics.regularCount)", caption: "5+ visits")
            RegularGuestMetricCard(title: "Becoming", value: "\(store.metrics.becomingCount)", caption: "3-4 visits")
            RegularGuestMetricCard(title: "Notes found", value: "\(store.metrics.notesCount)", caption: "Staff or guest notes")
            RegularGuestMetricCard(title: "Possible matches", value: "\(store.metrics.possibleCount)", caption: "Review only")
        }
    }

    // MARK: - Search / Filter / Sort Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RegularGuestFilter.allCases) { option in
                        Button {
                            filter = option
                        } label: {
                            Text(option.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(filter == option ? Color(.systemBackground) : Color(.secondaryLabel))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(filter == option ? ReservationUIStyle.selectedControlColor : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                                        .stroke(Color.primary.opacity(filter == option ? 0.12 : 0.08), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }

            HStack {
                Text("\(store.displayedSummaries.count) \(store.displayedSummaries.count == 1 ? "guest" : "guests")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(RegularGuestSort.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    Label(sort.displayName, systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.medium))
                }
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if store.isComputing && store.displayedSummaries.isEmpty {
            HStack {
                Spacer()
                ProgressView("Loading guest memory...")
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
                        } label: {
                            RegularGuestRow(summary: summary)
                        }
                        .buttonStyle(.plain)
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
                        GuestInsightBadge("Staff notes", systemImage: "note.text")
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
}
#endif
