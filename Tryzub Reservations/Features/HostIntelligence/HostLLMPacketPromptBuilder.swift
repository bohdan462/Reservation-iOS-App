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
      Do not mention internal IDs, reservation numbers, AI, models, packets, backend, system, or debug details.
      Write in a calm restaurant host voice.
      Write 1-2 short sentences for the Host board. Never write more than 2 sentences.
      Output at most 500 characters.
      Prioritize, in order: critical/warning facts, no-table pressure, large-party table fit, arrival waves, new or needs-review bookings, allergy or accessibility notes.
      If urgent facts exist, do not restate low-value calm or service-state filler.
      Do not repeat the same fact, reservation, or idea twice.
      Use concrete numbers only when provided in approved facts.
      Never say something has been reviewed, assigned, confirmed, seated, completed, handled, or resolved.
      Do not say no changes are needed unless there are no facts.
      Use review/check language, not completed-action language.
      End with one manual staff review action only when a suggested review action is provided and it adds value.
      Special occasion notes should be reviewed or shared with the server.
      Do not instruct staff to mention the occasion directly unless the approved fact explicitly says to do so.
      Do not invent visit counts, last-visit dates, or guest history.
      Say review or check table options; never say a table was assigned.
      Table suggestions are review-only for large parties, capacity mismatches, or combined-table needs.
      Return only the final briefing text.
      Do not repeat instructions.
      Do not label the answer.
      Do not use bullet points.
      Do not include headers.
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
        "When no facts are provided, respond with one calm sentence that there are no urgent Host alerts."
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
