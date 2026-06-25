//
//  GuestLookupModels.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Guest Lookup Models

struct GuestLookupResult: Identifiable, Equatable {
    let id: String
    let guestKey: String?
    let displayName: String
    let phoneDigits: String?
    let email: String?
    let lastReservationDate: String?
    let totalReservations: Int
    let latestGuestNotes: String?
    let latestStaffNotes: String?
    let labelSummary: String?
    let summaryLine: String?
    let hasDietaryNote: Bool
    let isRegularGuest: Bool
    let isBackendProfile: Bool
    let identitySource: GuestLookupIdentitySource
    let matchBasis: GuestProfileLookupMatchBasis?
    let matchConfidence: GuestProfileLookupMatchConfidence?

    var prefill: ManualReservationPrefill {
        ManualReservationPrefill(
            guestName: displayName,
            phoneDigits: phoneDigits,
            email: email,
            source: .callInGuestLookup
        )
    }

    var isStrongBackendMatch: Bool {
        identitySource == .backendLookup
            && matchConfidence == .strong
            && (matchBasis == .email || matchBasis == .phone)
    }

    var requiresStaffConfirmation: Bool {
        !isStrongBackendMatch
    }

    init(
        id: String,
        guestKey: String? = nil,
        displayName: String,
        phoneDigits: String?,
        email: String?,
        lastReservationDate: String?,
        totalReservations: Int,
        latestGuestNotes: String?,
        latestStaffNotes: String?,
        labelSummary: String?,
        summaryLine: String?,
        hasDietaryNote: Bool,
        isRegularGuest: Bool,
        isBackendProfile: Bool,
        identitySource: GuestLookupIdentitySource? = nil,
        matchBasis: GuestProfileLookupMatchBasis? = nil,
        matchConfidence: GuestProfileLookupMatchConfidence? = nil
    ) {
        self.id = id
        self.guestKey = guestKey
        self.displayName = displayName
        self.phoneDigits = phoneDigits
        self.email = email
        self.lastReservationDate = lastReservationDate
        self.totalReservations = totalReservations
        self.latestGuestNotes = latestGuestNotes
        self.latestStaffNotes = latestStaffNotes
        self.labelSummary = labelSummary
        self.summaryLine = summaryLine
        self.hasDietaryNote = hasDietaryNote
        self.isRegularGuest = isRegularGuest
        self.isBackendProfile = isBackendProfile
        self.identitySource = identitySource ?? (isBackendProfile ? .cachedProfile : .localReservationHistory)
        self.matchBasis = matchBasis
        self.matchConfidence = matchConfidence
    }
}

enum GuestLookupIdentitySource: Equatable, Sendable {
    case cachedProfile
    case localReservationHistory
    case backendLookup
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

enum GuestLookupPhoneNormalizer {
    /// Digits-only US phone for guest lookup. Strips punctuation, removes leading country-code `1`s, and caps at 10 digits.
    static func digits(_ value: String) -> String {
        var digits = value.filter(\.isNumber)
        while digits.first == "1" {
            digits.removeFirst()
        }
        if digits.count > 10 {
            return String(digits.prefix(10))
        }
        return digits
    }
}

enum GuestLookupFormatting {
    static func phoneDisplay(_ digits: String) -> String {
        let cleaned = GuestLookupPhoneNormalizer.digits(digits)
        let local = cleaned

        guard local.count == 10 else { return cleaned }

        let area = local.prefix(3)
        let middle = local.dropFirst(3).prefix(3)
        let last = local.suffix(4)
        return "(\(area)) \(middle)-\(last)"
    }
}
