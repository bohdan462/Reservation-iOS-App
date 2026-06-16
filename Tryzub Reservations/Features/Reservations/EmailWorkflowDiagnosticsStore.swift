//
//  EmailWorkflowDiagnosticsStore.swift
//  Tryzub Reservations
//
//  Developer-only snapshots of recent email workflow responses.
//

import Foundation

@MainActor
final class EmailWorkflowDiagnosticsStore: ObservableObject {
    static let shared = EmailWorkflowDiagnosticsStore()

    @Published private(set) var lastConfirmResponseJSON: String?
    @Published private(set) var lastReminderSendResponseJSON: String?
    @Published private(set) var lastReminderStatusResponseJSON: String?

    private init() {}

    func recordConfirm(_ response: ReservationConfirmResponse) {
        lastConfirmResponseJSON = Self.prettyPrintedRedactedJSON(response)
    }

    func recordReminderSend(_ response: ReservationReminderBatchResponse) {
        lastReminderSendResponseJSON = Self.prettyPrintedRedactedJSON(response)
    }

    func recordReminderStatus(_ response: ReservationReminderStatusResponse) {
        lastReminderStatusResponseJSON = Self.prettyPrintedRedactedJSON(response)
    }

    func clear() {
        lastConfirmResponseJSON = nil
        lastReminderSendResponseJSON = nil
        lastReminderStatusResponseJSON = nil
    }

    private static func prettyPrintedRedactedJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "<unable to encode response>"
        }
        return redact(text)
    }

    private static func redact(_ text: String) -> String {
        var redacted = text.replacingOccurrences(
            of: #""(token|raw_token|manage_token|manageToken)"\s*:\s*"[^"]*""#,
            with: #""$1": "<redacted>""#,
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"https?://[^\s"]*(token|manage_token|manageToken)=[^\s"]+"#,
            with: "<redacted-manage-url>",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #""Authorization"\s*:\s*"[^"]*""#,
            with: #""Authorization": "<redacted>""#,
            options: .regularExpression
        )
        return redacted
    }
}

