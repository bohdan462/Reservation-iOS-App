//
//  ReservationDTO.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import Foundation

enum ReservationStatus: String, Codable, CaseIterable, Identifiable {
    case new
    case needsReview = "needs_review"
    case confirmed
    case seated
    case completed
    case cancelled
    case noShow = "no_show"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ReservationStatus(rawValue: rawValue) ?? .needsReview
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayName: String {
        switch self {
        case .new:
            return "New"
        case .needsReview:
            return "Needs Review"
        case .confirmed:
            return "Confirmed"
        case .seated:
            return "Seated"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        case .noShow:
            return "No Show"
        }
    }
}

enum ReservationSourceType: String, Codable, CaseIterable, Identifiable {
    case form
    case manualCallIn = "manual_call_in"
    case manualWalkIn = "manual_walk_in"
    case knownGuestManual = "known_guest_manual"
    case importRepair = "import_repair"
    case unknown

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ReservationSourceType(rawValue: rawValue) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayName: String {
        switch self {
        case .form:
            return "Website"
        case .manualCallIn:
            return "Call-in"
        case .manualWalkIn:
            return "Walk-in"
        case .knownGuestManual:
            return "Known guest"
        case .importRepair:
            return "Import repair"
        case .unknown:
            return "Unknown"
        }
    }

    var isManualSource: Bool {
        switch self {
        case .manualCallIn, .manualWalkIn, .knownGuestManual, .importRepair:
            return true
        case .form, .unknown:
            return false
        }
    }
}

struct ReservationDTO: Codable, Identifiable, Equatable {
    let id: Int
    let sourceSubmissionId: Int?
    let guestName: String
    let email: String
    let phone: String
    let reservationDate: String
    let reservationTime: String
    let partySize: Int
    let guestNotes: String?
    let staffNotes: String?
    let status: ReservationStatus
    let tableName: String?
    let createdAt: String
    let updatedAt: String?
    let confirmedAt: String?
    let confirmationEmailSentAt: String?
    let reminderEmailSentAt: String?
    let supersededById: Int?
    var sourceType: ReservationSourceType? = nil
    var createdByUserId: Int? = nil
    var createdByDevice: String? = nil
    var isHidden: Bool? = nil
    var hiddenAt: String? = nil
    var hiddenReason: String? = nil
    var hiddenByUserId: Int? = nil
    
    
    enum CodingKeys: String, CodingKey {
        case id
        case sourceSubmissionId
        case guestName
        case email
        case phone
        case reservationDate
        case reservationTime
        case partySize
        case guestNotes
        case staffNotes
        case status
        case tableName
        case createdAt
        case updatedAt
        case confirmedAt
        case confirmationEmailSentAt
        case reminderEmailSentAt
        case supersededById
        case sourceType
        case createdByUserId
        case createdByDevice
        case isHidden
        case hiddenAt
        case hiddenReason
        case hiddenByUserId
    }

