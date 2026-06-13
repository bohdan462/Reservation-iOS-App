//
//  ReservationHistoryView.swift
//  Tryzub Reservations
//
//  Full reservation activity history sheet.
//

import SwiftUI

struct ReservationHistoryView: View {
    let reservationID: Int
    let reservationLabel: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activityStore: ReservationActivityStore

    @State private var isLoadingMore = false

    private var loadState: ActivityLoadState {
        activityStore.loadState(for: reservationID)
    }

    private var items: [ReservationActivityItemViewState] {
        activityStore.allItems(for: reservationID)
    }

    private var pagination: (page: Int, totalPages: Int, total: Int)? {
        activityStore.reservationPagination(for: reservationID)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .idle, .loading where items.isEmpty:
                    ProgressView("Loading history…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .empty:
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("No history yet. New changes will appear here.")
                    )

                case .failed(let message):
                    ContentUnavailableView {
                        Label("Could Not Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") {
                            Task {
                                await activityStore.loadReservationActivity(
                                    reservationID: reservationID,
                                    force: true
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                case .loading, .loaded:
                    List {
                        ForEach(groupedItems, id: \.dayKey) { group in
                            Section(group.dayTitle) {
                                ForEach(group.items) { item in
                                    ReservationActivityRow(item: item, style: .full)
                                }
                            }
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
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Reservation History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable {
                await activityStore.loadReservationActivity(
                    reservationID: reservationID,
                    force: true
                )
            }
        }
        .task(id: reservationID) {
            await activityStore.loadReservationActivity(reservationID: reservationID)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: ReservationActivityInvalidation.notification)
        ) { notification in
            guard let id = notification.userInfo?[ReservationActivityInvalidation.UserInfoKey.reservationID] as? Int,
                  id == reservationID else { return }
            Task {
                await activityStore.loadReservationActivity(reservationID: reservationID, force: true)
            }
        }
    }

    private var canLoadMore: Bool {
        guard let pagination else { return false }
        return pagination.page < pagination.totalPages
    }

    private func loadMore() {
        guard let pagination, !isLoadingMore else { return }
        isLoadingMore = true
        Task {
            await activityStore.loadReservationActivity(
                reservationID: reservationID,
                page: pagination.page + 1
            )
            isLoadingMore = false
        }
    }

    private var groupedItems: [(dayKey: String, dayTitle: String, items: [ReservationActivityItemViewState])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: items) { item -> String in
            if let date = ReservationFormatters.serverDateTime.date(from: item.createdAt)
                ?? ReservationFormatters.serverDateMinute.date(from: item.createdAt) {
                if calendar.isDateInToday(date) { return "today" }
                if calendar.isDateInYesterday(date) { return "yesterday" }
                return date.formatted(date: .abbreviated, time: .omitted)
            }
            return "unknown"
        }

        let order = ["today", "yesterday"]
        return groups.map { key, value in
            let title: String = {
                switch key {
                case "today": return "Today"
                case "yesterday": return "Yesterday"
                default: return key
                }
            }()
            return (dayKey: key, dayTitle: title, items: value)
        }
        .sorted { lhs, rhs in
            let li = order.firstIndex(of: lhs.dayKey) ?? Int.max
            let ri = order.firstIndex(of: rhs.dayKey) ?? Int.max
            if li != ri { return li < ri }
            return lhs.dayKey > rhs.dayKey
        }
    }
}
