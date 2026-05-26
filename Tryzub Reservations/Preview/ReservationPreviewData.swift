//
//  ReservationPreviewData.swift
//  Tryzub Reservations
//

import Foundation
import SwiftData

#if DEBUG
enum ReservationPreviewData {
    static let sampleDTOs: [ReservationDTO] = baseSampleDTOs
        + ninaSeenBeforeDTOs
        + mariaRegularDTOs
        + petroFrequentRegularDTOs

    private static let baseSampleDTOs: [ReservationDTO] = [
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
        ),
        ReservationDTO(
            id: 130,
            sourceSubmissionId: 405,
            guestName: "Marcus Chen",
            email: "marcus.chen@example.com",
            phone: "7735554421",
            reservationDate: "2026-04-12",
            reservationTime: "19:00:00",
            partySize: 4,
            guestNotes: "Prefers a quieter table.",
            staffNotes: "Liked varenyky and asked about live music nights.",
            status: .completed,
            tableName: "9",
            createdAt: "2026-04-08 10:40:00",
            updatedAt: "2026-04-12 21:10:00",
            confirmedAt: "2026-04-08 11:00:00",
            confirmationEmailSentAt: "2026-04-08 11:01:00",
            reminderEmailSentAt: nil,
            supersededById: nil
        ),
        ReservationDTO(
            id: 131,
            sourceSubmissionId: nil,
            guestName: "Marcus Chen",
            email: "callin+manual-131@tryzubchicago.com",
            phone: "7735554421",
            reservationDate: "2026-06-01",
            reservationTime: "19:30:00",
            partySize: 5,
            guestNotes: nil,
            staffNotes: "Call-in. Mentioned bringing friends from out of town.",
            status: .confirmed,
            tableName: "12",
            createdAt: "2026-05-20 14:10:00",
            updatedAt: nil,
            confirmedAt: "2026-05-20 14:14:00",
            confirmationEmailSentAt: nil,
            reminderEmailSentAt: nil,
            supersededById: nil
        ),
        ReservationDTO(
            id: 132,
            sourceSubmissionId: 406,
            guestName: "Mark Chen",
            email: "markc@example.net",
            phone: "3127774421",
            reservationDate: "2026-03-15",
            reservationTime: "19:00:00",
            partySize: 4,
            guestNotes: nil,
            staffNotes: "Possible same guest; phone ending matched another Chen record.",
            status: .cancelled,
            tableName: nil,
            createdAt: "2026-03-10 09:10:00",
            updatedAt: "2026-03-12 12:30:00",
            confirmedAt: nil,
            confirmationEmailSentAt: nil,
            reminderEmailSentAt: nil,
            supersededById: nil
        )
    ]

    private static let ninaSeenBeforeDTOs: [ReservationDTO] = {
        let dates = ["2026-05-21", "2026-04-18"]
        return dates.enumerated().map { index, date in
            ReservationDTO(
                id: 200 + index,
                sourceSubmissionId: 500 + index,
                guestName: "Nina Shevchenko",
                email: "nina.shevchenko@example.com",
                phone: "7735551200",
                reservationDate: date,
                reservationTime: index == 0 ? "18:30:00" : "18:00:00",
                partySize: 2,
                guestNotes: index == 0 ? "Asked about vegetarian options." : nil,
                staffNotes: nil,
                status: index == 0 ? .confirmed : .completed,
                tableName: index == 0 ? "5" : "8",
                createdAt: "2026-04-\(12 + index) 10:15:00",
                updatedAt: nil,
                confirmedAt: nil,
                confirmationEmailSentAt: nil,
                reminderEmailSentAt: nil,
                supersededById: nil
            )
        }
    }()

    private static let mariaRegularDTOs: [ReservationDTO] = {
        let dates = [
            "2026-05-24",
            "2026-05-02",
            "2026-04-18",
            "2026-03-29",
            "2026-03-01",
            "2026-02-14",
            "2026-01-17"
        ]

        return dates.enumerated().map { index, date in
            ReservationDTO(
                id: 300 + index,
                sourceSubmissionId: 600 + index,
                guestName: "Maria Sokol",
                email: "maria.sokol@example.com",
                phone: "3125558800",
                reservationDate: date,
                reservationTime: index % 2 == 0 ? "19:00:00" : "19:30:00",
                partySize: index == 2 ? 6 : 4,
                guestNotes: index == 0 ? "Celebrating with family." : nil,
                staffNotes: index == 1 ? "Likes a quieter table near the window." : nil,
                status: index == 0 ? .confirmed : .completed,
                tableName: index % 2 == 0 ? "14" : "10",
                createdAt: "2026-01-\(10 + index) 12:00:00",
                updatedAt: nil,
                confirmedAt: nil,
                confirmationEmailSentAt: nil,
                reminderEmailSentAt: nil,
                supersededById: nil
            )
        }
    }()

    private static let petroFrequentRegularDTOs: [ReservationDTO] = {
        let dates = [
            "2026-05-23",
            "2026-05-09",
            "2026-04-26",
            "2026-04-05",
            "2026-03-22",
            "2026-03-08",
            "2026-02-22",
            "2026-02-08",
            "2026-01-25",
            "2026-01-11"
        ]

        return dates.enumerated().map { index, date in
            ReservationDTO(
                id: 400 + index,
                sourceSubmissionId: index == 0 ? nil : 700 + index,
                guestName: "Petro Hrytsenko",
                email: index == 0 ? "callin+manual-400@tryzubchicago.com" : "petro.h@example.com",
                phone: "8475554411",
                reservationDate: date,
                reservationTime: "20:00:00",
                partySize: index % 3 == 0 ? 8 : 5,
                guestNotes: index == 2 ? "Asked for extra time between courses." : nil,
                staffNotes: index == 0 ? "Call-in. Usually brings a larger group." : nil,
                status: index == 8 ? .noShow : (index == 1 ? .confirmed : .completed),
                tableName: index % 2 == 0 ? "16" : "18",
                createdAt: "2026-01-\(5 + index) 11:30:00",
                updatedAt: nil,
                confirmedAt: nil,
                confirmationEmailSentAt: nil,
                reminderEmailSentAt: nil,
                supersededById: nil
            )
        }
    }()

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

    @MainActor
    static var allRecords: [ReservationRecord] {
        let context = previewContainer.mainContext
        let descriptor = FetchDescriptor<ReservationRecord>(sortBy: [SortDescriptor(\.remoteID)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    static var guestInsightsRecord: ReservationRecord {
        allRecords.first { $0.remoteID == 72 } ?? sampleRecord
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
