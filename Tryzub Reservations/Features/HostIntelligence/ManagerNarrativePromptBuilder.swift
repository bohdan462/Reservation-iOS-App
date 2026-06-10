//
//  ManagerNarrativePromptBuilder.swift
//  Tryzub Reservations
//
//  Builds staff-facing narrative prompts from approved ManagerNarrativePacket data.
//

import Foundation

enum ManagerNarrativePromptBuilder {

  static func buildPrompt(from packet: ManagerNarrativePacket) -> String {
    var sections: [String] = []

    sections.append(
      """
      You are writing a short manager briefing for restaurant staff on the Host board.
      Write natural host or manager language in at most 2 short sentences.
      Lead with the most urgent reservation or issue first.
      Connect related operational facts only when useful for staff decisions.
      Use only the provided facts and actions.
      Do not invent guests, tables, times, counts, allergies, notes, or actions.
      Do not say anything was confirmed, sent, seated, assigned, cancelled, or changed.
      Do not mention AI, models, or validation.
      Do not use bullet points, numbering, or category tags like [critical/overdue].
      Do not use labels like HEADLINE, WHY, or CHECK.
      Output plain staff-facing prose only.
      """
    )

    sections.append("Surface: \(packet.surface.rawValue)")
    if !packet.generatedAtDescription.isEmpty {
      sections.append("Generated at: \(packet.generatedAtDescription)")
    }
    sections.append("Service state: \(packet.serviceState)")

    if packet.headlineFacts.isEmpty {
      sections.append("Approved facts: none")
      sections.append(
        "When no facts are provided, say nothing needs attention right now."
      )
    } else {
      sections.append("Approved facts:")
      for fact in packet.headlineFacts {
        var line = fact.title
        if let detail = fact.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
          line += ". \(detail)"
        }
        sections.append("- \(line)")
      }
    }

    if packet.availableActions.isEmpty {
      sections.append("Available staff checks: none")
    } else {
      sections.append("Available staff checks:")
      for action in packet.availableActions {
        sections.append("- \(action.title) (\(action.destinationHint))")
      }
    }

    if !packet.writingRules.isEmpty {
      sections.append("Writing rules:")
      packet.writingRules.forEach { sections.append("- \($0)") }
    }

    sections.append("Write the manager narrative now:")
    return sections.joined(separator: "\n")
  }

  #if DEBUG
  static func buildDebugPromptPreview(from packet: ManagerNarrativePacket) -> String {
    buildPrompt(from: packet)
  }
  #endif
}
