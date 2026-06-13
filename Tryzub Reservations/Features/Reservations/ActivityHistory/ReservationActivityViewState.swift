//
//  ReservationActivityViewState.swift
//  Tryzub Reservations
//
//  Staff-safe presentation for reservation activity history.
//

import Foundation

enum ActivityLoadState: Equatable {
    case idle
    case loading
    case loaded([ReservationActivityItemViewState])
    case empty
    case failed(String)
}

struct ReservationActivityItemViewState: Identifiable, Equatable {
    let id: Int
    let title: String
    let subtitle: String?
    let timeText: String
    let iconName: String
    let eventType: String
    let reservationId: Int
    let createdAt: String
}

struct ReservationActivitySummaryChip: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int
}

struct ReservationActivityFeedViewState: Equatable {
    let dateKey: String
    let dateLabel: String
    let loadState: ActivityLoadState
    let summaryChips: [ReservationActivitySummaryChip]
    let total: Int
    let page: Int
    let totalPages: Int
}

enum ReservationActivityViewStateBuilder {
    static func items(
        from dtos: [ReservationActivityDTO],
        guestNameByReservationID: [Int: String] = [:],
        includeGuestContext: Bool = false,
        now: Date = Date()
    ) -> [ReservationActivityItemViewState] {
        dtos.map { dto in
            item(
                from: dto,
                guestName: includeGuestContext ? guestNameByReservationID[dto.reservationId] : nil,
                now: now
            )
        }
    }

    static func item(
        from dto: ReservationActivityDTO,
        guestName: String? = nil,
        now: Date = Date()
    ) -> ReservationActivityItemViewState {
        let actor = formattedActor(name: dto.actorName, role: dto.actorRole)
        let subtitle: String? = {
            if let guestName, !guestName.isEmpty {
                return "\(actor) · \(guestName)"
            }
            return actor
        }()

        return ReservationActivityItemViewState(
            id: dto.id,
            title: dto.summary,
            subtitle: subtitle,
            timeText: formattedTime(dto.createdAt, now: now),
            iconName: iconName(for: dto.eventType),
            eventType: dto.eventType,
            reservationId: dto.reservationId,
            createdAt: dto.createdAt
        )
    }

    static func summaryChips(from summary: ReservationActivityFeedSummaryDTO?) -> [ReservationActivitySummaryChip] {
        guard let summary else { return [] }
        return summary.chipCounts.map { pair in
            ReservationActivitySummaryChip(
                id: pair.eventType,
                label: chipLabel(for: pair.eventType),
                count: pair.count
            )
        }
    }

    static func staffSafeErrorMessage(from error: Error) -> String {
        if let apiError = error as? ReservationAPIError {
            switch apiError {
            case .unauthorized:
                return "You do not have access to activity history."
            case .missingCredentials:
                return "You do not have access to activity history."
            case .serverError(let statusCode, _):
                if statusCode == 401 || statusCode == 403 {
                    return "You do not have access to activity history."
                }
                if statusCode >= 500 {
                    return "History could not load right now."
                }
                return "Could not load history. Try again."
            case .networkFailure:
                return "Could not load history. Try again."
            default:
                return "Could not load history. Try again."
            }
        }
        return "Could not load history. Try again."
    }

    // MARK: - Private

    private static func formattedActor(name: String?, role: String?) -> String {
        if let name, !name.isEmpty { return name }
        if let role, !role.isEmpty {
            switch role.lowercased() {
            case "manager": return "Manager"
            case "host", "staff": return "Staff"
            case "guest": return "Guest"
            case "system": return "System"
            default: return role.capitalized
            }
        }
        return "Staff"
    }

    private static func formattedTime(_ raw: String, now: Date) -> String {
        let parsed = parseServerDate(raw)
        guard let parsed else { return raw }

        let calendar = Calendar.current
        if calendar.isDateInToday(parsed) {
            return ReservationFormatters.shortTime.string(from: parsed)
        }
        if calendar.isDateInYesterday(parsed) {
            return "Yesterday"
        }
        if calendar.dateComponents([.day], from: parsed, to: now).day ?? 0 < 7 {
            let weekday = parsed.formatted(.dateTime.weekday(.abbreviated))
            return "\(weekday) · \(ReservationFormatters.shortTime.string(from: parsed))"
        }
        return parsed.formatted(date: .abbreviated, time: .shortened)
    }

    private static func parseServerDate(_ raw: String) -> Date? {
        ReservationFormatters.serverDateTime.date(from: raw)
            ?? ReservationFormatters.serverDateMinute.date(from: raw)
    }

    static func iconName(for eventType: String) -> String {
        switch eventType {
        case "created": return "plus.circle"
        case "imported": return "tray.and.arrow.down"
        case "updated": return "pencil"
        case "status_changed": return "arrow.triangle.2.circlepath"
        case "confirmed": return "checkmark.circle"
        case "seated": return "person.2"
        case "completed": return "checkmark.seal"
        case "cancelled": return "xmark.circle"
        case "no_show": return "exclamationmark.triangle"
        case "table_assigned": return "tablecells"
        case "table_cleared": return "tablecells.badge.ellipsis"
        case "guest_note_updated": return "note.text"
        case "staff_note_updated": return "square.and.pencil"
        case "email_draft_created": return "envelope.badge"
        case "manual_email_sent": return "envelope"
        case "guest_cancelled": return "person.crop.circle.badge.xmark"
        case "guest_change_requested": return "arrow.left.arrow.right"
        case "hidden": return "eye.slash"
        case "restored": return "eye"
        case "hard_deleted": return "trash"
        case "auto_completed": return "clock.badge.checkmark"
        default: return "clock.arrow.circlepath"
        }
    }

    private static func chipLabel(for eventType: String) -> String {
        switch eventType {
        case "created": return "Created"
        case "cancelled", "guest_cancelled": return "Cancelled"
        case "table_assigned", "table_cleared": return "Tables"
        case "guest_note_updated", "staff_note_updated": return "Notes"
        case "confirmed": return "Confirmed"
        case "status_changed": return "Status"
        case "manual_email_sent", "email_draft_created": return "Email"
        default:
            return eventType
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}