    init(
        id: Int,
        sourceSubmissionId: Int?,
        guestName: String,
        email: String,
        phone: String,
        reservationDate: String,
        reservationTime: String,
        partySize: Int,
        guestNotes: String?,
        staffNotes: String?,
        status: ReservationStatus,
        tableName: String?,
        createdAt: String,
        updatedAt: String?,
        confirmedAt: String?,
        confirmationEmailSentAt: String?,
        reminderEmailSentAt: String?,
        supersededById: Int?,
        sourceType: ReservationSourceType? = nil,
        createdByUserId: Int? = nil,
        createdByDevice: String? = nil,
        isHidden: Bool? = nil,
        hiddenAt: String? = nil,
        hiddenReason: String? = nil,
        hiddenByUserId: Int? = nil
    ) {
        self.id = id
        self.sourceSubmissionId = sourceSubmissionId
        self.guestName = guestName
        self.email = email
        self.phone = phone
        self.reservationDate = reservationDate
        self.reservationTime = reservationTime
        self.partySize = partySize
        self.guestNotes = guestNotes
        self.staffNotes = staffNotes
        self.status = status
        self.tableName = tableName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.confirmedAt = confirmedAt
        self.confirmationEmailSentAt = confirmationEmailSentAt
        self.reminderEmailSentAt = reminderEmailSentAt
        self.supersededById = supersededById
        self.sourceType = sourceType
        self.createdByUserId = createdByUserId
        self.createdByDevice = createdByDevice
        self.isHidden = isHidden
        self.hiddenAt = hiddenAt
        self.hiddenReason = hiddenReason
        self.hiddenByUserId = hiddenByUserId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        sourceSubmissionId = try container.decodeIfPresent(Int.self, forKey: .sourceSubmissionId)
        guestName = try container.decode(String.self, forKey: .guestName)
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try container.decode(String.self, forKey: .phone)
        reservationDate = try container.decode(String.self, forKey: .reservationDate)
        reservationTime = try container.decode(String.self, forKey: .reservationTime)
        partySize = try container.decode(Int.self, forKey: .partySize)
        guestNotes = try container.decodeIfPresent(String.self, forKey: .guestNotes)
        staffNotes = try container.decodeIfPresent(String.self, forKey: .staffNotes)
        status = try container.decode(ReservationStatus.self, forKey: .status)
        tableName = try container.decodeIfPresent(String.self, forKey: .tableName)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        confirmedAt = try container.decodeIfPresent(String.self, forKey: .confirmedAt)
        confirmationEmailSentAt = try container.decodeIfPresent(String.self, forKey: .confirmationEmailSentAt)
        reminderEmailSentAt = try container.decodeIfPresent(String.self, forKey: .reminderEmailSentAt)
        supersededById = try container.decodeIfPresent(Int.self, forKey: .supersededById)
        sourceType = try container.decodeIfPresent(ReservationSourceType.self, forKey: .sourceType)
        createdByUserId = try container.decodeIfPresent(Int.self, forKey: .createdByUserId)
        createdByDevice = try container.decodeIfPresent(String.self, forKey: .createdByDevice)
        isHidden = try container.decodeFlexibleBoolIfPresent(forKey: .isHidden) ?? false
        hiddenAt = try container.decodeIfPresent(String.self, forKey: .hiddenAt)
        hiddenReason = try container.decodeIfPresent(String.self, forKey: .hiddenReason)
        hiddenByUserId = try container.decodeIfPresent(Int.self, forKey: .hiddenByUserId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(sourceSubmissionId, forKey: .sourceSubmissionId)
        try container.encode(guestName, forKey: .guestName)
        try container.encode(email, forKey: .email)
        try container.encode(phone, forKey: .phone)
        try container.encode(reservationDate, forKey: .reservationDate)
        try container.encode(reservationTime, forKey: .reservationTime)
        try container.encode(partySize, forKey: .partySize)
        try container.encodeIfPresent(guestNotes, forKey: .guestNotes)
        try container.encodeIfPresent(staffNotes, forKey: .staffNotes)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(tableName, forKey: .tableName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(confirmedAt, forKey: .confirmedAt)
        try container.encodeIfPresent(confirmationEmailSentAt, forKey: .confirmationEmailSentAt)
        try container.encodeIfPresent(reminderEmailSentAt, forKey: .reminderEmailSentAt)
        try container.encodeIfPresent(supersededById, forKey: .supersededById)
        try container.encodeIfPresent(sourceType, forKey: .sourceType)
        try container.encodeIfPresent(createdByUserId, forKey: .createdByUserId)
        try container.encodeIfPresent(createdByDevice, forKey: .createdByDevice)
        try container.encodeIfPresent(isHidden, forKey: .isHidden)
        try container.encodeIfPresent(hiddenAt, forKey: .hiddenAt)
        try container.encodeIfPresent(hiddenReason, forKey: .hiddenReason)
        try container.encodeIfPresent(hiddenByUserId, forKey: .hiddenByUserId)
    }
}

extension ReservationDTO {
    var reservationSortKey: String {
        "\(reservationDate) \(reservationTime)"
    }
}

struct ReservationUpdateRequest: Encodable {
    var guestName: String? = nil
    var email: String? = nil
    var phone: String? = nil
    var reservationDate: String? = nil
    var reservationTime: String? = nil
    var partySize: Int? = nil
    var guestNotes: String? = nil
    var staffNotes: String? = nil
    var status: ReservationStatus? = nil
    var tableName: String? = nil
    var supersededById: Int? = nil
    var isHidden: Bool? = nil
    var hiddenReason: String? = nil
}

struct ReservationCreateRequest: Encodable {
    var sourceSubmissionId: Int?
    var guestName: String
    var email: String
    var phone: String
    var reservationDate: String
    var reservationTime: String
    var partySize: Int
    var guestNotes: String?
    var staffNotes: String?
    var tableName: String?
    var sourceType: ReservationSourceType = .manualCallIn
    var createdByDevice: String? = "ios"
    var status: ReservationStatus = .confirmed
}

enum ReservationEmailStatus: String, Codable {
    case sent
    case failed
    case alreadySent = "already_sent"
    case skipped
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ReservationEmailStatus(rawValue: rawValue) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct ImportFailureDTO: Codable, Identifiable, Equatable {
    let failureId: Int?
    let sourceSubmissionId: Int?
    let errorCode: String?
    let errorMessage: String
    let reservation: ImportFailureReservationSnapshot?
    let submittedAt: String?
    let submittedAtGmt: String?
    let submissionStatus: String?
    let rawFields: [String: String]?
    let rawPayload: JSONValue?
    let status: String?
    let createdAt: String?

    var id: Int { failureId ?? sourceSubmissionId ?? -1 }

    enum CodingKeys: String, CodingKey {
        case failureId = "id"
        case sourceSubmissionId
        case errorCode
        case errorMessage
        case reservation
        case submittedAt
        case submittedAtGmt
        case submissionStatus
        case rawFields
        case rawPayload
        case status
        case createdAt
    }
}

struct ImportFailureReservationSnapshot: Codable, Equatable {
    let id: Int?
    let createdAt: String?
    let createdAtGmt: String?
    let guestName: String?
    let email: String?
    let phone: String?
    let reservationDate: String?
    let reservationTime: String?
    let partySize: Int?
    let notes: String?
}

struct RestaurantSetupDTO: Codable, Equatable {
    let restaurantKey: String
    let businessName: String
    let timezone: String
    let defaultPartySize: Int
    let callInPlaceholderEmail: String
    let fromEmail: String
    let replyToEmail: String
    let createdAt: String?
    let updatedAt: String?
}

struct RestaurantSetup: Codable, Equatable {
    var restaurantKey: String
    var businessName: String
    var timezone: String
    var defaultPartySize: Int
    var callInPlaceholderEmail: String
    var fromEmail: String
    var replyToEmail: String
    var createdAt: String?
    var updatedAt: String?

    static let `default` = RestaurantSetup(
        restaurantKey: "tryzub",
        businessName: "Tryzub Ukrainian Kitchen",
        timezone: "America/Chicago",
        defaultPartySize: 2,
        callInPlaceholderEmail: "callinreservation@tryzubchicago.com",
        fromEmail: "reservations@tryzubchicago.com",
        replyToEmail: "reservations@tryzubchicago.com",
        createdAt: nil,
        updatedAt: nil
    )

    init(dto: RestaurantSetupDTO) {
        restaurantKey = dto.restaurantKey
        businessName = dto.businessName
        timezone = dto.timezone
        defaultPartySize = dto.defaultPartySize
        callInPlaceholderEmail = dto.callInPlaceholderEmail
        fromEmail = dto.fromEmail
        replyToEmail = dto.replyToEmail
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
    }

    init(
        restaurantKey: String,
        businessName: String,
        timezone: String,
        defaultPartySize: Int,
        callInPlaceholderEmail: String,
        fromEmail: String,
        replyToEmail: String,
        createdAt: String?,
        updatedAt: String?
    ) {
        self.restaurantKey = restaurantKey
        self.businessName = businessName
        self.timezone = timezone
        self.defaultPartySize = defaultPartySize
        self.callInPlaceholderEmail = callInPlaceholderEmail
        self.fromEmail = fromEmail
        self.replyToEmail = replyToEmail
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct RestaurantSetupUpdateRequest: Encodable {
    var businessName: String? = nil
    var timezone: String? = nil
    var defaultPartySize: Int? = nil
    var callInPlaceholderEmail: String? = nil
    var fromEmail: String? = nil
    var replyToEmail: String? = nil
}

extension KeyedDecodingContainer {
    func decodeFlexibleBoolIfPresent(forKey key: Key) throws -> Bool? {
        if let boolValue = try? decodeIfPresent(Bool.self, forKey: key) {
            return boolValue
        }

        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return intValue != 0
        }

        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "1" || normalized == "true" || normalized == "yes"
        }

        return nil
    }
}
