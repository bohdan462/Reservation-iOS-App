//
//  HostLLMPacketPromptBuilder.swift
//  Tryzub Reservations
//
//  Builds presentation-only prompts from approved HostLLMPacket data.
//  Never includes raw reservation records or unsanitized notes.
//

import Foundation

enum HostLLMPacketPromptBuilder {

  static func buildPrompt(from packet: HostLLMPacket) -> String {
    var sections: [String] = []

    sections.append(
      """
      You are rewriting an approved restaurant host briefing for staff display.
      Use only the facts below. Do not invent guests, tables, allergies, times, or counts.
      Do not say any action was completed. Do not make booking decisions.
      Do not mention internal IDs or reservation numbers.
      Write in a calm host voice.
      Write 2-3 short sentences unless service state is critical.
      Output at most 4 short sentences and at most 500 characters.
      If the facts are sparse, keep the briefing brief and neutral.
      Do not repeat these instructions.
      Start directly with the briefing prose.
      """
    )

    sections.append("Context:")
    let generatedAt = packet.generatedAtDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    if !generatedAt.isEmpty {
      sections.append("- Generated at: \(generatedAt)")
    }
    sections.append("- Service state: \(packet.serviceState.rawValue)")
    sections.append("- Pressure score: \(Int(packet.pressureScore.rounded()))")

    if packet.topFacts.isEmpty {
      sections.append("Approved facts: none")
      sections.append(
        "When no facts are provided, respond with a single calm sentence that service looks stable."
      )
    } else {
      sections.append("Approved facts:")
      for (index, fact) in packet.topFacts.enumerated() {
        var line = "\(index + 1). [\(fact.severity.rawValue)/\(fact.category.rawValue)] \(fact.title)"
        let detail = fact.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
          line += " — \(detail)"
        }
        if let action = fact.suggestedAction?.trimmingCharacters(in: .whitespacesAndNewlines),
           !action.isEmpty {
          line += " (suggested review: \(action))"
        }
        sections.append(line)
      }
    }

    if !packet.forbiddenBehaviors.isEmpty {
      sections.append("Forbidden:")
      packet.forbiddenBehaviors.forEach { sections.append("- \($0)") }
    }

    if !packet.writingRules.isEmpty {
      sections.append("Writing rules:")
      packet.writingRules.forEach { sections.append("- \($0)") }
    }

    sections.append("Write the host briefing now:")
    return sections.joined(separator: "\n")
  }

  static func buildDebugPromptPreview(from packet: HostLLMPacket) -> String {
    buildPrompt(from: packet)
  }
}
