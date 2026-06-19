//
//  HostBoardLists.swift
//  Tryzub Reservations
//

import SwiftUI

struct CompactEmptyHostState: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .hostBoardGlassCapsule()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HostBoardReservationsLoadingState: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading reservations…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .hostBoardGlassCapsule()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum HostBoardListTrace {
    #if DEBUG
    static func logDuplicateRemoteIDs(_ reservations: [ReservationRecord], context: String) {
        let ids = reservations.map(\.remoteID)
        guard ids.count != Set(ids).count else { return }
        let duplicates = Dictionary(grouping: ids, by: { $0 })
            .filter { $1.count > 1 }
            .map(\.key)
            .sorted()
        print(
            "[HOST_ROWS_TRACE] event=duplicate_remote_ids context=\(context) duplicates=\(duplicates.map(String.init).joined(separator: ","))"
        )
    }
    #else
    static func logDuplicateRemoteIDs(_ reservations: [ReservationRecord], context: String) {}
    #endif
}

struct HostBoardColumn: View {
    let title: String
    let subtitle: String
    let reservations: [ReservationRecord]
    let emptyTitle: String
    let emptySystemImage: String
    var scrollsInternally = true
    var referenceNow = Date()
    var showsReservationLoadingPlaceholder = false
    let environment: AppEnvironment
    let onAction: (ReservationHostAction, ReservationRecord) -> Void
    let onOpenReservation: (ReservationRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if scrollsInternally {
                ScrollView {
                    columnContent
                        .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                columnContent
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: scrollsInternally ? CGFloat.infinity : nil,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private var columnContent: some View {
        if reservations.isEmpty {
            CompactEmptyHostState(title: emptyTitle, systemImage: emptySystemImage)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(reservations, id: \.remoteID) { reservation in
                    HostBoardReservationRow(
                        reservation: reservation,
                        referenceNow: referenceNow,
                        environment: environment,
                        onAction: onAction,
                        onOpenReservation: onOpenReservation
                    )
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .onAppear {
                HostBoardListTrace.logDuplicateRemoteIDs(reservations, context: "HostBoardColumn")
            }
        }
    }
}

struct HomeReservationsPanel: View {
    let snapshot: HostBoardSnapshot
    var referenceNow = Date()
    var scrollsInternally = true
    var showsReservationLoadingPlaceholder = false
    let environment: AppEnvironment
    let onAction: (ReservationHostAction, ReservationRecord) -> Void
    let onOpenReservation: (ReservationRecord) -> Void

    private var hourSections: [ReservationHourSection] {
        ReservationRecord.hourSections(from: snapshot.upcoming, now: snapshot.now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reservations")
                        .font(.headline.weight(.medium))
                }

                Spacer()
            }

            if scrollsInternally {
                ScrollView {
                    reservationsContent
                        .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                reservationsContent
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: scrollsInternally ? CGFloat.infinity : nil,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private var reservationsContent: some View {
        if showsReservationLoadingPlaceholder, hourSections.isEmpty {
            HostBoardReservationsLoadingState()
        } else if hourSections.isEmpty {
            CompactEmptyHostState(
                title: "No active reservations",
                systemImage: "calendar.badge.checkmark"
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(hourSections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary.opacity(0.82))
                            Text(section.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        LazyVStack(spacing: 8) {
                            ForEach(section.reservations, id: \.remoteID) { reservation in
                                HostBoardReservationRow(
                                    reservation: reservation,
                                    referenceNow: referenceNow,
                                    environment: environment,
                                    onAction: onAction,
                                    onOpenReservation: onOpenReservation
                                )
                            }
                        }
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                    }
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .onAppear {
                let rows = hourSections.flatMap(\.reservations)
                HostBoardListTrace.logDuplicateRemoteIDs(rows, context: "HomeReservationsPanel")
            }
        }
    }
}
