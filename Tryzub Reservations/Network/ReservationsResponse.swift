//
//  ReservationResponse.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import Foundation

struct ReservationsResponse: Codable {
    let success: Bool
    let serverTime: String?
    let page: Int
    let perPage: Int
    let total: Int
    let totalPages: Int
    let data: [ReservationDTO]
}

struct ReservationUpdateResponse: Codable {
    let success: Bool
    let data: ReservationDTO
    let activity: MutationActivityResultDTO?
}

struct ReservationFetchResponse: Codable {
    let success: Bool
    let data: ReservationDTO
}

struct ReservationCreateResponse: Codable {
    let success: Bool
    let data: ReservationDTO
    let activity: MutationActivityResultDTO?
}

struct ReservationConfirmResponse: Codable {
    let success: Bool
    let emailStatus: ReservationEmailStatus
    let emailError: String?
    let fallback: ReservationConfirmFallback?
    let message: String?
    let data: ReservationDTO?
    let activity: MutationActivityResultDTO?
    let diagnostics: JSONValue?
}

enum ReservationConfirmFallback: String, Codable {
    case manualMail = "manual_mail"
}

struct ReservationReminderSummaryDTO: Codable, Equatable {
    let sent: Int
    let failed: Int
    let skipped: Int
    let alreadySent: Int
    let eligible: Int
    let totalChecked: Int
}

struct ReservationReminderResultDTO: Codable, Equatable, Identifiable {
    var id: Int { reservationId }

    let reservationId: Int
    let reservationTime: String?
    let status: String
    let reason: String?
    let reminderEmailSentAt: String?
    let displayMessage: String?
}

struct ReservationReminderBatchResponse: Codable {
    let success: Bool
    let date: String
    let mode: String?
    let targetTime: String?
    let morningBatchRan: Bool?
    let morningBatch: JSONValue?
    let lastBatch: JSONValue?
    let summary: ReservationReminderSummaryDTO
    let results: [ReservationReminderResultDTO]
    let diagnostics: JSONValue?
    let automaticRemindersEnabled: Bool?
    let manualBatchRemindersEnabled: Bool?
    let reminderLeadHours: Int?
    let morningReminderTime: String?
    let emailUsage: EmailUsageSummary?

    enum CodingKeys: String, CodingKey {
        case success
        case date
        case mode
        case targetTime
        case morningBatchRan
        case morningBatch
        case lastBatch
        case summary
        case results
        case diagnostics
        case automaticRemindersEnabled
        case manualBatchRemindersEnabled
        case reminderLeadHours
        case morningReminderTime
        case emailUsage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        date = try container.decode(String.self, forKey: .date)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        targetTime = try container.decodeIfPresent(String.self, forKey: .targetTime)
        morningBatchRan = try container.decodeIfPresent(Bool.self, forKey: .morningBatchRan)
        morningBatch = try container.decodeIfPresent(JSONValue.self, forKey: .morningBatch)
        lastBatch = try container.decodeIfPresent(JSONValue.self, forKey: .lastBatch)
        summary = try container.decode(ReservationReminderSummaryDTO.self, forKey: .summary)
        results = try container.decodeIfPresent([ReservationReminderResultDTO].self, forKey: .results) ?? []
        diagnostics = try container.decodeIfPresent(JSONValue.self, forKey: .diagnostics)
        automaticRemindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticRemindersEnabled)
        manualBatchRemindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .manualBatchRemindersEnabled)
        reminderLeadHours = try container.decodeFlexibleIntIfPresent(forKey: .reminderLeadHours)
        morningReminderTime = try container.decodeIfPresent(String.self, forKey: .morningReminderTime)
        emailUsage = try container.decodeIfPresent(EmailUsageSummary.self, forKey: .emailUsage)
    }
}

typealias ReservationReminderStatusResponse = ReservationReminderBatchResponse

struct ResolvedReminderAutomationSettings: Equatable {
    let automaticRemindersEnabled: Bool
    let manualBatchRemindersEnabled: Bool
    let reminderLeadHours: Int
    let morningReminderTime: String

    static func resolving(
        setup: RestaurantSetup,
        status: ReservationReminderStatusResponse?
    ) -> ResolvedReminderAutomationSettings {
        ResolvedReminderAutomationSettings(
            automaticRemindersEnabled: status?.automaticRemindersEnabled
                ?? setup.automaticRemindersEnabled,
            manualBatchRemindersEnabled: status?.manualBatchRemindersEnabled
                ?? setup.manualBatchRemindersEnabled,
            reminderLeadHours: status?.reminderLeadHours
                ?? setup.reminderLeadHours,
            morningReminderTime: resolvedMorningReminderTime(status: status, setup: setup)
        )
    }

    private static func resolvedMorningReminderTime(
        status: ReservationReminderStatusResponse?,
        setup: RestaurantSetup
    ) -> String {
        if let value = trimmedNonEmpty(status?.morningReminderTime) {
            return value
        }
        if let value = trimmedNonEmpty(setup.morningReminderTime) {
            return value
        }
        return ReminderAutomationDefaults.morningReminderTime
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct ReservationGuestManageLinkResponse: Codable {
    let success: Bool
    let data: ReservationGuestManageLinkDTO
}

struct ReservationGuestManageLinkDTO: Codable, Equatable {
    let url: String
    let expiresAt: String?
}

struct ReservationManualEmailLogResponse: Codable {
    let success: Bool
    let data: ReservationManualEmailLogDTO
}

struct ReservationManualEmailLogDTO: Codable, Equatable {
    let reservationId: Int?
    let emailType: ReservationManualEmailLogEmailType
    let status: ReservationManualEmailLogStatus
    let provider: String?
    let confirmationEmailSentAt: String?
}

struct ReservationDeleteResponse: Codable {
    let success: Bool?
    let message: String?
}

struct RestaurantSetupResponse: Codable {
    let success: Bool?
    let data: RestaurantSetupDTO?
}

struct RestaurantHoursResponse: Codable {
    let success: Bool?
    let data: RestaurantHoursDTO?
}

struct RestaurantDayAvailabilityResponse: Codable {
    let success: Bool?
    let data: RestaurantDayAvailabilityDTO?
}

struct RestaurantBlockedSlotsResponse: Codable {
    let success: Bool?
    let date: String?
    let data: [RestaurantBlockedSlotDTO]?
}

struct ImportFailuresResponse: Codable {
    let success: Bool
    let page: Int
    let perPage: Int
    let total: Int
    let totalPages: Int
    let data: [ImportFailureDTO]
}

struct PingResponseDTO: Decodable, Equatable {
    let success: Bool
    let message: String
    let time: String?
    let tableExists: Bool?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case time
        case tableExists
    }
}

// MARK: - Intelligence Envelopes

struct BusinessIntelligenceSummaryResponse: Decodable {
    let success: Bool?
    let data: BusinessIntelligenceSummaryDTO?
}

struct GuestIntelligenceProfileAPIResponse: Decodable {
    let success: Bool?
    let data: GuestIntelligenceReservationProfileDTO?
}

struct GuestIntelligenceProfileLegacyAPIResponse: Decodable {
    let success: Bool?
    let data: GuestIntelligenceSummaryDTO?
}

struct GuestIntelligenceDayAPIResponse: Decodable {
    let success: Bool?
    let data: GuestIntelligenceDayResponseDTO?
}

struct IntelligenceSystemStatusResponse: Decodable {
    let success: Bool?
    let data: IntelligenceSystemStatusDTO?
}
