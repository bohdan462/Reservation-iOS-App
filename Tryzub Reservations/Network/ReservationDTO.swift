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
