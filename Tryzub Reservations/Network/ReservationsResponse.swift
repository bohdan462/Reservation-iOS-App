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
}

struct ReservationFetchResponse: Codable {
    let success: Bool
    let data: ReservationDTO
}

struct ReservationCreateResponse: Codable {
    let success: Bool
    let data: ReservationDTO
}

struct ReservationConfirmResponse: Codable {
    let success: Bool
    let emailStatus: ReservationEmailStatus
    let emailError: String?
    let message: String?
    let data: ReservationDTO
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
        case tableExists = "table_exists"
    }
}
