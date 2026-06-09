//
//  BusinessIntelligenceInsightBuilder.swift
//  Tryzub Reservations
//
//  Deterministic manager-facing lines from backend business intelligence.
//

import Foundation

enum BusinessIntelligenceInsightBuilder {

    static func build(
        summary: BusinessIntelligenceSummaryDTO,
        systemStatus: IntelligenceSystemStatusDTO?
    ) -> [String] {
        var lines: [String] = []
        let estimatedRelationships = usesEstimatedGuestRelationships(summary)

        if let peakLabel = BusinessIntelligenceFormatting.peakWindowLabel(summary: summary) {
            lines.append("\(peakLabel) is the strongest demand window.")
        }

        if let repeatRate = summary.guestRelationships.repeatGuestRate, repeatRate > 0 {
            let rateText = BusinessIntelligenceFormatting.percent(repeatRate)
            if estimatedRelationships {
                lines.append("\(rateText) estimated repeat guests in this range.")
            } else {
                lines.append("\(rateText) repeat guests in this range.")
            }
        }

        let needsReview = summary.risk.needsReviewCount ?? systemStatus?.managerSummary.itemsNeedingReview
        let noTable = summary.risk.noTableCount
        if let needsReview, needsReview > 0 {
            if let noTable, noTable > 0 {
                lines.append("\(needsReview) need attention, including \(noTable) without a table.")
            } else {
                lines.append("\(needsReview) need attention.")
            }
        } else if let noTable, noTable > 0 {
            lines.append("\(noTable) upcoming reservations still need tables.")
        }

        if lines.isEmpty,
           let totalGuests = summary.summary.totalGuests,
           totalGuests > 0 {
            lines.append("\(totalGuests) guests in this range.")
        }

        return Array(lines.prefix(2))
    }

    static func dataQualityNote(for summary: BusinessIntelligenceSummaryDTO) -> String? {
        guard usesEstimatedGuestRelationships(summary) else { return nil }
        return "Guest relationship metrics are estimated from email/phone matches."
    }

    static func managerSafeSystemWarnings(_ warnings: [String]) -> [String] {
        warnings.compactMap { warning in
            let lowered = warning.lowercased()
            if lowered.contains("import") {
                return "Import pipeline may need attention."
            }
            if lowered.contains("duplicate") {
                return "Possible duplicates detected."
            }
            if lowered.contains("hidden") || lowered.contains("superseded") {
                return "Hidden or superseded records are excluded."
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
}
