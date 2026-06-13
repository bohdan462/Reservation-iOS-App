//
//  ServiceTimelineModels.swift
//  Tryzub Reservations
//
//  Data models for the Service Timeline / Tape Chart view.
//

import SwiftUI

// MARK: - Display Mode

/// Vertical grouping strategy for timeline lanes.
enum ServiceTimelineDisplayMode: String, CaseIterable, Identifiable {
    /// Mode A: one row per reservation, sorted chronologically. v1 default.
    case reservationLanes = "Lanes"
    // Mode B (time-grouped) and Mode C (table lanes) reserved for future.

    var id: String { rawValue }
    var label: String { rawValue }
}

// MARK: - Filter State

struct ServiceTimelineFilter: Equatable {
    var hideCompleted: Bool = true
    var hideCancelled: Bool = true
    var showOnlyNoTable: Bool = false

    func apply(to reservations: [ReservationRecord]) -> [ReservationRecord] {
        reservations.filter { r in
            if hideCompleted && r.statusValue == .completed { return false }
            if hideCancelled && (r.statusValue == .cancelled || r.statusValue == .noShow) { return false }
            if showOnlyNoTable && r.hasTableAssignment { return false }
            return true
        }
    }
}

// MARK: - Service Window

struct ServiceTimelineWindow: Equatable {
    let open: Date
    let close: Date

    var durationMinutes: Int {
        max(0, Int(close.timeIntervalSince(open) / 60))
    }

    var isValid: Bool {
        close > open && durationMinutes > 0
    }

    func minutesFromOpen(for date: Date) -> Double {
        date.timeIntervalSince(open) / 60.0
    }
}

// MARK: - Block Colors

extension ReservationStatus {
    var timelineBlockFill: Color {
        switch self {
        case .new:
            return Color(.systemGreen).opacity(0.14)
        case .confirmed:
            return Color(.systemGreen).opacity(0.16)
        case .needsReview:
            return Color(.systemOrange).opacity(0.18)
        case .seated:
            return Color.accentColor.opacity(0.18)
        case .completed:
            return Color(.systemGray4).opacity(0.28)
        case .cancelled, .noShow:
            return Color(.systemGray5).opacity(0.35)
        }
    }

    var timelineBlockBorder: Color {
        switch self {
        case .new:
            return Color(.systemGreen).opacity(0.30)
        case .confirmed:
            return Color(.systemGreen).opacity(0.32)
        case .needsReview:
            return Color(.systemOrange).opacity(0.42)
        case .seated:
            return Color.accentColor.opacity(0.40)
        case .completed:
            return Color(.systemGray3).opacity(0.38)
        case .cancelled, .noShow:
            return Color(.systemGray4).opacity(0.36)
        }
    }

    var timelineLabelColor: Color {
        switch self {
        case .seated:
            return Color.accentColor
        case .needsReview:
            return TryzubColors.warning
        case .completed, .cancelled, .noShow:
            return Color.secondary
        default:
            return Color.primary.opacity(0.80)
        }
    }
}

// MARK: - Layout Block

/// Precomputed layout descriptor for a single reservation in the timeline.
struct ServiceTimelineBlock: Identifiable {
    /// Reservation remoteID — stable and unique.
    let id: Int
    let guestName: String
    let displayTime: String
    let partySize: Int
    let status: ReservationStatus
    let assignedTableName: String?
    let hasGuestNotes: Bool
    let confirmedAt: String?
    /// Row index in Mode A.
    let laneIndex: Int
    /// X offset from the left edge of the timeline content (pts).
    let xOffset: CGFloat
    /// Block width in pts, derived from estimated dining duration.
    let width: CGFloat

    var hasTableAssignment: Bool {
        assignedTableName.map { !$0.isEmpty } ?? false
    }

    var voiceOverLabel: String {
        var parts = [guestName, displayTime, "\(partySize) guest\(partySize == 1 ? "" : "s")", status.displayName]
        if let table = assignedTableName { parts.append("Table \(table)") }
        return parts.joined(separator: ", ")
    }
}
