//
//  GuestMessageDraftModels.swift
//  Tryzub Reservations
//
//  Allowlisted packet and draft types for staff-controlled guest message drafts.
//

import Foundation

// MARK: - Kind

enum GuestMessageDraftKind: String, Codable, CaseIterable, Equatable {
    case confirmation
    case reminder
    case clarificationRequest
    case largePartyConfirmation
    case tableReady
}

// MARK: - Tone & language

enum GuestMessageTone: String, Codable, Equatable {
    case warmProfessional
    case concise
    case formal
}

enum GuestMessageLanguage: String, Codable, Equatable {
    case english
}

// MARK: - Restaurant profile

struct ReservationEmailRestaurantProfile: Equatable {
    let name: String
    let phone: String?
    let address: String?

    static let workflowDefault = ReservationEmailRestaurantProfile(
        name: ReservationEmailWorkflow.restaurantName,
        phone: ReservationEmailWorkflow.restaurantPhone,
        address: ReservationEmailWorkflow.restaurantAddressLine
    )
}

// MARK: - Packet

struct GuestMessageDraftPacket: Codable, Equatable {
    static let currentVersion = "1"

    let version: String
    let kind: GuestMessageDraftKind
    let createdAt: Date

    let restaurantName: String
    let restaurantPhone: String?
    let restaurantAddress: String?
    let reservationManageURL: String?

    let guestFirstName: String?
    let reservationDateDisplay: String
    let reservationTimeDisplay: String
    let partySize: Int
    let tableName: String?

    let isLargeParty: Bool
    let hasSpecialOccasionFlag: Bool
    let hasSeatingPreferenceFlag: Bool
    let hasAllergyOrAccessibilityFlag: Bool
    let needsReview: Bool

    let tone: GuestMessageTone
    let language: GuestMessageLanguage
    let policyHints: [String]
    let blockedFields: [String]
}

// MARK: - Draft

struct GuestMessageDraft: Codable, Equatable {
    let emailSubject: String
    let emailBody: String
    let shortMessageBody: String
    let safetyNote: String?
    let blockedReason: String?
    let source: GuestMessageDraftSource
}

enum GuestMessageDraftSource: String, Codable, Equatable {
    case template
    case localModel
    case blocked
}
