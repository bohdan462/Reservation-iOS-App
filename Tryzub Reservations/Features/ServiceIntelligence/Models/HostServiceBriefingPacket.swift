//
//  HostServiceBriefingPacket.swift
//  Tryzub Reservations
//
//  Parent service briefing packet for Host Board, More -> Service Intelligence,
//  and future narrative input. This file owns safe facts only: no raw notes,
//  phone numbers, email addresses, or UI state.
//

import Foundation

enum BriefingFactKind: String, CaseIterable, Equatable {
    case dayOverview
    case arrivalWindow
    case timedArrival
    case nextArrival
    case seatedOverview
    case seatedDuration
    case tableWatch
    case waitingArrivals
    case noTableToday
    case newGuestCount
    case guestMemory
    case allergy
    case occasion
    case seatingPreference
    case reminder
    case confirmation
    case deposit
    case preorder
    case setup
    case walkInCompleted
    case completedRecap
    case noShowFollowUp
    case longStayRecap
    case businessPeak
    case serviceCalm
}

struct BriefingFact: Identifiable, Equatable {
    let id: String
    let kind: BriefingFactKind
    let reservationID: Int?
    let guestName: String?
    let partySize: Int?
    let timeLabel: String?
    let tableLabel: String?
    let count: Int?
    let secondaryCount: Int?
    let minutes: Int?
    let priority: Int

    init(
        id: String,
        kind: BriefingFactKind,
        reservationID: Int? = nil,
        guestName: String? = nil,
        partySize: Int? = nil,
        timeLabel: String? = nil,
        tableLabel: String? = nil,
        count: Int? = nil,
        secondaryCount: Int? = nil,
        minutes: Int? = nil,
        priority: Int
    ) {
        self.id = id
        self.kind = kind
        self.reservationID = reservationID
        self.guestName = guestName
        self.partySize = partySize
        self.timeLabel = timeLabel
        self.tableLabel = tableLabel
        self.count = count
        self.secondaryCount = secondaryCount
        self.minutes = minutes
        self.priority = priority
    }
}

struct BriefingSection: Identifiable, Equatable {
    let id: String
    let title: String
    let facts: [BriefingFact]
    let lines: [String]
}

struct BriefingPresentation: Equatable {
    let compactLine: String
    let compactChips: [String]
    let sections: [BriefingSection]

    static let empty = BriefingPresentation(
        compactLine: "Nothing urgent right now.",
        compactChips: [],
        sections: []
    )
}

struct BriefingTruthCounts: Equatable {
    let activeReservations: Int
    let expectedGuests: Int
    let seatedReservations: Int
    let waitingArrivals: Int
    let noTable: Int
    let completedReservations: Int
    let walkInCompleted: Int
    let noShows: Int
    let newGuests: Int?
}

struct HostServiceBriefingPacket: Equatable {
    let dateKey: String
    let serviceMode: ServiceMode
    let generatedAt: Date
    let inputFingerprint: String
    let truthCounts: BriefingTruthCounts
    let allowedGuestNames: [String]
    let allowedTableLabels: [String]
    let compactLine: String
    let compactChips: [String]
    let sections: [BriefingSection]
    let facts: [BriefingFact]

    static let empty = HostServiceBriefingPacket(
        dateKey: "",
        serviceMode: .beforeService,
        generatedAt: Date(timeIntervalSince1970: 0),
        inputFingerprint: "empty",
        truthCounts: BriefingTruthCounts(
            activeReservations: 0,
            expectedGuests: 0,
            seatedReservations: 0,
            waitingArrivals: 0,
            noTable: 0,
            completedReservations: 0,
            walkInCompleted: 0,
            noShows: 0,
            newGuests: nil
        ),
        allowedGuestNames: [],
        allowedTableLabels: [],
        compactLine: "Nothing urgent right now.",
        compactChips: [],
        sections: [],
        facts: []
    )
}
