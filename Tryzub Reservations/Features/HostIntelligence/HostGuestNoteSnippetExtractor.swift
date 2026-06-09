//
//  HostGuestNoteSnippetExtractor.swift
//  Tryzub Reservations
//
//  Deterministic short note snippets for Host Intelligence copy.
//

import Foundation

enum HostGuestNoteSnippetExtractor {
  private static let maxSnippetLength = 60

  static func seatingPreferenceSnippet(from notes: String) -> String? {
    let text = normalizedNotes(notes)
    guard !text.isEmpty else { return nil }

    let patterns: [(String, String)] = [
      ("booth by the wall", "a booth by the wall"),
      ("booth", "a booth"),
      ("by the wall", "a table by the wall"),
      ("quiet table", "a quiet table"),
      ("quiet area", "a quiet area"),
      ("patio", "patio seating"),
      ("outdoor", "outdoor seating"),
      ("window", "a window table"),
      ("corner", "a corner table"),
      ("bar seating", "bar seating"),
      ("high chair", "a high chair"),
      ("highchair", "a high chair"),
      ("wheelchair accessible", "wheelchair-accessible seating"),
      ("wheelchair", "wheelchair-accessible seating"),
      ("accessible seating", "accessible seating")
    ]

    for (needle, snippet) in patterns where text.contains(needle) {
      return cap(snippet)
    }

    return extractAround(keywords: ["prefer", "preference", "request", "would like"], in: text)
  }

  static func accessibilitySnippet(from notes: String) -> String? {
    let text = normalizedNotes(notes)
    guard !text.isEmpty else { return nil }

    if text.contains("wheelchair") {
      return cap("wheelchair-accessible seating")
    }
    if text.contains("accessible") {
      return cap("accessibility seating needs")
    }
    if text.contains("high chair") || text.contains("highchair") {
      return cap("a high chair")
    }
    return nil
  }

  static func allergySnippet(from notes: String) -> String? {
    let text = normalizedNotes(notes)
    guard !text.isEmpty else { return nil }

    let allergens = [
      "shellfish", "shrimp", "crab", "lobster", "peanut", "tree nut",
      "gluten", "dairy", "celiac", "sesame", "soy", "egg", "fish"
    ]
    if let match = allergens.first(where: { text.contains($0) }) {
      return cap("\(match) allergy")
    }
    if text.contains("allergy") || text.contains("allergic") {
      return cap("an allergy note")
    }
    return nil
  }

  static func specialOccasionSnippet(from notes: String) -> String? {
    let text = normalizedNotes(notes)
    guard !text.isEmpty else { return nil }

    let occasions = ["birthday", "anniversary", "engagement", "graduation", "celebration"]
    if let match = occasions.first(where: { text.contains($0) }) {
      return cap("\(match) note")
    }
    if text.contains("special occasion") {
      return cap("special occasion note")
    }
    return nil
  }

  // MARK: - Helpers

  private static func normalizedNotes(_ notes: String) -> String {
    notes
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "  ", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  private static func extractAround(keywords: [String], in text: String) -> String? {
    for keyword in keywords where text.contains(keyword) {
      guard let range = text.range(of: keyword) else { continue }
      let tail = text[range.upperBound...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: ":,-."))
      guard !tail.isEmpty else { continue }
      let words = tail.split(separator: " ").prefix(6).joined(separator: " ")
      guard !words.isEmpty else { continue }
      return cap(words)
    }
    return nil
  }

  private static func cap(_ snippet: String) -> String {
    let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    if trimmed.count <= maxSnippetLength {
      return trimmed
    }
    return String(trimmed.prefix(maxSnippetLength)).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
