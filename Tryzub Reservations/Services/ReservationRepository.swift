//
//  ReservationRepository.swift
//  Tryzub Reservations
//

import Foundation
import OSLog
import SwiftData

// MARK: - Repository Contract

@MainActor
protocol ReservationRepositoryProtocol {
    func latestLocalSyncDate() throws -> Date?
    func upsert(_ reservation: ReservationDTO) throws
    func upsert(_ reservations: [ReservationDTO]) throws
    func replaceDateScope(date: String, with reservations: [ReservationDTO], includeHidden: Bool) throws
    func replaceDateWindow(from: String, to: String, with reservations: [ReservationDTO], includeHidden: Bool) throws
    func replaceReviewQueue(with reservations: [ReservationDTO]) throws
    func deleteReservation(remoteID: Int) throws
}

@MainActor
final class ReservationRepository: ReservationRepositoryProtocol {
    // MARK: - Dependencies

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Cache Metadata

    // Intent: Lets startup show when any cached server reservation was last synced.
    // Network: None; SwiftData cache read only.
    func latestLocalSyncDate() throws -> Date? {
        var descriptor = FetchDescriptor<ReservationRecord>(
            sortBy: [SortDescriptor(\ReservationRecord.lastSyncedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.lastSyncedAt
    }

    // MARK: - Server DTO Upsert

    func upsert(_ reservation: ReservationDTO) throws {
        try upsert([reservation])
    }

    // Intent: Writes server DTOs into SwiftData cache keyed by remote reservation ID.
    // Duplicate note: Records with the same server id update one local ReservationRecord.
    func upsert(_ reservations: [ReservationDTO]) throws {
        guard !reservations.isEmpty else { return }

        let existingRecords = try records(remoteIDs: reservations.map(\.id))
        upsert(reservations, into: existingRecords)
        try context.save()
        ReservationSyncDiagnostics.repositoryUpsert(
            scope: "upsert",
            input: reservations,
            localRecordCount: existingRecords.count + max(reservations.count - existingRecords.count, 0)
        )
    }

    // Intent: Reads only the cached rows needed for schedule-all/detail lookups.
    func records(remoteIDs: [Int]) throws -> [ReservationRecord] {
        let uniqueIDs = Array(Set(remoteIDs))
        guard !uniqueIDs.isEmpty else { return [] }

        let descriptor = FetchDescriptor<ReservationRecord>(
            predicate: #Predicate { record in
                uniqueIDs.contains(record.remoteID)
            }
        )
        return try context.fetch(descriptor)
    }

    // Intent: Successful date-scoped GET is server truth for that date in normal visible lists.
    // Missing local rows are deleted so hidden/moved/status-changed records cannot linger.
    func replaceDateScope(date: String, with reservations: [ReservationDTO], includeHidden: Bool) throws {
        let scopedDate = date
        let dateDescriptor = FetchDescriptor<ReservationRecord>(
            predicate: #Predicate<ReservationRecord> { record in
                record.reservationDate == scopedDate
            }
        )
        let beforeRecords = try context.fetch(dateDescriptor)
        let beforeCount = beforeRecords.count
        let returnedIDs = Set(reservations.map(\.id))
        var removedIDs: [Int] = []

        for record in beforeRecords
            where !returnedIDs.contains(record.remoteID)
                && (includeHidden || !record.isHidden) {
            removedIDs.append(record.remoteID)
            context.delete(record)
        }

        let existingRecords = try records(remoteIDs: reservations.map(\.id))
        upsert(reservations, into: existingRecords)
        try context.save()

        let afterRecords = try context.fetch(dateDescriptor)
        let afterCount = afterRecords.count
        ReservationSyncDiagnostics.cacheWrite(
            scope: "date=\(date)",
            input: reservations,
            beforeCount: beforeCount,
            afterCount: afterCount,
            removedIDs: removedIDs
        )
    }

    // Intent: Successful schedule-window GET is server truth for only that date window.
    func replaceDateWindow(from: String, to: String, with reservations: [ReservationDTO], includeHidden: Bool) throws {
        let windowFrom = from
        let windowTo = to
        let windowDescriptor = FetchDescriptor<ReservationRecord>(
            predicate: #Predicate<ReservationRecord> { record in
                record.reservationDate >= windowFrom && record.reservationDate <= windowTo
            }
        )
        let beforeRecords = try context.fetch(windowDescriptor)
        let beforeCount = beforeRecords.count
        let returnedIDs = Set(reservations.map(\.id))
        var removedIDs: [Int] = []

        for record in beforeRecords
            where !returnedIDs.contains(record.remoteID)
                && (includeHidden || !record.isHidden) {
            removedIDs.append(record.remoteID)
            context.delete(record)
        }

        let existingRecords = try records(remoteIDs: reservations.map(\.id))
        upsert(reservations, into: existingRecords)
        try context.save()

        let afterRecords = try context.fetch(windowDescriptor)
        let afterCount = afterRecords.count
        ReservationSyncDiagnostics.cacheWrite(
            scope: "window=\(from)...\(to)",
            input: reservations,
            beforeCount: beforeCount,
            afterCount: afterCount,
            removedIDs: removedIDs
        )
    }

