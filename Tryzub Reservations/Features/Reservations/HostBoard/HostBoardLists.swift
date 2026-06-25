//
//  HostBoardLists.swift
//  Tryzub Reservations
//

import SwiftUI

private extension Color {
    static let hostBoardSeatedBlue = Color(red: 0.08, green: 0.36, blue: 0.70)
}

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
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(.horizontal, 14)
        .hostBoardGlassPanel(cornerRadius: 12, strokeOpacity: 0.08)
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
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(.horizontal, 14)
        .hostBoardGlassPanel(cornerRadius: 12, strokeOpacity: 0.08)
    }
}

private struct HostBoardListHeader: View {
    let title: String
    let subtitle: String
    let count: Int
    let systemImage: String
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 8)

            Text("\(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .frame(minWidth: 28, minHeight: 28)
                .padding(.horizontal, 3)
                .hostBoardGlassCapsule(strokeOpacity: 0.10)
                .contentTransition(.numericText())
                .accessibilityLabel("\(count) \(title.lowercased())")
        }
        .frame(minHeight: 40)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: count)
    }
}

private struct HostBoardListGroupHeader: View {
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(tint.opacity(0.75))
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.84))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
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
    var showsServiceGroupHeader = false
    let environment: AppEnvironment
    let onAction: (ReservationHostAction, ReservationRecord) -> Void
    let onOpenReservation: (ReservationRecord) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var guestCount: Int {
        reservations.reduce(0) { $0 + $1.partySize }
    }

    private var reservationIDs: [Int] {
        reservations.map(\.remoteID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HostBoardListHeader(
                title: title,
                subtitle: subtitle,
                count: reservations.count,
                systemImage: "person.2.fill",
                tint: .hostBoardSeatedBlue
            )

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
        VStack(alignment: .leading, spacing: 8) {
            if showsServiceGroupHeader {
                HostBoardListGroupHeader(
                    title: reservations.isEmpty ? "Dining room" : "Dining now",
                    subtitle: reservations.isEmpty
                        ? "Ready for first seating"
                        : "\(reservations.count) \(reservations.count == 1 ? "party" : "parties") · \(guestCount) \(guestCount == 1 ? "guest" : "guests")",
                    tint: .hostBoardSeatedBlue
                )
            }

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
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    }
                }
                .onAppear {
                    HostBoardListTrace.logDuplicateRemoteIDs(reservations, context: "HostBoardColumn")
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.30), value: reservationIDs)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hourSections: [ReservationHourSection] {
        ReservationRecord.hourSections(from: snapshot.upcoming, now: snapshot.now)
    }

    private var upcomingGuestCount: Int {
        snapshot.upcoming.reduce(0) { $0 + $1.partySize }
    }

    private var reservationIDs: [Int] {
        snapshot.upcoming.map(\.remoteID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HostBoardListHeader(
                title: "Reservations",
                subtitle: "\(upcomingGuestCount) \(upcomingGuestCount == 1 ? "guest" : "guests") expected",
                count: snapshot.upcoming.count,
                systemImage: "calendar.badge.clock",
                tint: .orange
            )

            if scrollsInternally {
                ScrollView {
                    reservationsContent
                        .padding(.bottom, 12)
                        .animation(reduceMotion ? nil : .snappy(duration: 0.30), value: reservationIDs)
                }
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                reservationsContent
                    .animation(reduceMotion ? nil : .snappy(duration: 0.30), value: reservationIDs)
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
            VStack(alignment: .leading, spacing: 8) {
                HostBoardListGroupHeader(
                    title: "Arrival queue",
                    subtitle: "Updating reservations",
                    tint: .orange
                )
                HostBoardReservationsLoadingState()
            }
        } else if hourSections.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HostBoardListGroupHeader(
                    title: "Arrival queue",
                    subtitle: "Ready for the next booking",
                    tint: .orange
                )
                CompactEmptyHostState(
                    title: "No active reservations",
                    systemImage: "calendar.badge.checkmark"
                )
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(hourSections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        HostBoardListGroupHeader(
                            title: section.title,
                            subtitle: section.subtitle,
                            tint: .orange
                        )

                        LazyVStack(spacing: 8) {
                            ForEach(section.reservations, id: \.remoteID) { reservation in
                                HostBoardReservationRow(
                                    reservation: reservation,
                                    referenceNow: referenceNow,
                                    environment: environment,
                                    onAction: onAction,
                                    onOpenReservation: onOpenReservation
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                            }
                        }
                    }
                }
            }
            .onAppear {
                let rows = hourSections.flatMap(\.reservations)
                HostBoardListTrace.logDuplicateRemoteIDs(rows, context: "HomeReservationsPanel")
            }
        }
    }
}
