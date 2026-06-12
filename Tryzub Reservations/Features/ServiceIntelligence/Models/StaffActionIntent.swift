//
//  StaffActionIntent.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 1 foundation.
//
//  A StaffActionIntent is something staff MAY need to do manually. The system
//  suggests; staff confirms. Almost everything has `canAutoComplete == false`:
//  the app must never auto-seat, auto-complete, auto-confirm, auto-send, or
//  auto-mark deposits as paid.
//

import Foundation

enum StaffActionType: String, Codable, CaseIterable {
    case checkReservationStatus
    case markSeated
    case markComplete
    case assignTable
    case reviewNoTable
    case reviewDeposit
    case reviewPreorder
    case tellKitchen
    case tellBar
    case reviewAttachment
    case reviewGuestNote
    case callGuest
    case sendConfirmation
    case verifyGuestCount
    case prepareSetup
    case reviewGuestHistory
    case reviewAfterClose
    // Phase 4 — Booking Load Suggestions. Decision-support only: the app suggests,
    // staff confirms any real backend action (block slot, etc.). Never auto-closes.
    case suggestCloseBookingSlot
    case suggestAlternateBookingTime
    case reviewBookingWindow
    case nothingToDo

    /// The very small set of actions that could be completed by the app itself
    /// without staff judgement. Deliberately empty for now — staff confirms all.
    var canAutoComplete: Bool { false }
}

enum ActionPriority: Int, Codable, CaseIterable, Comparable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    static func < (lhs: ActionPriority, rhs: ActionPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// When the action is relevant relative to the current service moment.
enum ActionTiming: String, Codable, CaseIterable {
    case now
    case comingUp
    case later
    case afterClose
    case anytime
}

struct StaffActionIntent: Identifiable, Equatable, Codable {
    let id: String
    let type: StaffActionType
    let reservationID: String?
    let title: String
    let detail: String?
    let priority: ActionPriority
    let timing: ActionTiming
    let sourceSignalIDs: [String]
    let canAutoComplete: Bool

    init(
        id: String,
        type: StaffActionType,
        reservationID: String?,
        title: String,
        detail: String? = nil,
        priority: ActionPriority,
        timing: ActionTiming,
        sourceSignalIDs: [String] = [],
        canAutoComplete: Bool? = nil
    ) {
        self.id = id
        self.type = type
        self.reservationID = reservationID
        self.title = title
        self.detail = detail
        self.priority = priority
        self.timing = timing
        self.sourceSignalIDs = sourceSignalIDs
        self.canAutoComplete = canAutoComplete ?? type.canAutoComplete
    }
}
