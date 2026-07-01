//
//  BusinessIntelligenceInsightBuilder.swift
//  Tryzub Reservations
//
//  Deterministic manager-facing lines from backend business intelligence.
//

import Foundation

enum BusinessIntelligenceInsightBuilder {

    static func headline(
        summary: BusinessIntelligenceSummaryDTO,
        systemStatus: IntelligenceSystemStatusDTO?
    ) -> String? {
        let needsReview = summary.risk.needsReviewCount ?? systemStatus?.managerSummary.itemsNeedingReview ?? 0
        let peak = BusinessIntelligenceFormatting.peakWindowLabel(summary: summary)

        if needsReview > 0 {
            return "\(needsReview) bookings need management review."
        }
        if let peak {
            return "Main pressure builds around \(peak)."
        }
        if let totalGuests = summary.summary.totalGuests, totalGuests > 0 {
            return "\(totalGuests) guests in this range with steady demand."
        }
        return nil
    }

    static func supportingLines(
        summary: BusinessIntelligenceSummaryDTO,
        systemStatus: IntelligenceSystemStatusDTO?
    ) -> [String] {
        var lines: [String] = []
        let estimatedRelationships = usesEstimatedGuestRelationships(summary)

        if let peakLabel = BusinessIntelligenceFormatting.peakWindowLabel(summary: summary) {
            lines.append("Peak window: \(peakLabel).")
        }

        if let repeatRate = summary.guestRelationships.repeatGuestRate, repeatRate > 0 {
            let rateText = BusinessIntelligenceFormatting.percent(repeatRate)
            if estimatedRelationships {
                lines.append("Repeat guests look strong at about \(rateText).")
            } else {
                lines.append("Repeat guests are strong at \(rateText).")
            }
        }

        let needsReview = summary.risk.needsReviewCount ?? systemStatus?.managerSummary.itemsNeedingReview
        if let needsReview, needsReview > 0 {
            lines.append("Check booking pipeline before peak service.")
        }

        return Array(lines.prefix(2))
    }

    static func build(
        summary: BusinessIntelligenceSummaryDTO,
        systemStatus: IntelligenceSystemStatusDTO?
    ) -> [String] {
        if let headline = headline(summary: summary, systemStatus: systemStatus) {
            let supporting = supportingLines(summary: summary, systemStatus: systemStatus)
                .filter { !duplicatesHeadlineMeaning($0, headline: headline) }
            return [headline] + supporting.prefix(1)
        }
        return supportingLines(summary: summary, systemStatus: systemStatus)
    }

    static func chartCaption(summary: BusinessIntelligenceSummaryDTO) -> String? {
        let peak = BusinessIntelligenceFormatting.peakWindowLabel(summary: summary)
        let weekdayPeak = summary.breakdowns.byWeekday
            .map { row -> (label: String, guests: Int) in
                let guests = row.guestsCount ?? row.reservationsCount ?? 0
                let label = row.weekdayLabel ?? "Day"
                return (label, guests)
            }
            .max(by: { $0.guests < $1.guests })

        switch (peak, weekdayPeak?.guests ?? 0 > 0 ? weekdayPeak : nil) {
        case let (peak?, weekday?) where weekday.guests > 0:
            return "Main pressure: \(peak) · Peak: \(weekday.label)"
        case let (peak?, nil):
            return "Main pressure: \(peak)"
        case let (nil, weekday?) where weekday.guests > 0:
            return "Peak: \(weekday.label)"
        default:
            return nil
        }
    }

    static func dataQualityNote(for summary: BusinessIntelligenceSummaryDTO) -> String? {
        guard usesEstimatedGuestRelationships(summary) else { return nil }
        return "Some guest history is estimated."
    }

    static func managerSafeSystemWarnings(_ warnings: [String]) -> [String] {
        warnings.compactMap { warning in
            let lowered = warning.lowercased()
            if lowered.contains("import") {
                return "Some form imports may need staff review."
            }
            if lowered.contains("duplicate") {
                return "Some records may need staff review."
            }
            if lowered.contains("hidden") || lowered.contains("superseded") {
                return "Hidden bookings are left out of these totals."
            }
            return nil
        }
        .reduce(into: [String]()) { result, line in
            if !result.contains(line) {
                result.append(line)
            }
        }
    }

    // MARK: - Private

    private static func usesEstimatedGuestRelationships(
        _ summary: BusinessIntelligenceSummaryDTO
    ) -> Bool {
        if summary.dataQuality?.relationshipMetricsMode?
            .lowercased()
            .contains("approx") == true {
            return true
        }

        guard let warnings = summary.dataQuality?.warnings, !warnings.isEmpty else {
            return false
        }

        return warnings.contains { warning in
            let lowered = warning.lowercased()
            return lowered.contains("relationship")
                || lowered.contains("identity")
                || lowered.contains("approx")
                || lowered.contains("estimated")
                || lowered.contains("name_only")
        }
    }

    private static func duplicatesHeadlineMeaning(_ line: String, headline: String) -> Bool {
        let normalizedLine = line.lowercased()
        let normalizedHeadline = headline.lowercased()
        guard normalizedHeadline.contains("main pressure builds around"),
              normalizedLine.contains("peak window:") else {
            return false
        }
        let linePeak = normalizedLine
            .replacingOccurrences(of: "peak window:", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return !linePeak.isEmpty && normalizedHeadline.contains(linePeak)
    }
}
