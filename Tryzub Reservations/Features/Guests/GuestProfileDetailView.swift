//
//  GuestProfileDetailView.swift
//  Tryzub Reservations
//

import SwiftData
import SwiftUI

// Shared guest-history destination for guestKey-based navigation.
// Slice 3D should render full booking and notes history from GuestProfileDTO here.
struct GuestProfileDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var guestProfileStore: GuestProfileStore

    let guestKey: String
    let environment: AppEnvironment

    @State private var profile: GuestProfileDTO?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let profile {
                headerSection(profile)
                metricsSection(profile)
                summarySection(profile)
                nextReservationSection(profile)
            } else if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading guest history")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(TryzubColors.mutedText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Loading guest history")
                }
            } else if hasLoaded {
                Section {
                    ContentUnavailableView(
                        "Guest History Unavailable",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text(errorMessage ?? "Try again.")
                    )

                    Button {
                        Task {
                            await loadProfile(force: true)
                        }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel("Retry loading guest history")
                }
            }
        }
        .navigationTitle("Guest history")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .task(id: guestKey) {
            await loadProfile(force: false)
        }
    }

    @ViewBuilder
    private func headerSection(_ profile: GuestProfileDTO) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(profile.primaryName?.nilIfBlank ?? "Guest")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(TryzubColors.primaryText)

                VStack(alignment: .leading, spacing: 6) {
                    if let phone = profile.primaryPhone?.nilIfBlank {
                        Label(GuestLookupFormatting.phoneDisplay(phone), systemImage: "phone")
                    }
                    if let email = profile.primaryEmail?.nilIfBlank {
                        Label(email, systemImage: "envelope")
                    }
                    if let firstSeen = profile.firstSeenDate?.nilIfBlank {
                        Label("First seen \(GuestProfileDetailDateFormatter.display(firstSeen))", systemImage: "calendar")
                    }
                    if let lastSeen = profile.lastSeenDate?.nilIfBlank ?? profile.lastBookedAt?.nilIfBlank {
                        Label("Last seen \(GuestProfileDetailDateFormatter.display(lastSeen))", systemImage: "clock")
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(TryzubColors.mutedText)

                if let labels = conciseLabels(profile), !labels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(labels, id: \.self) { label in
                                Text(label)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(TryzubColors.primaryText)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(TryzubColors.cardBackground, in: Capsule())
                                    .overlay {
                                        Capsule()
                                            .stroke(TryzubColors.border, lineWidth: 1)
                                    }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func metricsSection(_ profile: GuestProfileDTO) -> some View {
        Section("Guest summary") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                GuestProfileMetricTile(title: "Reservations", value: countText(profile.totalReservations ?? profile.totalBookingCount))
                GuestProfileMetricTile(title: "Completed", value: countText(profile.cleanVisitCount ?? profile.cleanPastVisitCount ?? profile.completedCount ?? profile.counts?.completed))
                GuestProfileMetricTile(title: "Cancelled", value: countText(profile.cancelledCount ?? profile.counts?.cancelled))
                GuestProfileMetricTile(title: "No-shows", value: countText(profile.noShowCount ?? profile.counts?.noShow))
                GuestProfileMetricTile(title: "Upcoming", value: countText(profile.upcomingCount))
                GuestProfileMetricTile(title: "Guest notes", value: countText(profile.guestNotesCount ?? profile.counts?.guestNotes))
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func summarySection(_ profile: GuestProfileDTO) -> some View {
        let summaryLines = profileSummaryLines(profile)
        if !summaryLines.isEmpty {
            Section("Pattern") {
                ForEach(summaryLines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(TryzubColors.primaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func nextReservationSection(_ profile: GuestProfileDTO) -> some View {
        if let next = profile.nextReservation {
            Section("Next reservation") {
                VStack(alignment: .leading, spacing: 7) {
                    if let date = next.date?.nilIfBlank ?? next.reservationDate?.nilIfBlank {
                        Label(GuestProfileDetailDateFormatter.display(date), systemImage: "calendar")
                    }
                    if let time = next.time?.nilIfBlank ?? next.reservationTime?.nilIfBlank {
                        Label(time, systemImage: "clock")
                    }
                    if let partySize = next.partySize, partySize > 0 {
                        Label("\(partySize) \(partySize == 1 ? "guest" : "guests")", systemImage: "person.2")
                    }
                    if let tableName = next.tableName?.nilIfBlank {
                        Label(tableName, systemImage: "table.furniture")
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(TryzubColors.primaryText)
            }
        }
    }

    private func loadProfile(force: Bool) async {
        _ = environment
        isLoading = true
        errorMessage = nil
        let loadedProfile = await guestProfileStore.loadProfile(
            guestKey: guestKey,
            force: force,
            context: modelContext
        )
        profile = loadedProfile
        hasLoaded = true
        isLoading = false
        if loadedProfile == nil {
            errorMessage = guestProfileStore.detailErrorMessage ?? "Guest history unavailable."
        }
    }

    private func conciseLabels(_ profile: GuestProfileDTO) -> [String]? {
        let allLabels = profile.labels?
            .compactMap { $0.title?.nilIfBlank } ?? []
        let labels = Array(allLabels.prefix(5))
        return labels.isEmpty ? nil : labels
    }

    private func profileSummaryLines(_ profile: GuestProfileDTO) -> [String] {
        var lines: [String] = []
        if let summary = profile.summary?.summaryText?.nilIfBlank {
            lines.append(summary)
        }
        if let classification = profile.summary?.classification?.nilIfBlank {
            lines.append(classification)
        }
        if let notes = profile.summary?.managementNotes {
            lines.append(contentsOf: notes.compactMap(\.nilIfBlank).prefix(3))
        }
        if let usualPartySize = profile.preferences?.usualPartySize ?? profile.usualPartySize, usualPartySize > 0 {
            lines.append("Usual party size: \(usualPartySize)")
        }
        if let averagePartySize = profile.preferences?.averagePartySize ?? profile.averagePartySize {
            lines.append("Average party size: \(averagePartySize.formatted(.number.precision(.fractionLength(1))))")
        }
        return lines
    }

    private func countText(_ value: Int?) -> String {
        "\(max(0, value ?? 0))"
    }
}

private struct GuestProfileMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(TryzubColors.primaryText)
                .lineLimit(1)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TryzubColors.mutedText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(TryzubColors.cardBackground, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                .stroke(TryzubColors.border, lineWidth: 1)
        }
    }
}

private enum GuestProfileDetailDateFormatter {
    static func display(_ value: String) -> String {
        guard let date = ReservationFormatters.reservationDateKey.date(from: value) else {
            return value
        }

        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
