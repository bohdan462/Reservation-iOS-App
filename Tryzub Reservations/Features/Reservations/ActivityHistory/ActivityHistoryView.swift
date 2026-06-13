//
//  ActivityHistoryView.swift
//  Tryzub Reservations
//
//  Global service-day activity from More tab.
//

import SwiftUI
import SwiftData

struct ActivityHistoryView: View {
    @EnvironmentObject private var activityStore: ReservationActivityStore
    @Query private var cachedReservations: [ReservationRecord]

    @State private var selectedDate = Date()
    @State private var isLoadingMore = false

    init() {
        let bounds = activeReservationWindowQueryBounds()
        let fromDate = bounds.from
        let toDate = bounds.to
        _cachedReservations = Query(
            filter: #Predicate<ReservationRecord> { record in
                !record.isHidden
                    && record.reservationDate >= fromDate
                    && record.reservationDate <= toDate
            }
        )
    }

    private var dateKey: String { selectedDate.reservationDateString() }

    private var loadState: ActivityLoadState {
        activityStore.feedState(for: selectedDate)
    }

    private var items: [ReservationActivityItemViewState] {
        activityStore.feedItems(for: selectedDate)
    }

    private var summaryChips: [ReservationActivitySummaryChip] {
        activityStore.feedSummaryChips(for: selectedDate)
    }

    private var pagination: (page: Int, totalPages: Int, total: Int)? {
        activityStore.feedPaginationByDateKey[dateKey]
    }

    private var guestNameByReservationID: [Int: String] {
        Dictionary(
            cachedReservations.map { ($0.remoteID, $0.guestName) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    private var dateLabel: String {
        Calendar.current.isDateInToday(selectedDate) ? "Today" : selectedDate.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        List {
            Section {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }

            if !summaryChips.isEmpty {
                Section("Summary") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(summaryChips) { chip in
                                Text("\(chip.label) \(chip.count)")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Latest changes") {
                feedContent
            }

            if canLoadMore {
                Section {
                    Button {
                        loadMore()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView()
                            } else {
                                Text("Load more")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isLoadingMore)
                }
            }
        }
        .navigationTitle("Activity History")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            if loadState == .loading && items.isEmpty {
                ProgressView()
                    .padding(.vertical, 8)
            }
        }
        .refreshable {
            await reload(force: true)
        }
        .task(id: dateKey) {
            await reload(force: false)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: ReservationActivityInvalidation.notification)
        ) { notification in
            guard let date = notification.userInfo?[ReservationActivityInvalidation.UserInfoKey.date] as? String,
                  date == dateKey else { return }
            Task { await reload(force: true) }
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        switch loadState {
        case .idle, .loading where items.isEmpty:
            HStack {
                Spacer()
                ProgressView("Loading changes…")
                Spacer()
            }
            .padding(.vertical, 12)

        case .empty:
            Text("No changes recorded for this date yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    Task { await reload(force: true) }
                }
                .font(.subheadline.weight(.semibold))
            }

        case .loading, .loaded:
            if items.isEmpty {
                Text("No changes recorded for this date yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.timeText) · \(item.title)")
                            .font(.subheadline)
                            .foregroundStyle(TryzubColors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(TryzubColors.mutedText)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var canLoadMore: Bool {
        guard let pagination else { return false }
        return pagination.page < pagination.totalPages
    }

    private func reload(force: Bool) async {
        await activityStore.loadActivityFeed(
            date: selectedDate,
            force: force,
            guestNameByReservationID: guestNameByReservationID
        )
    }

    private func loadMore() {
        guard let pagination, !isLoadingMore else { return }
        isLoadingMore = true
        Task {
            await activityStore.loadActivityFeed(
                date: selectedDate,
                page: pagination.page + 1,
                guestNameByReservationID: guestNameByReservationID
            )
            isLoadingMore = false
        }
    }
}
