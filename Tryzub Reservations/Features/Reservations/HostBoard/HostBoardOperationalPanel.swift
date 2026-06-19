//
//  HostBoardOperationalPanel.swift
//  Tryzub Reservations
//

import SwiftUI

// MARK: - Summary Card

struct HostBoardSummaryCard: View {
    let reservationCount: Int
    let guestCount: Int
    let newCount: Int
    let reviewCount: Int
    let failedImportCount: Int
    let noTableCount: Int
    let arrivalPressure: ArrivalPressureSummary
    var isSelectedDateToday = true
    var referenceNow: Date = Date()
    var availabilitySummary: String?
    var isAvailabilityLoading = false
    var onRefreshAvailability: (() -> Void)?
    var onOpenReservationByID: ((Int) -> Void)?

    private var stats: [HostBoardStat] {
        var items = [
            HostBoardStat(value: reservationCount, label: "Booked"),
            HostBoardStat(value: guestCount, label: "Guests"),
            HostBoardStat(value: newCount, label: "New"),
            HostBoardStat(value: reviewCount, label: "Review"),
            HostBoardStat(value: noTableCount, label: "No table")
        ]
        if failedImportCount > 0 {
            items.append(HostBoardStat(value: failedImportCount, label: "Forms"))
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    ForEach(stats) { stat in
                        statItem(stat)
                    }
                    Spacer(minLength: 0)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(stats) { statItem($0) }
                }
            }

            if let availabilitySummary {
                HStack(spacing: 8) {
                    Text(availabilitySummary)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(TryzubColors.mutedText)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let onRefreshAvailability {
                        Button(action: onRefreshAvailability) {
                            if isAvailabilityLoading {
                                TryzubSubtleLoadingDot(diameter: 6)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(TryzubColors.mutedText)
                        .disabled(isAvailabilityLoading)
                    }
                }
            } else if isAvailabilityLoading {
                HStack(spacing: 8) {
                    Text("Checking available times…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(TryzubColors.mutedText)
                    Spacer(minLength: 0)
                    TryzubSubtleLoadingDot(diameter: 6)
                }
            }
        }
        .padding(10)
        .hostBoardGlassPanel(cornerRadius: ReservationUIStyle.cardCorner)
    }

    private func statItem(_ stat: HostBoardStat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(stat.value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(stat.value == 0 ? TryzubColors.mutedText : TryzubColors.primaryText)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: stat.value)
                .lineLimit(1)
            Text(stat.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(TryzubColors.mutedText)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .hostBoardGlassCapsule()
        .fixedSize(horizontal: true, vertical: false)
    }

    private func timelineLegend(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(TryzubColors.mutedText)
            Text(value)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TryzubColors.primaryText)
                .lineLimit(1)
        }
    }
}

struct HostOperationalStatusPanel: View {
    let reservationCount: Int
    let guestCount: Int
    let newCount: Int
    let reviewCount: Int
    let failedImportCount: Int
    let noTableCount: Int
    let availabilitySummary: String?
    let isAvailabilityLoading: Bool
    let reminderContext: HostReminderPanelContext?
    let isWideLayout: Bool
    let onRefreshAvailability: (() -> Void)?
    let onSendReminders: () -> Void

    private var stats: [HostBoardStat] {
        var items = [
            HostBoardStat(value: reservationCount, label: "Booked"),
            HostBoardStat(value: guestCount, label: "Guests"),
            HostBoardStat(value: newCount, label: "New"),
            HostBoardStat(value: reviewCount, label: "Review"),
            HostBoardStat(value: noTableCount, label: "No table")
        ]
        if failedImportCount > 0 {
            items.append(HostBoardStat(value: failedImportCount, label: "Forms"))
        }
        return items
    }

