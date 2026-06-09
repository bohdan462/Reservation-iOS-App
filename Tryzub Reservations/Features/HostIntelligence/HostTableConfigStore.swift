//
//  HostTableConfigStore.swift
//  Tryzub Reservations
//
//  UserDefaults-backed local restaurant table inventory.
//

import Foundation

@MainActor
final class HostTableConfigStore: ObservableObject {

  @Published private(set) var tables: [RestaurantTableConfig] = []

  private let defaultsKey = "tryzub.hostIntelligence.tableConfig.v1"

  init() {
    load()
  }

  func save(_ tables: [RestaurantTableConfig]) {
    self.tables = tables
    persist()
  }

  func addDefaultTable() {
    let nextOrder = (tables.map(\.sortOrder).max() ?? -1) + 1
    let nextIndex = tables.count + 1
    let table = RestaurantTableConfig(
      name: "Table \(nextIndex)",
      capacity: 4,
      sortOrder: nextOrder
    )
    tables.append(table)
    persist()
  }

  func update(_ table: RestaurantTableConfig) {
    guard let index = tables.firstIndex(where: { $0.id == table.id }) else { return }
    tables[index] = table
    persist()
  }

  func delete(_ table: RestaurantTableConfig) {
    tables.removeAll { $0.id == table.id }
    tables = tables.map { existing in
      var updated = existing
      updated.combinableTableIDs.removeAll { $0 == table.id }
      return updated
    }
    persist()
  }

  func reset() {
    tables = []
    persist()
  }

  func reload() {
    load()
  }

  var activeTables: [RestaurantTableConfig] {
    sortedTables.filter(\.isActive)
  }

  var totalActiveCapacity: Int {
    activeTables.reduce(0) { $0 + $1.capacity }
  }

  var sortedTables: [RestaurantTableConfig] {
    tables.sorted { lhs, rhs in
      if lhs.sortOrder != rhs.sortOrder {
        return lhs.sortOrder < rhs.sortOrder
      }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
      tables = []
      return
    }

    do {
      tables = try JSONDecoder().decode([RestaurantTableConfig].self, from: data)
    } catch {
      tables = []
    }
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(tables) else { return }
    UserDefaults.standard.set(data, forKey: defaultsKey)
  }
}
