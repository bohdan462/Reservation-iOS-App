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
      Write natural host or manager language in at most 3 short sentences when rich context exists; otherwise 1–2.
      Lead with service pressure or the most urgent reservation first.
      Explain the arrival pressure wave in plain staff language using only the provided pressure facts.
      Connect related operational facts only when useful for staff decisions.
      Use only the provided facts, pressure facts, and actions.
      Do not invent guests, tables, times, counts, allergies, notes, preferences, or actions.
      Do not invent pressure numbers, peak windows, or wave timing not in the packet.
      Do not say anything was confirmed, sent, seated, assigned, cancelled, or changed.
      Do not promise cake, discounts, decorations, VIP treatment, or special surprises.
      Do not mention AI, models, or validation.
      Do not use bullet points, numbering, or category tags like [critical/overdue].
      Do not use labels like HEADLINE, WHY, or CHECK.
      Do not start with Manager: or Host: or any role prefix.
      Do not use announcement tone such as Attention all staff members.
      Do not use second-person guest-facing language like you or your reservation.
      Do not use quotation marks.
      Mention returning guest, party size, dietary, occasion, or note signals only when provided.
      Write direct staff notes for coworkers, not broadcasts to guests.
      Output plain staff-facing prose only.
      """
    )

    sections.append("Surface: \(packet.surface.rawValue)")
    if !packet.generatedAtDescription.isEmpty {
      sections.append("Generated at: \(packet.generatedAtDescription)")
    }
    sections.append("Service state: \(packet.serviceState)")

    if let pressure = packet.arrivalPressureFacts {
      sections.append("Service pressure facts (deterministic — do not recalculate):")
      if let peak = pressure.peakWindow {
        sections.append("- Peak window: \(peak)")
      }
      sections.append("- Peak reservations: \(pressure.peakReservationCount)")
      sections.append("- Peak guests: \(pressure.peakGuestCount)")
      if let next = pressure.nextWaveStart {
        sections.append("- Next wave starts: \(next)")
      }
      sections.append("- Pressure level: \(pressure.pressureLevel)")
      sections.append("- No-table in peak: \(pressure.noTableInPeakCount)")
      sections.append("- Large parties in peak: \(pressure.largePartyInPeakCount)")
      sections.append("- Note signals in peak: \(pressure.noteSignalsInPeak)")
      sections.append("- Returning guests in peak: \(pressure.returningGuestSignalsInPeak)")
      sections.append("- Current time relation: \(pressure.currentTimeRelation)")
      sections.append("- Summary: \(pressure.pressureSummaryLine)")
    } else {
      sections.append("Service pressure facts: none")
    }

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