    var body: some View {
        Group {
            if isWideLayout {
                HStack(alignment: .top, spacing: 16) {
                    statsSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    reminderSection
                        .frame(width: 300, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    statsSection
                    reminderSection
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .hostBoardGlassPanel(cornerRadius: ReservationUIStyle.cardCorner, strokeOpacity: 0.14)
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Label("Service", systemImage: "person.3.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TryzubColors.primaryText)
                    .fixedSize()

                availabilityStatus
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    ForEach(stats) { statItem($0) }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 82), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(stats) { statItem($0) }
                }
            }
        }
    }

    @ViewBuilder
    private var availabilityStatus: some View {
        if let availabilitySummary {
            HStack(spacing: 6) {
                Text(availabilitySummary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let onRefreshAvailability {
                    Button(action: onRefreshAvailability) {
                        if isAvailabilityLoading {
                            TryzubSubtleLoadingDot(diameter: 6)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TryzubColors.mutedText)
                    .disabled(isAvailabilityLoading)
                }
            }
        } else if isAvailabilityLoading {
            HStack(spacing: 6) {
                Text("Checking times")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
                TryzubSubtleLoadingDot(diameter: 6)
            }
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Label("Reminders", systemImage: "bell.badge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TryzubColors.primaryText)

                if reminderContext?.isSending == true {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer(minLength: 0)

                if reminderContext?.canSendBatchReminders == true {
                    Button(action: onSendReminders) {
                        Label("Send", systemImage: "paperplane")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(reminderContext?.isSending == true)
                }
            }

            Text(reminderContext?.shortStateLine ?? "Reminders off")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(reminderContext?.stateTint ?? TryzubColors.mutedText)
                .lineLimit(1)

            if let secondary = reminderContext?.compactSecondaryLine {
                Text(secondary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notice = reminderContext?.notice, !notice.isEmpty {
                Text(notice)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statItem(_ stat: HostBoardStat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(stat.value)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(stat.value == 0 ? TryzubColors.mutedText : TryzubColors.primaryText)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: stat.value)
                .lineLimit(1)
            Text(stat.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(TryzubColors.mutedText)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .hostBoardGlassCapsule()
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct HostBoardStat: Identifiable {
    let value: Int
    let label: String
    var id: String { label }
}

// MARK: - Availability Indicator

struct HomeAvailabilityIndicator: View {
    let availability: RestaurantDayAvailabilityDTO?
    let slots: ReservationSlotsResponseDTO?
    let blockedCount: Int
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isClosed ? "calendar.badge.exclamationmark" : "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isClosed ? .red : .secondary)
                .frame(width: 28, height: 28)
                .hostBoardGlassSurface(cornerRadius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(isClosed ? "Reservations closed today" : "Today availability")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isClosed ? .red : .primary)

                Text(summaryText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: onRefresh) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isLoading)
        }
        .padding(10)
        .hostBoardGlassSurface(cornerRadius: 10)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isClosed ? Color.red.opacity(0.07) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isClosed ? Color.red.opacity(0.18) : Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var isClosed: Bool {
        if let availability {
            return !availability.isOpen
        }
        if let slots {
            return !slots.isOpen
        }
        return false
    }

    private var summaryText: String {
        if let errorMessage {
            return errorMessage
        }

        if isLoading && availability == nil && slots == nil {
            return "Checking available times…"
        }

        if isClosed {
            return sourceText
        }

        var parts: [String] = []
        if let availability,
           let openTime = shortTime(availability.openTime),
           let closeTime = shortTime(availability.closeTime) {
            parts.append("\(openTime)-\(closeTime)")
        }
        parts.append("\(slots?.slots.count ?? 0) public slots")
        if sourceText == "Special override" {
            parts.append(sourceText)
        }
        if blockedCount > 0 {
            parts.append("Blocked slots: \(blockedCount)")
        }
        return parts.joined(separator: " | ")
    }

    private var sourceText: String {
        switch availability?.source.lowercased() ?? slots?.source?.lowercased() {
        case "special":
            return "Special override"
        case "weekly":
            return "Weekly"
        case .some(let source):
            return source.capitalized
        case nil:
            return "Server availability"
        }
    }

    private func shortTime(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return String(value.prefix(5))
    }
}
