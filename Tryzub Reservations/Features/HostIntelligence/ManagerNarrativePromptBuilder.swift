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
      You are writing a short manager briefing for restaurant staff.
      Use simple restaurant staff language.
      Write so a busy host understands in five seconds.
      Do not use technical words: backend, cache, sync, API, endpoint, packet, model, validation, diagnostics, confidence, capacity ratio.
      Use only the provided facts and actions.
      Do not invent guests, tables, times, counts, allergies, notes, or actions.
      Do not say anything was confirmed, sent, assigned, cancelled, seated, or changed.
      Do not mention AI, models, or local model.
      Use at most 3 short lines with these exact labels:
      HEADLINE:
      WHY:
      CHECK:
      HEADLINE = one sentence for what matters right now.
      WHY = one sentence for why it matters, or write NONE if not needed.
      CHECK = one sentence for what staff can check next using an available action, or write NONE if not needed.
      Do not use bullet points.
      Do not add extra lines.
      Do not repeat the same idea in multiple lines.
      Use concrete numbers only when provided in approved facts.
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
        "When no facts are provided, HEADLINE should say nothing needs attention right now. WHY and CHECK should be NONE."
      )
    } else {
      sections.append("Approved facts:")
      for (index, fact) in packet.headlineFacts.enumerated() {
        var line = "\(index + 1). [\(fact.priority)] \(fact.title)"
        if let detail = fact.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
          line += " — \(detail)"
        }
        sections.append(line)
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