    // Intent: Successful review GETs refresh rows still in new/needs_review.
    // Missing rows are not deleted; broader date/window sync or mutation responses own status changes.
    func replaceReviewQueue(with reservations: [ReservationDTO]) throws {
        let statusNew = ReservationStatus.new.rawValue
        let statusNeedsReview = ReservationStatus.needsReview.rawValue
        let reviewDescriptor = FetchDescriptor<ReservationRecord>(
            predicate: #Predicate<ReservationRecord> { record in
                !record.isHidden && (record.status == statusNew || record.status == statusNeedsReview)
            }
        )
        let beforeRecords = try context.fetch(reviewDescriptor)
        let beforeCount = beforeRecords.count

        let existingRecords = try records(remoteIDs: reservations.map(\.id))
        upsert(reservations, into: existingRecords)
        try context.save()

        let afterRecords = try context.fetch(reviewDescriptor)
        let afterCount = afterRecords.count
        ReservationSyncDiagnostics.cacheWrite(
            scope: "review=new,needs_review(upsert-only)",
            input: reservations,
            beforeCount: beforeCount,
            afterCount: afterCount,
            removedIDs: []
        )
    }

    // Intent: Removes a row from the local cache after an admin/developer hard-delete succeeds on the server.
    func deleteReservation(remoteID: Int) throws {
        let descriptor = FetchDescriptor<ReservationRecord>(
            predicate: #Predicate { record in
                record.remoteID == remoteID
            }
        )
        let records = try context.fetch(descriptor)
        for record in records {
            context.delete(record)
        }
        try context.save()
    }

    private func upsert(_ reservations: [ReservationDTO], into existingRecords: [ReservationRecord]) {
        var existingByRemoteID: [Int: ReservationRecord] = [:]
        for record in existingRecords {
            existingByRemoteID[record.remoteID] = record
        }

        for dto in reservations {
            if let existing = existingByRemoteID[dto.id] {
                existing.update(from: dto)
            } else {
                context.insert(ReservationRecord(from: dto))
            }
        }
    }
}

enum ReservationSyncDiagnostics {
    static var logsHomeVisibleRows = false

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "SyncDiagnostics"
    )

    static func apiListResponse(
        reason: ReservationAPIRequestReason,
        total: Int?,
        reservations: [ReservationDTO],
        label: String
    ) {
        guard isEnabled else { return }

        let statusCounts = Dictionary(grouping: reservations, by: { $0.status.rawValue })
            .mapValues(\.count)
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        let hiddenCount = reservations.filter { $0.isHidden == true }.count
        emit("[API DATA] reason=\(reason.rawValue) label=\(label) total=\(total.map(String.init) ?? "-") decoded=\(reservations.count) firstIDs=\(reservations.prefix(10).map(\.id)) statusCounts=[\(statusCounts)] hiddenCount=\(hiddenCount)")
    }

    static func repositoryUpsert(
        scope: String,
        input: [ReservationDTO],
        localRecordCount: Int
    ) {
        guard isEnabled else { return }

        emit("[CACHE] scope=\(scope) server=\(input.count) before=- upserted=\(input.count) removed=0 localMatchedOrInserted=\(localRecordCount) firstIDs=\(input.prefix(10).map(\.id))")
    }

    static func cacheWrite(
        scope: String,
        input: [ReservationDTO],
        beforeCount: Int,
        afterCount: Int,
        removedIDs: [Int]
    ) {
        guard isEnabled else { return }

        emit("[CACHE] scope=\(scope) server=\(input.count) before=\(beforeCount) upserted=\(input.count) removed=\(removedIDs.count) after=\(afterCount) firstRemovedIDs=\(removedIDs.prefix(10))")
    }

    static func homeVisible(
        selectedDate: String,
        allLocalForDateCount: Int,
        hiddenExcludedCount: Int,
        statusExcludedCount: Int,
        finalVisibleCount: Int,
        ids: [Int],
        excludedStatusCounts: [String: Int]
    ) {
        guard isEnabled, logsHomeVisibleRows else { return }

        emit("[SYNC] home visible selectedDate=\(selectedDate) localForDate=\(allLocalForDateCount) hiddenExcluded=\(hiddenExcludedCount) statusExcluded=\(statusExcludedCount) finalVisible=\(finalVisibleCount) firstIDs=\(ids.prefix(10))")
        emit("[SYNC] home excluded statuses=[completed:\(excludedStatusCounts["completed"] ?? 0), cancelled:\(excludedStatusCounts["cancelled"] ?? 0), no_show:\(excludedStatusCounts["no_show"] ?? 0), hidden:\(hiddenExcludedCount)]")
    }

    private static func emit(_ message: String) {
      
        print(message)
    }

    private static var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
