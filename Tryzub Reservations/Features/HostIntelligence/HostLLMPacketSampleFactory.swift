//
//  HostLLMPacketSampleFactory.swift
//  Tryzub Reservations
//
//  Developer-only synthetic HostLLMPacket fixtures for local model diagnostics.
//  Not used by the engine or Host board.
//

import Foundation

enum HostLLMPacketSampleFactory {

  enum Sample: String, CaseIterable {
    case calm
    case busy
    case critical

    var displayName: String {
      switch self {
      case .calm: return "Calm"
      case .busy: return "Busy"
      case .critical: return "Critical"
      }
    }

    var buttonTitle: String {
      "Test Sample: \(displayName)"
    }
  }

  static func calmWithNoFacts() -> HostLLMPacket {
    HostLLMPacket(
      generatedAtDescription: "Developer sample — calm service",
      serviceState: .calm,
      pressureScore: 0,
      topFacts: [],
      forbiddenBehaviors: HostLLMPacket.empty.forbiddenBehaviors,
      writingRules: HostLLMPacket.empty.writingRules
    )
  }

  static func busyHostShift() -> HostLLMPacket {
    HostLLMPacket(
      generatedAtDescription: "Developer sample — busy host shift",
      serviceState: .busy,
      pressureScore: 55,
      topFacts: [
        HostLLMFact(
          severity: .warning,
          category: .arrivalWave,
          title: "Arrival wave",
          detail: "Three parties are expected around 6:00 PM, totaling 12 guests.",
          evidence: ["Arrival cluster around 6:00 PM."],
          suggestedAction: "Review the 6:00 PM seating plan."
        ),
        HostLLMFact(
          severity: .watch,
          category: .table,
          title: "Table capacity option",
          detail: "Table 12 seats 6.",
          evidence: ["Local table inventory capacity."],
          suggestedAction: "Review Table 12 for a party of six."
        ),
        HostLLMFact(
          severity: .warning,
          category: .table,
          title: "No table assigned",
          detail: "Party of 6 for Natalia is due in 20 minutes and has no table assigned.",
          evidence: ["Large party without a table."],
          suggestedAction: "Review Table 12 for the party of 6."
        ),
        HostLLMFact(
          severity: .critical,
          category: .allergy,
          title: "Allergy note",
          detail: "A guest has a shellfish allergy note.",
          evidence: ["Allergy noted on the reservation."],
          suggestedAction: "Alert the server before seating."
        ),
      ],
      forbiddenBehaviors: HostLLMPacket.empty.forbiddenBehaviors,
      writingRules: HostLLMPacket.empty.writingRules
    )
  }

  static func criticalTablePressure() -> HostLLMPacket {
    HostLLMPacket(
      generatedAtDescription: "Developer sample — critical table pressure",
      serviceState: .critical,
      pressureScore: 85,
      topFacts: [
        HostLLMFact(
          severity: .critical,
          category: .capacity,
          title: "Table capacity mismatch",
          detail: "Assigned Table 4 seats 4, but the party size is 8.",
          evidence: ["Assigned table is too small."],
          suggestedAction: "Review a larger table or combined option."
        ),
        HostLLMFact(
          severity: .watch,
          category: .table,
          title: "Combined table option",
          detail: "Tables A5 + A6 seat 10 together.",
          evidence: ["Local combinable table inventory."],
          suggestedAction: "Review A5 + A6 for the party of 8."
        ),
        HostLLMFact(
          severity: .critical,
          category: .overdue,
          title: "Overdue large party",
          detail: "Party of 10 for Morgan is 15 minutes past their reservation time.",
          evidence: ["Large party is overdue."],
          suggestedAction: "Contact the party or release the hold."
        ),
        HostLLMFact(
          severity: .watch,
          category: .cancellation,
          title: "Table opportunity",
          detail: "A cancellation just opened Table 7 for the next hour.",
          evidence: ["Recent cancellation freed a table."],
          suggestedAction: "Offer Table 7 to waiting parties."
        ),
        HostLLMFact(
          severity: .warning,
          category: .timing,
          title: "Alternate time available",
          detail: "The 7:30 PM slot is full; 8:15 PM has availability for a party of four.",
          evidence: ["Later slot has capacity."],
          suggestedAction: "Suggest 8:15 PM to walk-in guests."
        ),
        HostLLMFact(
          severity: .warning,
          category: .guest,
          title: "Previous service issue",
          detail: "Guest Alex noted a slow service experience on the last visit.",
          evidence: ["Prior service note on file."],
          suggestedAction: "Brief the server before seating."
        )
      ],
      forbiddenBehaviors: HostLLMPacket.empty.forbiddenBehaviors,
      writingRules: HostLLMPacket.empty.writingRules
    )
  }

  static func packet(for sample: Sample) -> HostLLMPacket {
    switch sample {
    case .calm: return calmWithNoFacts()
    case .busy: return busyHostShift()
    case .critical: return criticalTablePressure()
    }
  }

  static func fallbackText(for sample: Sample) -> String {
    switch sample {
    case .calm:
      return "Service looks stable right now."
    case .busy:
      return "Service is busy. Review the top alerts before seating the next party."
    case .critical:
      return "Service is under heavy pressure. Address critical alerts first."
    }
  }
}
