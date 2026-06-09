//
//  AnalyticsRangeOption.swift
//  Tryzub Reservations
//

import Foundation

enum AnalyticsRangeOption: String, CaseIterable, Identifiable {
    /// Backend `/business-intelligence/summary` and `/intelligence/system-status` cap ranges at 366 inclusive days.
    static let intelligenceMaxInclusiveDays = 366

    case all
    case thisMonth
    case last30Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .thisMonth:
            return "This Month"
        case .last30Days:
            return "Last 30 Days"
        }
    }

    func dateRange(now: Date = Date(), calendar: Calendar = .current) -> (from: String?, to: String?) {
        switch self {
        case .all:
            return (nil, nil)
        case .thisMonth:
            let components = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: components) ?? now
            return (start.reservationDateString(), now.reservationDateString())
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return (start.reservationDateString(), now.reservationDateString())
        }
    }

    /// Explicit bounds for intelligence endpoints, always within `intelligenceMaxInclusiveDays`.
    /// Legacy `/reservation-analytics/summary` may use `dateRange()` with nil bounds for `.all`.
    func resolvedIntelligenceDateRange(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (from: String, to: String) {
        let explicitRange = dateRange(now: now, calendar: calendar)
        if let fromKey = explicitRange.from,
           let toKey = explicitRange.to,
           let parsedFrom = Self.parseDateKey(fromKey, calendar: calendar),
           let parsedTo = Self.parseDateKey(toKey, calendar: calendar) {
            let clamped = Self.clampInclusiveDaySpan(
                from: parsedFrom,
                to: parsedTo,
                maxInclusiveDays: Self.intelligenceMaxInclusiveDays,
                calendar: calendar
            )
            return (clamped.from.reservationDateString(), clamped.to.reservationDateString())
        }

        let toDate = calendar.startOfDay(for: now)
        let fromDate = calendar.date(
            byAdding: .day,
            value: -(Self.intelligenceMaxInclusiveDays - 1),
            to: toDate
        ) ?? toDate
        return (fromDate.reservationDateString(), now.reservationDateString())
    }

    func managerRangeLabel(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch self {
        case .all:
            return "Rolling 12-month intelligence window"
        case .thisMonth, .last30Days:
            let keys = resolvedIntelligenceDateRange(now: now, calendar: calendar)
            return "\(keys.from) – \(keys.to)"
        }
    }

    // MARK: - Private

    private static func parseDateKey(_ key: String, calendar: Calendar) -> Date? {
        guard let date = ReservationFormatters.reservationDateKey.date(from: key) else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

    private static func clampInclusiveDaySpan(
        from: Date,
        to: Date,
        maxInclusiveDays: Int,
        calendar: Calendar
    ) -> (from: Date, to: Date) {
        let startOfFrom = calendar.startOfDay(for: from)
        let startOfTo = calendar.startOfDay(for: to)
        let normalizedTo = max(startOfFrom, startOfTo)
        let inclusiveDayCount = (calendar.dateComponents([.day], from: startOfFrom, to: normalizedTo).day ?? 0) + 1

        guard inclusiveDayCount > maxInclusiveDays else {
            return (startOfFrom, normalizedTo)
        }

        let clampedFrom = calendar.date(
            byAdding: .day,
            value: -(maxInclusiveDays - 1),
            to: normalizedTo
        ) ?? startOfFrom
        return (clampedFrom, normalizedTo)
    }
}
