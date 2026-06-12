//
//  ReservationStructuredNoteRecord.swift
//  Tryzub Reservations
//
//  Local-first SwiftData record for structured per-reservation staff notes.
//  Keyed by reservationRemoteID — survives cache flushes.
//
//  These fields are NOT yet backed by the backend. They are iOS-local until
//  backend endpoints are added. The canonical general notes remain on
//  ReservationRecord.guestNotes / .staffNotes.
//
//  Needed future backend fields / endpoints:
//    PATCH /managed-reservations/{id}:
//      manager_note, kitchen_note, bar_note, setup_note,
//      deposit_note, deposit_status, deposit_amount,
//      preorder_note, preorder_status, banquet_note
//

import Foundation
import SwiftData

// MARK: - Deposit status

enum DepositStatus: String, CaseIterable {
    case none = "none"
    case mentioned = "mentioned"
    case needsReview = "needs_review"
    case verified = "verified"

    var staffLabel: String {
        switch self {
        case .none: return "None"
        case .mentioned: return "Mentioned"
        case .needsReview: return "Needs review"
        case .verified: return "Verified"
        }
    }

    var isActionable: Bool { self == .mentioned || self == .needsReview }
}

// MARK: - Preorder status

enum PreorderStatus: String, CaseIterable {
    case none = "none"
    case mentioned = "mentioned"
    case confirmed = "confirmed"

    var staffLabel: String {
        switch self {
        case .none: return "None"
        case .mentioned: return "Mentioned"
        case .confirmed: return "Confirmed"
        }
    }

    var isActionable: Bool { self == .mentioned }
}

// MARK: - Model

@Model
final class ReservationStructuredNoteRecord {

    // Foreign key — survives ReservationRecord cache flushes.
    @Attribute(.unique)
    var reservationRemoteID: Int

    // MARK: Staff-visible note fields

    /// Manager-level note: payment, deposit decision, special arrangements.
    var managerNote: String?

    /// Kitchen note: preorder, food allergy, birthday cake, dishes, dietary detail.
    var kitchenNote: String?

    /// Bar note: drinks, champagne, bottle service, cocktail preference.
    var barNote: String?

    /// Setup note: high chair, wheelchair, quiet table, special layout, decorations.
    var setupNote: String?

    // MARK: Deposit tracking

    /// Free-form deposit info (e.g. "$200 cash" or "Venmo @tryzub").
    var depositNoteText: String?

    /// Raw DepositStatus value stored as String for SwiftData compatibility.
    var depositStatusRaw: String

    /// Free-form deposit amount (e.g. "$200").
    var depositAmountText: String?

    // MARK: Preorder / Banquet

    /// Preorder details: specific dishes, counts, dietary restrictions.
    var preorderNoteText: String?

    /// Raw PreorderStatus value stored as String for SwiftData compatibility.
    var preorderStatusRaw: String

    /// Banquet / package note: full menu, package tier, guest count for kitchen.
    var banquetNoteText: String?

    // MARK: Metadata

    var updatedAt: Date

    // MARK: Init

    init(reservationRemoteID: Int) {
        self.reservationRemoteID = reservationRemoteID
        self.depositStatusRaw = DepositStatus.none.rawValue
        self.preorderStatusRaw = PreorderStatus.none.rawValue
        self.updatedAt = Date()
    }

    // MARK: Typed accessors

    var depositStatus: DepositStatus {
        get { DepositStatus(rawValue: depositStatusRaw) ?? .none }
        set { depositStatusRaw = newValue.rawValue; updatedAt = Date() }
    }

    var preorderStatus: PreorderStatus {
        get { PreorderStatus(rawValue: preorderStatusRaw) ?? .none }
        set { preorderStatusRaw = newValue.rawValue; updatedAt = Date() }
    }

    // MARK: Content checks

    var hasDepositContent: Bool {
        depositStatus != .none
        || !(depositNoteText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        || !(depositAmountText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var hasPreorderContent: Bool {
        preorderStatus != .none
        || !(preorderNoteText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        || !(banquetNoteText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var hasStaffNoteContent: Bool {
        [managerNote, kitchenNote, barNote, setupNote]
            .compactMap { $0 }
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var hasAnyContent: Bool {
        hasDepositContent || hasPreorderContent || hasStaffNoteContent
    }
}
