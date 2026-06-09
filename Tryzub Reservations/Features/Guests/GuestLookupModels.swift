//
//  GuestLookupModels.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Guest Lookup Models

struct GuestLookupResult: Identifiable, Equatable {
    let id: String
    let displayName: String
    let phoneDigits: String?
    let email: String?
    let lastReservationDate: String?
    let totalReservations: Int
    let latestGuestNotes: String?
    let latestStaffNotes: String?

    var prefill: ManualReservationPrefill {
        ManualReservationPrefill(
            guestName: displayName,
            phoneDigits: phoneDigits,
            email: email,
            source: .callInGuestLookup
        )
    }
}

struct ManualReservationPrefill: Equatable {
    var guestName: String
    var phoneDigits: String?
    var email: String?
    var source: ManualReservationPrefillSource

    static let blankCallIn = ManualReservationPrefill(
        guestName: "",
        phoneDigits: nil,
        email: nil,
        source: .blankCallIn
    )
}

enum ManualReservationPrefillSource: String, Equatable {
    case blankCallIn
    case callInGuestLookup
}

enum GuestLookupFormatting {
    static func phoneDisplay(_ digits: String) -> String {
        let cleaned = digits.filter(\.isNumber)
        let local = cleaned.count == 11 && cleaned.first == "1"
            ? String(cleaned.dropFirst())
            : cleaned

        guard local.count == 10 else { return cleaned }

        let area = local.prefix(3)
        let middle = local.dropFirst(3).prefix(3)
        let last = local.suffix(4)
        return "(\(area)) \(middle)-\(last)"
    }
}
