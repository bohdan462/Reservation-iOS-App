//
//  BusinessIntelligenceFormatting.swift
//  Tryzub Reservations
//

import Foundation

enum BusinessIntelligenceFormatting {
    static let missingValue = "—"

    static func integer(_ value: Int?) -> String {
        guard let value else { return missingValue }
        return "\(value)"
    }

    static func percent(_ rate: Double?) -> String {
        guard let rate else { return missingValue }
        let normalized = rate > 1 ? rate / 100 : rate
        return String(format: "%.0f%%", normalized * 100)
    }

    static func decimal(_ value: Double?, fractionDigits: Int = 1) -> String {
        guard let value else { return missingValue }
        return String(format: "%.\(fractionDigits)f", value)
    }

    static func displayHour(_ value: String?) -> String {
        guard let value else { return missingValue }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return missingValue }

        if trimmed.contains(":") {
            return formatClock(trimmed)
        }

        if let hour = Int(trimmed) {
            return formatOperationalTime(hour: hour, minute: 0)
        }

        return trimmed
    }

    static func peakWindowLabel(
        summary: BusinessIntelligenceSummaryDTO
    ) -> String? {
        if let peak = summary.peakWindows.first {
            var parts: [String] = []
            if let weekday = peak.weekdayLabel, !weekday.isEmpty {
                parts.append(weekday)
            }
            if let time = peak.time, !time.isEmpty {
                parts.append(displayHour(time))
            }
            if !parts.isEmpty {
                return parts.joined(separator: " · ")
            }
        }

        let demand = summary.demand
        var parts: [String] = []
        if let weekday = demand.busiestWeekdayLabel, !weekday.isEmpty {
            parts.append(weekday)
        } else if let busiestDate = demand.busiestDate, !busiestDate.isEmpty {
            parts.append(busiestDate)
        }
        if let peakWindow = demand.peak15MinWindow, !peakWindow.isEmpty {
            parts.append(displayHour(peakWindow))
        } else if let hour = demand.busiestHour, !hour.isEmpty {
            parts.append(displayHour(hour))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func overallStatusTitle(_ status: IntelligenceSystemOverallStatusDTO) -> String {
        switch status {
        case .ok:
            return "OK"
        case .warning:
            return "Warning"
        case .needsAttention:
            return "Needs attention"
        }
    }

    private static func formatClock(_ value: String) -> String {
        formatOperationalTime(value)
    }

    /// Compact 24-hour restaurant time (HH:mm).
    private static func formatOperationalTime(_ value: String) -> String {
        let parts = value.split(separator: ":")
        guard let hourComponent = parts.first, let hour = Int(hourComponent) else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let minutePart = parts.count > 1 ? String(parts[1].prefix(2)) : "00"
        let minute = Int(minutePart) ?? 0
        return formatOperationalTime(hour: hour, minute: minute)
    }

    private static func formatOperationalTime(hour: Int, minute: Int) -> String {
        let normalizedHour = (hour % 24 + 24) % 24
        let normalizedMinute = max(0, min(minute, 59))
        return String(format: "%02d:%02d", normalizedHour, normalizedMinute)
    }
}
