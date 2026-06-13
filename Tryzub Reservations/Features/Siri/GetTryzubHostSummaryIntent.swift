//
//  GetTryzubHostSummaryIntent.swift
//  Tryzub Reservations
//

import AppIntents

struct GetTryzubHostSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Tryzub Host Summary"
    static let description = IntentDescription("Summarizes today's Tryzub reservations for staff.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = await TryzubHostSummaryIntentService.buildTodaySummary()
        return .result(dialog: "\(summary)")
    }
}
