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
        let existingRecords = try context.fetch(FetchDescriptor<ReservationRecord>())
        upsert(reservations, into: existingRecords)
        try context.save()
        let afterRecords = try context.fetch(FetchDescriptor<ReservationRecord>())
        ReservationSyncDiagnostics.repositoryUpsert(
            scope: "upsert",
            input: reservations,
            localRecords: afterRecords
        )
    }

    // Intent: Successful date-scoped GET is server truth for that date in normal visible lists.
    // Missing local rows are deleted so hidden/moved/status-changed records cannot linger.
    func replaceDateScope(date: String, with reservations: [ReservationDTO], includeHidden: Bool) throws {
        let beforeRecords = try context.fetch(FetchDescriptor<ReservationRecord>())
        let beforeCount = beforeRecords.filter { $0.reservationDate == date }.count
        let returnedIDs = Set(reservations.map(\.id))
        var removedIDs: [Int] = []

        for record in beforeRecords
            where record.reservationDate == date
                && !returnedIDs.contains(record.remoteID)
                && (includeHidden || !record.isHidden) {
            removedIDs.append(record.remoteID)
            context.delete(record)
        }

        let remainingRecords = beforeRecords.filter { !removedIDs.contains($0.remoteID) }
        upsert(reservations, into: remainingRecords)
        try context.save()

        let afterRecords = try context.fetch(FetchDescriptor<ReservationRecord>())
        let afterCount = afterRecords.filter { $0.reservationDate == date }.count
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
        let beforeRecords = try context.fetch(FetchDescriptor<ReservationRecord>())
        let beforeCount = beforeRecords.filter { $0.reservationDate >= from && $0.reservationDate <= to }.count
        let returnedIDs = Set(reservations.map(\.id))
        var removedIDs: [Int] = []

        for record in beforeRecords
            where record.reservationDate >= from
                && record.reservationDate <= to
                && !returnedIDs.contains(record.remoteID)
                && (includeHidden || !record.isHidden) {
            removedIDs.append(record.remoteID)
            context.delete(record)
        }

        let remainingRecords = beforeRecords.filter { !removedIDs.contains($0.remoteID) }
        upsert(reservations, into: remainingRecords)
        try context.save()

        let afterRecords = try context.fetch(FetchDescriptor<ReservationRecord>())
        let afterCount = afterRecords.filter { $0.reservationDate >= from && $0.reservationDate <= to }.count
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
        let beforeRecords = try context.fetch(FetchDescriptor<ReservationRecord>())
        let beforeCount = beforeRecords.filter { !$0.isHidden && ($0.statusValue == .new || $0.statusValue == .needsReview) }.count

        upsert(reservations, into: beforeRecords)
        try context.save()

        let afterRecords = try context.fetch(FetchDescriptor<ReservationRecord>())
        let afterCount = afterRecords.filter { !$0.isHidden && ($0.statusValue == .new || $0.statusValue == .needsReview) }.count
        ReservationSyncDiagnostics.cacheWrite(
            scope: "review=new,needs_review(upsert-only)",
            input: reservations,
            beforeCount: beforeCount,
            afterCount: afterCount,
            removedIDs: []
        )
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
        localRecords: [ReservationRecord]
    ) {
        guard isEnabled else { return }

        let dates = Set(input.map(\.reservationDate)).sorted()
        let scopedLocalCount = localRecords.filter { dates.contains($0.reservationDate) }.count
        emit("[CACHE] scope=\(scope) server=\(input.count) before=- upserted=\(input.count) removed=0 after=\(scopedLocalCount) firstIDs=\(input.prefix(10).map(\.id))")
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
        guard isEnabled else { return }

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
