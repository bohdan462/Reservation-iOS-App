//
//  ReservationHistoryPrefetcher.swift
//  Tryzub Reservations
//
//  Background-only reservation history cache enrichment for guest intelligence.
//

import Foundation
import SwiftData

enum ReservationHistoryPrefetcher {

  private static let completedAtKey = "tryzub.historyPrefetch.completedAt"
  private static let freshnessInterval: TimeInterval = 12 * 60 * 60
  /// Safety cap; prefetch stops earlier when a window returns zero rows.
  private static let maxHistoryDaysAgo = 3_650
  private static let extendedWindowChunkDays = 180

  /// Newest date windows first; each window walks backward in time (upsert-only).
  static func windows() -> [(from: String, to: String)] {
    let calendar = Calendar.current
    let today = Date()

    func dateKey(daysAgo: Int) -> String {
      let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
      return date.reservationDateString()
    }

    // Active window already covers yesterday forward; fill older history backward.
    var windows: [(from: String, to: String)] = [
      (dateKey(daysAgo: 30), dateKey(daysAgo: 2)),
      (dateKey(daysAgo: 90), dateKey(daysAgo: 31)),
      (dateKey(daysAgo: 180), dateKey(daysAgo: 91)),
      (dateKey(daysAgo: 365), dateKey(daysAgo: 181)),
    ]

    var chunkEndDaysAgo = 366
    while chunkEndDaysAgo <= maxHistoryDaysAgo {
      let chunkStartDaysAgo = min(chunkEndDaysAgo + extendedWindowChunkDays - 1, maxHistoryDaysAgo)
      windows.append((dateKey(daysAgo: chunkStartDaysAgo), dateKey(daysAgo: chunkEndDaysAgo)))
      chunkEndDaysAgo = chunkStartDaysAgo + 1
    }

    return windows
  }

  static func shouldRun(force: Bool = false) -> Bool {
    if force { return true }
    guard let completedAt = UserDefaults.standard.object(forKey: completedAtKey) as? Date else {
      return true
    }
    return Date().timeIntervalSince(completedAt) >= freshnessInterval
  }

  static func markCompleted() {
    UserDefaults.standard.set(Date(), forKey: completedAtKey)
  }

  /// Returns total rows written when prefetch runs; `nil` when skipped as fresh.
  @MainActor
  @discardableResult
  static func prefetchIfNeeded(
    apiClient: any ReservationsAPIClientProtocol,
    context: ModelContext,
    force: Bool = false
  ) async -> Int? {
    guard shouldRun(force: force) else {
      ReservationSyncDiagnostics.historyPrefetchSkipped(reason: "fresh")
      return nil
    }

    ReservationSyncDiagnostics.historyPrefetchStarted()

    let repository = ReservationRepository(context: context)
    let service = ReservationSyncService(client: apiClient, repository: repository)
    let allWindows = windows()
    var totalWritten = 0

    for (index, window) in allWindows.enumerated() {
      guard !Task.isCancelled else {
        ReservationSyncDiagnostics.historyPrefetchCancelled()
        return nil
      }

      ReservationSyncDiagnostics.historyPrefetchWindow(
        index: index + 1,
        total: allWindows.count,
        from: window.from,
        to: window.to
      )

      do {
        let result = try await service.prefetchHistoryWindow(
          from: window.from,
          to: window.to,
          reason: .scheduleWindow
        )
        totalWritten += result.rowsWritten ?? 0

        if result.rowCount == 0 {
          ReservationSyncDiagnostics.historyPrefetchReachedEnd(oldestFrom: window.from)
          break
        }
      } catch {
        if error.isCancellationLike {
          ReservationSyncDiagnostics.historyPrefetchCancelled()
          return nil
        }
        ReservationSyncDiagnostics.historyPrefetchFailed(
          window: "\(window.from)...\(window.to)",
          message: error.localizedDescription
        )
        return nil
      }

      await Task.yield()
    }

    markCompleted()
    ReservationSyncDiagnostics.historyPrefetchFinished(totalRows: totalWritten)
    return totalWritten
  }
}
