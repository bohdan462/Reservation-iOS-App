//
//  HostTableIntelligenceSupport.swift
//  Tryzub Reservations
//
//  Pure table-fit and capacity helpers for Host Intelligence.
//

import Foundation

enum HostTableIntelligenceSupport {

  // MARK: - Capacity Summary

  static func buildTableCapacitySummary(
    tableConfigs: [RestaurantTableConfig]
  ) -> HostTableCapacitySummary {
    let active = tableConfigs.filter(\.isActive)
    let inactiveCount = tableConfigs.count - active.count
    let totalActiveCapacity = active.reduce(0) { $0 + $1.capacity }
    let largestSingle = active.map(\.capacity).max() ?? 0
    let largestCombination = largestCombinationCapacity(in: active)

    return HostTableCapacitySummary(
      activeTableCount: active.count,
      inactiveTableCount: inactiveCount,
      totalActiveCapacity: totalActiveCapacity,
      largestSingleTableCapacity: largestSingle,
      largestCombinationCapacity: largestCombination
    )
  }

  // MARK: - Fit Options

  static func findSingleTableFitOptions(
    reservation: ReservationRecord,
    tables: [RestaurantTableConfig]
  ) -> [HostTableFitOption] {
    let partySize = reservation.partySize
    return tables
      .filter { $0.isActive && $0.capacity >= partySize }
      .sorted { $0.capacity < $1.capacity }
      .map { table in
        HostTableFitOption(
          id: "single-\(reservation.remoteID)-\(table.id.uuidString)",
          reservationID: reservation.remoteID,
          guestName: reservation.guestName,
          partySize: partySize,
          tableNames: [table.name],
          tableIDs: [table.id],
          totalCapacity: table.capacity,
          isCombination: false,
          section: table.section.nilIfEmpty,
          fitQuality: fitQuality(partySize: partySize, capacity: table.capacity)
        )
      }
  }

  static func findCombinationTableFitOptions(
    reservation: ReservationRecord,
    tables: [RestaurantTableConfig]
  ) -> [HostTableFitOption] {
    let partySize = reservation.partySize
    let active = tables.filter(\.isActive)
    var options: [HostTableFitOption] = []

    for i in 0..<active.count {
      for j in (i + 1)..<active.count {
        let left = active[i]
        let right = active[j]
        guard canCombine(left, right) else { continue }

        let totalCapacity = left.capacity + right.capacity
        guard totalCapacity >= partySize else { continue }

        let names = [left.name, right.name].sorted()
        let ids = [left.id, right.id]
        options.append(
          HostTableFitOption(
            id: "combo-\(reservation.remoteID)-\(left.id.uuidString)-\(right.id.uuidString)",
            reservationID: reservation.remoteID,
            guestName: reservation.guestName,
            partySize: partySize,
            tableNames: names,
            tableIDs: ids,
            totalCapacity: totalCapacity,
            isCombination: true,
            section: preferredSection(left.section, right.section),
            fitQuality: fitQuality(partySize: partySize, capacity: totalCapacity)
          )
        )
      }
    }

    return options.sorted { $0.totalCapacity < $1.totalCapacity }
  }

  static func bestTableFitOptions(
    for reservation: ReservationRecord,
    tableConfigs: [RestaurantTableConfig],
    limit: Int = 3
  ) -> [HostTableFitOption] {
    guard !tableConfigs.isEmpty else { return [] }

    let singles = findSingleTableFitOptions(reservation: reservation, tables: tableConfigs)
    if !singles.isEmpty {
      return Array(singles.prefix(limit))
    }

    let combinations = findCombinationTableFitOptions(
      reservation: reservation,
      tables: tableConfigs
    )
    return Array(combinations.prefix(limit))
  }

  static func recommendedTableFits(
    reservations: [ReservationRecord],
    tableConfigs: [RestaurantTableConfig],
    limit: Int = 3
  ) -> [HostTableFitOption] {
    let noTable = reservations.filter { $0.isOpenWork && !$0.hasTableAssignment }
    var results: [HostTableFitOption] = []

    for reservation in noTable {
      let options = bestTableFitOptions(for: reservation, tableConfigs: tableConfigs, limit: 1)
      if let first = options.first {
        results.append(first)
      }
      if results.count >= limit { break }
    }

    return results
  }

  // MARK: - Assigned Table Parsing

  static func parseAssignedTableNames(_ assigned: String) -> [String] {
    assigned
      .split { "+,/".contains($0) }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  static func matchingTables(
    for names: [String],
    in tableConfigs: [RestaurantTableConfig]
  ) -> [RestaurantTableConfig]? {
    guard !names.isEmpty else { return nil }

    let active = tableConfigs.filter(\.isActive)
    var matched: [RestaurantTableConfig] = []

    for name in names {
      guard let table = active.first(where: {
        normalizeTableName($0.name) == normalizeTableName(name)
      }) else {
        return nil
      }
      matched.append(table)
    }

    return matched
  }

  static func normalizeTableName(_ value: String?) -> String {
    value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
  }

  static func displayTableNames(_ names: [String]) -> String {
    names.joined(separator: " + ")
  }

  // MARK: - Operational Advice Policy

  /// Table-capacity advice is review-only and reserved for parties that need real planning.
  static func shouldSurfaceNoTableFitAdvice(
    partySize: Int,
    largePartyThreshold: Int
  ) -> Bool {
    partySize >= largePartyThreshold
  }

  static func assignedTableCapacityMismatch(
    for reservation: ReservationRecord,
    tableConfigs: [RestaurantTableConfig]
  ) -> (tables: [RestaurantTableConfig], totalCapacity: Int)? {
    guard reservation.hasTableAssignment,
          let assignedName = reservation.assignedTableName else {
      return nil
    }

    let parsedNames = parseAssignedTableNames(assignedName)
    guard let matchedTables = matchingTables(for: parsedNames, in: tableConfigs) else {
      return nil
    }

    let totalCapacity = matchedTables.reduce(0) { $0 + $1.capacity }
    guard reservation.partySize > totalCapacity else { return nil }
    return (matchedTables, totalCapacity)
  }

  // MARK: - Private

  private static func largestCombinationCapacity(in tables: [RestaurantTableConfig]) -> Int {
    guard tables.count >= 2 else { return 0 }

    var maxCapacity = 0
    for i in 0..<tables.count {
      for j in (i + 1)..<tables.count {
        let left = tables[i]
        let right = tables[j]
        guard canCombine(left, right) else { continue }
        maxCapacity = max(maxCapacity, left.capacity + right.capacity)
      }
    }
    return maxCapacity
  }

  private static func canCombine(
    _ left: RestaurantTableConfig,
    _ right: RestaurantTableConfig
  ) -> Bool {
    left.combinableTableIDs.contains(right.id)
      || right.combinableTableIDs.contains(left.id)
  }

  private static func fitQuality(partySize: Int, capacity: Int) -> HostTableFitQuality {
    guard capacity >= partySize else { return .unavailable }
    if capacity == partySize { return .exact }
    if capacity == partySize + 1 { return .tight }
    if capacity <= partySize + 3 { return .comfortable }
    return .oversized
  }

  private static func preferredSection(_ left: String, _ right: String) -> String? {
    if !left.isEmpty && left == right { return left.nilIfEmpty }
    if !left.isEmpty { return left.nilIfEmpty }
    return right.nilIfEmpty
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
