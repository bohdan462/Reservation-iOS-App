//
//  HostServiceBriefingNarrative.swift
//  Tryzub Reservations
//
//  Result model for the 4E Service Intelligence narrative layer.
//  Represents template fallback or validated local-model output keyed
//  to a specific HostServiceBriefingPacket fingerprint.
//
//  UI-neutral: no SwiftUI import.
//

import Foundation

// MARK: - Source

enum ServiceBriefingNarrativeSource: String, Equatable, Sendable {
    /// No narrative generated yet (initial state).
    case none
    /// Deterministic template prose from HostServiceBriefingTemplateWriter.
    case template
    /// Validated local-model output accepted without repairs.
    case localModel
    /// Local-model output with minor structural repairs; still model-generated.
    case repairedLocalModel
    /// Template used as fallback after model gate/validation failure.
    case fallback
}

// MARK: - Result model

/// Cached output of the 4E narrative pass.
/// Keyed by `packetFingerprint` so stale results are safely ignored.
struct HostServiceBriefingNarrative: Equatable, Sendable {
    /// Compact staff-facing headline (equivalent of packet.compactLine but model-worded).
    let compactLine: String
    /// Wording overrides for specific section IDs (e.g. "arrivals", "guests", "followup").
    /// Empty when the model produced a compact-only rewrite.
    let sectionLinesByID: [String: [String]]
    /// How this narrative was produced.
    let source: ServiceBriefingNarrativeSource
    /// Set when model generation was attempted but fell back to template.
    let failedReason: String?
    /// The service date this narrative is valid for.
    let dateKey: String
    /// The `HostServiceBriefingPacket.inputFingerprint` that produced this narrative.
    let packetFingerprint: String
    /// The source fingerprint passed through the controller stale guard.
    let sourceFingerprint: String
    /// Identifies the prompt schema version. Bump when prompt changes to invalidate cached output.
    let promptVersion: String
    let createdAt: Date

    // MARK: - Sentinel

    static let empty = HostServiceBriefingNarrative(
        compactLine: "",
        sectionLinesByID: [:],
        source: .none,
        failedReason: nil,
        dateKey: "",
        packetFingerprint: "empty",
        sourceFingerprint: "",
        promptVersion: "",
        createdAt: Date(timeIntervalSince1970: 0)
    )

    // MARK: - Helpers

    /// Returns true when this narrative is valid for the given packet.
    func isCurrent(dateKey: String, packetFingerprint: String) -> Bool {
        guard source != .none,
              !self.dateKey.isEmpty,
              self.dateKey == dateKey,
              self.packetFingerprint != "empty",
              self.packetFingerprint == packetFingerprint else {
            return false
        }
        return true
    }

    /// True when the narrative was produced (at least in part) by the local model.
    var usesModel: Bool {
        source == .localModel || source == .repairedLocalModel
    }

    /// True when there is a displayable compact line from any source.
    var hasUsableCopy: Bool {
        source != .none && !compactLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
