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
    let emailDeliveryStatus: EmailDeliveryStatus?
    let emailError: String?
    let fallback: ReservationConfirmFallback?
    let message: String?
    let data: ReservationDTO?
    let activity: MutationActivityResultDTO?
    let diagnostics: JSONValue?
}

struct ReservationCorrectionResponse: Codable {
    let success: Bool
    let emailStatus: ReservationEmailStatus?
    let emailDeliveryStatus: EmailDeliveryStatus?
    let emailError: String?
    let message: String?
    let data: ReservationDTO
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
        case settings
        case emailUsage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let settings = try container.decodeIfPresent(ReminderAutomationSettingsPayload.self, forKey: .settings)
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
        automaticRemindersEnabled = try container.decodeFlexibleBoolIfPresent(forKey: .automaticRemindersEnabled)
            ?? settings?.automaticRemindersEnabled
        manualBatchRemindersEnabled = try container.decodeFlexibleBoolIfPresent(forKey: .manualBatchRemindersEnabled)
            ?? settings?.manualBatchRemindersEnabled
        reminderLeadHours = try container.decodeFlexibleIntIfPresent(forKey: .reminderLeadHours)
            ?? settings?.reminderLeadHours
        morningReminderTime = try container.decodeIfPresent(String.self, forKey: .morningReminderTime)
            ?? settings?.morningReminderTime
        emailUsage = try container.decodeIfPresent(EmailUsageSummary.self, forKey: .emailUsage)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(targetTime, forKey: .targetTime)
        try container.encodeIfPresent(morningBatchRan, forKey: .morningBatchRan)
        try container.encodeIfPresent(morningBatch, forKey: .morningBatch)
        try container.encodeIfPresent(lastBatch, forKey: .lastBatch)
        try container.encode(summary, forKey: .summary)
        try container.encode(results, forKey: .results)
        try container.encodeIfPresent(diagnostics, forKey: .diagnostics)
        try container.encodeIfPresent(automaticRemindersEnabled, forKey: .automaticRemindersEnabled)
        try container.encodeIfPresent(manualBatchRemindersEnabled, forKey: .manualBatchRemindersEnabled)
        try container.encodeIfPresent(reminderLeadHours, forKey: .reminderLeadHours)
        try container.encodeIfPresent(morningReminderTime, forKey: .morningReminderTime)
        try container.encodeIfPresent(emailUsage, forKey: .emailUsage)
    }
}

typealias ReservationReminderStatusResponse = ReservationReminderBatchResponse

private struct ReminderAutomationSettingsPayload: Decodable {
    let automaticRemindersEnabled: Bool?
    let manualBatchRemindersEnabled: Bool?
    let reminderLeadHours: Int?
    let morningReminderTime: String?

    enum CodingKeys: String, CodingKey {
        case automaticRemindersEnabled
        case manualBatchRemindersEnabled
        case reminderLeadHours
        case morningReminderTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        automaticRemindersEnabled = try container.decodeFlexibleBoolIfPresent(forKey: .automaticRemindersEnabled)
        manualBatchRemindersEnabled = try container.decodeFlexibleBoolIfPresent(forKey: .manualBatchRemindersEnabled)
        reminderLeadHours = try container.decodeFlexibleIntIfPresent(forKey: .reminderLeadHours)
        morningReminderTime = try container.decodeIfPresent(String.self, forKey: .morningReminderTime)
    }
}

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

struct ReservationAttachmentListResponseDTO: Decodable {
    let success: Bool
    let reservationID: Int
    let attachments: [ReservationAttachmentDTO]

    enum CodingKeys: String, CodingKey {
        case success
        case reservationID
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeFlexibleBoolIfPresent(forKey: .success) ?? true
        reservationID = try container.decodeFlexibleIntIfPresent(forKey: .reservationID) ?? 0
        attachments = try container.decodeIfPresent([ReservationAttachmentDTO].self, forKey: .attachments) ?? []
    }
}

struct ReservationAttachmentResponseDTO: Decodable {
    let success: Bool
    let reservationID: Int?
    let attachment: ReservationAttachmentDTO?
    let data: ReservationAttachmentDTO?

    enum CodingKeys: String, CodingKey {
        case success
        case reservationID
        case attachment
        case data
    }

    var resolvedAttachment: ReservationAttachmentDTO? {
        attachment ?? data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeFlexibleBoolIfPresent(forKey: .success) ?? true
        reservationID = try container.decodeFlexibleIntIfPresent(forKey: .reservationID)
        attachment = try container.decodeIfPresent(ReservationAttachmentDTO.self, forKey: .attachment)
        data = try container.decodeIfPresent(ReservationAttachmentDTO.self, forKey: .data)
    }
}

struct ReservationAttachmentDTO: Decodable, Identifiable, Equatable {
    let id: Int
    let reservationID: Int
    let label: String
    let caption: String?
    let originalFilename: String?
    let mimeType: String
    let fileSizeBytes: Int?
    let width: Int?
    let height: Int?
    let createdAt: String?
    let updatedAt: String?
    let uploadedByUserID: Int?
    let contentPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reservationID
        case label
        case caption
        case originalFilename
        case mimeType
        case fileSizeBytes
        case width
        case height
        case createdAt
        case updatedAt
        case uploadedByUserID
        case contentPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleIntIfPresent(forKey: .id) ?? 0
        reservationID = try container.decodeFlexibleIntIfPresent(forKey: .reservationID) ?? 0
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? AttachmentLabel.other.backendValue
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        originalFilename = try container.decodeIfPresent(String.self, forKey: .originalFilename)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "image/jpeg"
        fileSizeBytes = try container.decodeFlexibleIntIfPresent(forKey: .fileSizeBytes)
        width = try container.decodeFlexibleIntIfPresent(forKey: .width)
        height = try container.decodeFlexibleIntIfPresent(forKey: .height)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        uploadedByUserID = try container.decodeFlexibleIntIfPresent(forKey: .uploadedByUserID)
        contentPath = try container.decodeIfPresent(String.self, forKey: .contentPath)
    }
}

struct ReservationAttachmentUpdateRequest: Encodable {
    let label: String
    let caption: String?
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
