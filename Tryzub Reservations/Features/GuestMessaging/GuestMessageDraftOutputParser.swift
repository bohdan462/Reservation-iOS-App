//
//  GuestMessageDraftOutputParser.swift
//  Tryzub Reservations
//

import Foundation

enum GuestMessageDraftOutputParser {

    static func parse(_ text: String) -> GuestMessageDraft? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidates = [trimmed, strippedMarkdownFences(from: trimmed)]
        for candidate in candidates {
            if let draft = decodeJSON(candidate) {
                return draft
            }
            if let extracted = extractJSONObject(from: candidate),
               let draft = decodeJSON(extracted) {
                return draft
            }
        }
        return nil
    }

    // MARK: - Private

    private static func decodeJSON(_ json: String) -> GuestMessageDraft? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            return nil
        }

        let subject = payload.emailSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = payload.emailBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let sms = payload.shortMessageBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty, !body.isEmpty, !sms.isEmpty else { return nil }

        return GuestMessageDraft(
            emailSubject: subject,
            emailBody: body,
            shortMessageBody: sms,
            safetyNote: payload.safetyNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            blockedReason: payload.blockedReason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            source: .localModel
        )
    }

    private static func strippedMarkdownFences(from text: String) -> String {
        var value = text
        if value.hasPrefix("```") {
            value = value.replacingOccurrences(of: "```json", with: "")
            value = value.replacingOccurrences(of: "```", with: "")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[start...end])
    }

    private struct Payload: Decodable {
        let emailSubject: String
        let emailBody: String
        let shortMessageBody: String
        let safetyNote: String?
        let blockedReason: String?
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
