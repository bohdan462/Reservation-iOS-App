//
//  GuestIntelligenceSignalLabels.swift
//  Tryzub Reservations
//
//  Maps backend guest intelligence signal keys to staff-readable display labels.
//
//  Backend emits snake_case keys (table_preference, service_issue).
//  ReservationsAPIClient decodes with .convertFromSnakeCase, which also rewrites
//  dictionary keys, so the keys arriving in allNoteSignals and visit signals are
//  camelCase (tablePreference, serviceIssue). Both forms are supported here so the
//  label map is correct regardless of future decoder changes or backend additions.
//

import Foundation

enum GuestIntelligenceSignalLabels {

    /// Known signal keys (both camelCase post-decode and original snake_case).
    private static let knownLabels: [String: String] = [
        // camelCase (actual form after .convertFromSnakeCase)
        "tablePreference": "Table preference",
        "serviceIssue": "Service issue",
        "occasion": "Occasion",
        "dietary": "Dietary",
        "allergy": "Allergy",
        "accessibility": "Accessibility",
        // snake_case originals — accepted as fallback if decoder config changes
        "table_preference": "Table preference",
        "service_issue": "Service issue",
    ]

    /// Returns a staff-readable display label for a signal key.
    /// Falls back to a humanized version of the key for unknown future signals.
    static func display(for key: String) -> String {
        if let known = knownLabels[key] {
            return known
        }
        return humanize(key)
    }

    /// Converts camelCase or snake_case to "Title case with spaces".
    private static func humanize(_ key: String) -> String {
        // Handle snake_case
        if key.contains("_") {
            return key
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
        // Handle camelCase: insert space before uppercase letters
        var result = ""
        for (index, char) in key.enumerated() {
            if char.isUppercase && index > 0 {
                result.append(" ")
                result.append(char.lowercased().first!)
            } else if index == 0 {
                result.append(char.uppercased().first!)
            } else {
                result.append(char)
            }
        }
        return result
    }
}
