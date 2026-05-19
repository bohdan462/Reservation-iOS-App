//
//  ReservationPreviewData.swift
//  Tryzub Reservations
//

import Foundation
import SwiftData

#if DEBUG
enum ReservationPreviewData {
    static let sampleDTOs: [ReservationDTO] = [
        ReservationDTO(
            id: 56,
            sourceSubmissionId: 282,
            guestName: "Abhinav Srinath",
            email: "abhi1025@yahoo.com",
            phone: "5133058537",
            reservationDate: "2026-05-18",
            reservationTime: "17:30:00",
            partySize: 2,
            guestNotes: "Window seat if possible.",
            staffNotes: nil,
            status: .new,
            tableName: nil,
            createdAt: "2026-05-14 13:36:54",
            updatedAt: nil,
            confirmedAt: nil,
            confirmationEmailSentAt: nil,
            reminderEmailSentAt: nil,
            supersededById: nil
        ),
        ReservationDTO(
            id: 61,
            sourceSubmissionId: 301,
            guestName: "Diana Kovalenko",
            email: "diana.k@example.com",
            phone: "3125550198",
            reservationDate: "2026-05-19",
            reservationTime: "19:00:00",
            partySize: 6,
            guestNotes: "Birthday dinner.",
            staffNotes: "Large party — confirm patio availability.",
            status: .needsReview,
            tableName: nil,
            createdAt: "2026-05-15 09:12:00",
            updatedAt: "2026-05-17 14:20:00",
            confirmedAt: nil,
            confirmationEmailSentAt: nil,
            reminderEmailSentAt: nil,
            supersededById: nil
        ),
        ReservationDTO(
            id: 72,
            sourceSubmissionId: 318,
            guestName: "Marcus Chen",
            email: "marcus.chen@example.com",
            phone: "7735554421",
            reservationDate: "2026-05-18",
            reservationTime: "18:00:00",
            partySize: 4,
            guestNotes: nil,
            staffNotes: "Called guest. Confirmed.",
            status: .confirmed,
            tableName: "12",
            createdAt: "2026-05-16 11:05:22",
            updatedAt: "2026-05-18 10:15:00",
            confirmedAt: "2026-05-18 10:15:00",
            confirmationEmailSentAt: nil,
            reminderEmailSentAt: nil,
            supersededById: nil
        ),
        ReservationDTO(
            id: 84,
            sourceSubmissionId: 340,
            guestName: "Olena Petrenko",
            email: "olena.p@example.com",
            phone: "8725553310",
            reservationDate: "2026-05-18",
            reservationTime: "20:30:00",
            partySize: 2,
            guestNotes: nil,
            staffNotes: nil,
            status: .seated,
            tableName: "7",
            createdAt: "2026-05-17 16:44:10",
            updatedAt: "2026-05-18 20:35:00",
            confirmedAt: "2026-05-17 18:00:00",
            confirmationEmailSentAt: nil,
            reminderEmailSentAt: nil,
            supersededById: nil
        ),
        ReservationDTO(
            id: 91,
            sourceSubmissionId: 355,
            guestName: "James Wilson",
            email: "jwilson@example.com",
            phone: "6305557788",
            reservationDate: "2026-05-22",
            reservationTime: "12:00:00",
            partySize: 3,
            guestNotes: "Gluten-free menu requested.",
            staffNotes: nil,
            status: .confirmed,
            tableName: "4",
            createdAt: "2026-05-18 08:30:00",
            updatedAt: nil,
            confirmedAt: "2026-05-18 09:00:00",
            confirmationEmailSentAt: nil,
            reminderEmailSentAt: nil,
            supersededById: nil
        ),
        ReservationDTO(
            id: 95,
            sourceSubmissionId: 362,
            guestName: "Sofia Martinez",
            email: "sofia.m@example.com",
            phone: "8475552299",
            reservationDate: "2026-05-10",
            reservationTime: "19:30:00",
            partySize: 2,
            guestNotes: nil,
            staffNotes: "Guest called to cancel.",
            status: .cancelled,
            tableName: nil,
            createdAt: "2026-05-08 12:00:00",
            updatedAt: "2026-05-09 15:22:00",
            confirmedAt: nil,
            confirmationEmailSentAt: nil,
            reminderEmailSentAt: nil,
            supersededById: nil
        ),
        ReservationDTO(
            id: 102,
            sourceSubmissionId: 371,
            guestName: "Yuki Tanaka",
            email: "yuki.tanaka@example.com",
            phone: "2245556612",
            reservationDate: "2026-05-25",
            reservationTime: "21:00:00",
            partySize: 5,
            guestNotes: "Anniversary.",
            staffNotes: nil,
            status: .new,
            tableName: nil,
            createdAt: "2026-05-18 14:10:00",
            updatedAt: nil,
            confirmedAt: nil,
            confirmationEmailSentAt: nil,
            reminderEmailSentAt: nil,
            supersededById: nil
        )
    ]

    @MainActor
    static var previewContainer: ModelContainer = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: ReservationRecord.self,
            configurations: configuration
        )
        let context = container.mainContext
        for dto in sampleDTOs {
            context.insert(ReservationRecord(from: dto))
        }
        return container
    }()

    @MainActor
    static var sampleRecord: ReservationRecord {
        let context = previewContainer.mainContext
        var descriptor = FetchDescriptor<ReservationRecord>(sortBy: [SortDescriptor(\.remoteID)])
        descriptor.fetchLimit = 1
        if let record = try? context.fetch(descriptor).first {
            return record
        }
        let record = ReservationRecord(from: sampleDTOs[0])
        context.insert(record)
        return record
    }
}

extension ReservationsAPIClient {
    static var preview: ReservationsAPIClient {
        ReservationsAPIClient(
            baseURL: URL(string: "https://example.com/wp-json/tryzub/v1")!,
            username: "preview",
            applicationPassword: "preview"
        )
    }
}
#endif
