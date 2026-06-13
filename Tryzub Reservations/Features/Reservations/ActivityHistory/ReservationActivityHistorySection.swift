//
//  ReservationActivityHistorySection.swift
//  Tryzub Reservations
//
//  Compact History section for Reservation Detail.
//

import SwiftUI

struct ReservationActivityHistorySection: View {
    let reservationID: Int
    let reservationLabel: String?

    @EnvironmentObject private var activityStore: ReservationActivityStore
    @State private var showFullHistory = false

    private var loadState: ActivityLoadState {
        activityStore.loadState(for: reservationID)
    }

    private var previewItems: [ReservationActivityItemViewState] {
        activityStore.previewItems(for: reservationID, limit: 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("History", systemImage: "clock.arrow.circlepath")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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
        .sheet(isPresented: $showFullHistory) {
            ReservationHistoryView(
                reservationID: reservationID,
                reservationLabel: reservationLabel
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading history…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)

        case .empty:
            Text("No history yet. New changes will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    Task {
                        await activityStore.loadReservationActivity(
                            reservationID: reservationID,
                            force: true
                        )
                    }
                }
                .font(.subheadline.weight(.semibold))
            }

        case .loaded:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(previewItems) { item in
                    ReservationActivityRow(item: item, style: .compact)
                }

                if activityStore.allItems(for: reservationID).count > 5
                    || (activityStore.reservationPagination(for: reservationID)?.total ?? 0) > 5 {
                    Button("Show all") {
                        showFullHistory = true
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}

struct ReservationActivityRow: View {
    enum Style {
        case compact
        case full
    }

    let item: ReservationActivityItemViewState
    var style: Style = .full

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.iconName)
                .font(style == .compact ? .caption : .body)
                .foregroundStyle(TryzubColors.mutedText)
                .frame(width: 18, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                if style == .compact {
                    Text("\(item.timeText) · \(item.title)")
                        .font(.subheadline)
                        .foregroundStyle(TryzubColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(item.title)
                        .font(.subheadline)
                        .foregroundStyle(TryzubColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(style == .compact ? subtitle : "\(subtitle) · \(item.timeText)")
                        .font(.caption)
                        .foregroundStyle(TryzubColors.mutedText)
                } else if style == .full {
                    Text(item.timeText)
                        .font(.caption)
                        .foregroundStyle(TryzubColors.mutedText)
                }
            }

            Spacer(minLength: 0)
        }
    }
}
