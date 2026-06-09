//
//  HostTableCapacityTextParser.swift
//  Tryzub Reservations
//
//  Parses local table name + seat count text for Host Intelligence.
//

import Foundation

struct HostTableCapacityParseResult: Equatable {
  let tables: [RestaurantTableConfig]
  let invalidLines: [String]
  let tableNames: [String]

  var invalidLineCount: Int { invalidLines.count }
}

enum HostTableCapacityTextParser {

  static let storageKey = "tryzub.hostIntelligence.tableCapacityText"

  static func parse(_ rawValue: String) -> HostTableCapacityParseResult {
    var tables: [RestaurantTableConfig] = []
    var invalidLines: [String] = []
    var names: [String] = []
    var sortOrder = 0

    for line in lines(from: rawValue) {
      if let parsed = parseLine(line) {
        tables.append(
          RestaurantTableConfig(
            name: parsed.name,
            capacity: parsed.capacity,
            sortOrder: sortOrder
          )
        )
        names.append(parsed.name)
        sortOrder += 1
      } else {
        invalidLines.append(line)
      }
    }

    return HostTableCapacityParseResult(
      tables: tables,
      invalidLines: invalidLines,
      tableNames: names.uniquedPreservingOrder()
    )
  }

  static func formattedExample() -> String {
    "A1: 4\nA2: 4\nA3: 2\nPatio: 6"
  }

  // MARK: - Private

  private static func lines(from rawValue: String) -> [String] {
    rawValue
      .components(separatedBy: .newlines)
      .flatMap { line in
        line.split(whereSeparator: { $0 == ";" }).map(String.init)
      }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func parseLine(_ line: String) -> (name: String, capacity: Int)? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let separators = CharacterSet(charactersIn: ":=-,")
    let parts = trimmed
      .split(whereSeparator: { separators.contains($0.unicodeScalars.first!) })
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    if parts.count == 2,
       let capacity = Int(parts[1]),
       capacity > 0,
       capacity <= 30,
       !parts[0].isEmpty {
      return (parts[0], capacity)
    }

    let spaceParts = trimmed.split(separator: " ").map(String.init)
    if spaceParts.count == 2,
       let capacity = Int(spaceParts[1]),
       capacity > 0,
       capacity <= 30 {
      let name = spaceParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { return nil }
      return (name, capacity)
    }

    return nil
  }
}
