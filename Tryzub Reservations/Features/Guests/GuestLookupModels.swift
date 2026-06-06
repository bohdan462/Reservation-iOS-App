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
