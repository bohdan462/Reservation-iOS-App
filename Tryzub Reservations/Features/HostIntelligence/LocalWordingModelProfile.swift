//
//  LocalWordingModelProfile.swift
//  Tryzub Reservations
//
//  Describes which local model file (or template fallback) is used for wording tasks
//  (Host summary, guest drafts). Distinct from HostLocalModelTaskProfile, which describes
//  per-task inference tuning parameters (tokens, system prompt, timeout).
//
//  iPad / demo build note:
//  REQUIRE_3B_HOST_MODEL=1 bundles host-wording-qwen2_5-3b-instruct-q4_k_m.gguf as the
//  primary wording model. The runtime prefers betterLocal3B when available and falls back
//  to smallFastLocal or template. No code path is deleted; only the priority order changes.
//

import Foundation

enum LocalWordingModelProfile: String, Equatable, CaseIterable, Sendable {
    /// Pure template writer — no local model required. Always available as critical fallback.
    case template

    /// Small 0.5B quantised model (fast, lower quality). Optional in demo/iPad builds.
    case smallFastLocal

    /// Better 3B quantised model. Primary wording model for the iPad/demo build.
    /// Bundled when REQUIRE_3B_HOST_MODEL=1.
    case betterLocal3B

    // MARK: - Properties

    /// The GGUF filename expected in Application Support / bundle.
    /// Returns `nil` for the template profile.
    var modelFileName: String? {
        switch self {
        case .template:
            return nil
        case .smallFastLocal:
            return "\(HostLocalModelFileLocator.smallModelBaseName).\(HostLocalModelFileLocator.expectedModelExtension)"
        case .betterLocal3B:
            return "host-wording-qwen2_5-3b-instruct-q4_k_m.gguf"
        }
    }

    /// Short identifier used in traces and diagnostics. Never log guest data alongside this.
    var traceName: String {
        switch self {
        case .template:       return "template"
        case .smallFastLocal: return "small_fast_local"
        case .betterLocal3B:  return "better_local_3b"
        }
    }

    /// Staff-readable label for settings and diagnostics UI.
    var displayName: String {
        switch self {
        case .template:       return "Reliable template"
        case .smallFastLocal: return "Fast local model (0.5B)"
        case .betterLocal3B:  return "Better local model (3B)"
        }
    }

    /// True when this profile requires a local model file to be present.
    var requiresModelFile: Bool { self != .template }
}
