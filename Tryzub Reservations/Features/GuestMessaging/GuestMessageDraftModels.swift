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
    case cancellation

    var staffLabel: String {
        switch self {
        case .confirmation:
            return "Confirmation"
        case .reminder:
            return "Reminder"
        case .clarificationRequest:
            return "Question"
        case .largePartyConfirmation:
            return "Large party"
        case .tableReady:
            return "Table ready"
        case .cancellation:
            return "Cancellation"
        }
    }

    var draftActionTitle: String {
        staffLabel
    }
}

extension GuestMessageDraftSource {
    var staffLabel: String {
        switch self {
        case .template:
            return "Template draft"
        case .localModel:
            return "AI draft"
        case .blocked:
            return "Blocked"
        }
    }
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

enum GuestMessageOccasionFlag: String, Codable, Equatable {
    case none
    case birthday
    case anniversary
    case celebration
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
    let occasion: GuestMessageOccasionFlag
    let hasBirthdayFlag: Bool
    let hasAnniversaryFlag: Bool
    let hasCelebrationFlag: Bool
    let hasDietaryFlag: Bool
    let hasAccessibilityFlag: Bool
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

// MARK: - Display helpers

extension GuestMessageDraftKind {
    var emailTemplateKind: GuestEmailTemplateKind {
        switch self {
        case .confirmation:
            return .confirmation
        case .reminder:
            return .reminder
        case .tableReady:
            return .tableReady
        case .cancellation:
            return .cancellation
        case .clarificationRequest, .largePartyConfirmation:
            return .manualQuestion
        }
    }

    var supportsBackendManualEmailLog: Bool {
        emailTemplateKind.backendLogEmailType != nil
    }

    var usesDeterministicOperationalTemplate: Bool {
        switch self {
        case .confirmation, .reminder, .tableReady, .cancellation:
            return true
        case .clarificationRequest, .largePartyConfirmation:
            return false
        }
    }
}

extension GuestMessageDraft {
    var hasSafetyNote: Bool {
        let trimmed = safetyNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
    }

    var isBlocked: Bool {
        if source == .blocked { return true }
        let trimmed = blockedReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
    }
}
