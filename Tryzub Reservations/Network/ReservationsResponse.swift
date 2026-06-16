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
}

typealias ReservationReminderStatusResponse = ReservationReminderBatchResponse

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
        case tableExists = "table_exists"
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
