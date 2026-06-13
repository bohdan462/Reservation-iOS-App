//
//  HostAttentionPresentation.swift
//  Tryzub Reservations
//
//  Deterministic staff-facing presentation model for the Host attention card.
//

import Foundation

struct HostAttentionPresentationItem: Identifiable, Equatable {
  let id: String
  let priority: ManagerAttentionPriority
  let title: String
  let detail: String?
  let actionTitle: String
  let destinationHint: ManagerAttentionDestinationHint
  let relatedReservationIDs: [Int]
  let sourceAction: HostSuggestedAction?
}

struct HostAttentionContextItem: Identifiable, Equatable {
  let id: String
  let title: String
  let detail: String?
  let relatedReservationIDs: [Int]
}

struct HostAttentionPresentation: Equatable {
  let headline: String
  let summary: String?
  let primaryItems: [HostAttentionPresentationItem]
  let secondaryContext: [HostAttentionContextItem]
  let primaryActions: [HostSuggestedAction]
  let suppressedItems: [String]
  let modelEligibleReason: String?
  let floorSourceLabel: String
  let themes: [String]

  static let empty = HostAttentionPresentation(
    headline: "Nothing needs attention right now.",
    summary: nil,
    primaryItems: [],
    secondaryContext: [],
    primaryActions: [],
    suppressedItems: [],
    modelEligibleReason: nil,
    floorSourceLabel: HostFloorTableSource.pendingBackend.traceLabel,
    themes: []
  )

  var hasVisibleContent: Bool {
    !primaryItems.isEmpty || !secondaryContext.isEmpty || !(summary ?? "").isEmpty
  }

  var groupedFacts: [String] {
    var facts: [String] = []
    let headline = headline.trimmingCharacters(in: .whitespacesAndNewlines)
    if !headline.isEmpty {
      facts.append(headline)
    }
    if let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
       !summary.isEmpty {
      facts.append(summary)
    }
    facts.append(contentsOf: primaryItems.map { item in
      if let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
         !detail.isEmpty {
        return "\(item.title): \(detail)"
      }
      return item.title
    })
    facts.append(contentsOf: secondaryContext.map { item in
      if let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
         !detail.isEmpty {
        return "\(item.title): \(detail)"
      }
      return item.title
    })
    return facts.deduplicatedStaffLines()
  }

  var presentationFingerprint: String {
    let parts = [
      floorSourceLabel,
      headline,
      summary ?? "",
      primaryItems.map { "\($0.id):\($0.title):\($0.detail ?? "")" }.joined(separator: ";"),
      secondaryContext.map { "\($0.id):\($0.title):\($0.detail ?? "")" }.joined(separator: ";"),
      primaryActions.map { "\($0.id):\($0.title)" }.joined(separator: ";"),
      suppressedItems.joined(separator: ";"),
      modelEligibleReason ?? "notEligible",
      themes.joined(separator: ",")
    ]
    return HostAttentionStableDigest.hexDigest(parts.joined(separator: "|"))
  }

  var primaryActionsFingerprint: String {
    HostAttentionStableDigest.hexDigest(
      primaryActions
        .map { "\($0.id):\($0.kind.rawValue):\($0.title):\($0.reason)" }
        .joined(separator: "|")
    )
  }
}

enum HostAttentionStableDigest {
  static func hexDigest(_ text: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in text.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16)
  }
}

private extension Array where Element == String {
  func deduplicatedStaffLines() -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for line in self {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      let key = trimmed
        .lowercased()
        .replacingOccurrences(of: #"[^\w\s]"#, with: "", options: .regularExpression)
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      result.append(trimmed)
    }
    return result
  }
}
