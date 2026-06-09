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
      Write 1-3 short sentences. Never write more than 4 sentences.
      Output at most 4 short sentences and at most 500 characters.
      If there are no urgent facts, keep it short.
      Never say something has been reviewed, assigned, confirmed, seated, completed, handled, or resolved.
      Do not say no changes are needed unless there are no facts.
      Use review/check language, not completed-action language.
      Write as a reminder, not as a report of completed work.
      Special occasion notes should be reviewed or shared with the server.
      Do not instruct staff to mention the occasion directly unless the approved fact explicitly says to do so.
      Do not invent visit counts, last-visit dates, or guest history.
      Use returning-guest context only when provided in approved facts or evidence.
      Use table capacity only if it is provided in the approved facts.
      Do not invent table numbers, table capacities, or table assignments.
      Say review or check table options; never say a table was assigned.
      Do not recommend assigning a specific table for small parties.
      Table suggestions are review-only and should focus on large parties, capacity mismatches, or combined-table needs.
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
