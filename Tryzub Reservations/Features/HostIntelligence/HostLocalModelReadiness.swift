//
//  HostLocalModelReadiness.swift
//  Tryzub Reservations
//
//  Readiness state for on-device wording model. Lightweight — no model loading.
//
//  The no-argument `currentReadiness()` checks the best available profile
//  (betterLocal3B → smallFastLocal → template) so callers that have not yet
//  been updated to pass an explicit profile still behave correctly in the
//  iPad/demo build where only the 3B model is bundled.
//

import Foundation

enum HostLocalModelReadinessStatus: String, Codable, Equatable {
  case unavailable
  case modelMissing
  case runtimeMissing
  case ready
}

struct HostLocalModelReadiness: Codable, Equatable {
  let status: HostLocalModelReadinessStatus
  let title: String
  let detail: String
  let modelName: String?
  let runtimeName: String?
}

extension HostLocalModelReadiness {
  static let unavailable = HostLocalModelReadiness(
    status: .unavailable,
    title: "Local model unavailable",
    detail: "On-device briefing is not available in this build.",
    modelName: nil,
    runtimeName: nil
  )

  static let runtimeMissing = HostLocalModelReadiness(
    status: .runtimeMissing,
    title: "Local model runtime missing",
    detail: "No local model runtime is included in this build.",
    modelName: nil,
    runtimeName: nil
  )

  static let modelMissing = HostLocalModelReadiness(
    status: .modelMissing,
    title: "Local model file missing",
    detail: "A model runtime may be present, but no wording model is installed.",
    modelName: nil,
    runtimeName: nil
  )
}

enum HostLocalModelReadinessProvider {

  /// Checks readiness for the best available wording model.
  /// Prefers betterLocal3B, falls back to smallFastLocal.
  /// Returns `.ready` for the template profile even when no model file is present
  /// because template never requires a file.
  static func currentReadiness() -> HostLocalModelReadiness {
    let profile = HostLocalModelFileLocator.bestAvailableProfile()
    return currentReadiness(profile: profile)
  }

  static func currentReadiness(profile: LocalWordingModelProfile) -> HostLocalModelReadiness {
    if profile == .template {
      return HostLocalModelReadiness(
        status: .ready,
        title: "Template wording",
        detail: "Reliable template wording does not use a local model file.",
        modelName: nil,
        runtimeName: nil
      )
    }

    guard HostLocalModelRuntimeFactory.isRuntimeIntegrated else {
      let adapterNote = HostLocalModelRuntimeFactory.isAdapterShellPresent
        ? "Adapter shell is present, but inference runtime is not linked."
        : "No local model adapter is present."
      return HostLocalModelReadiness(
        status: .runtimeMissing,
        title: "Local model runtime missing",
        detail: "\(adapterNote) \(HostLocalModelFileLocator.modelLookupPathDescription(profile: profile))",
        modelName: profile.modelFileName,
        runtimeName: nil
      )
    }

    let runtimeName = HostLocalModelRuntimeFactory.integratedRuntimeName
    let presence = HostLocalModelFileLocator.modelPresenceDescription(profile: profile)
    let source = HostLocalModelFileLocator.resolvedModelSourceDisplayName(profile: profile)

    guard HostLocalModelFileLocator.inferenceModelURL(profile: profile) != nil else {
      let prepareHint = HostLocalModelFileLocator.needsBundledModelPreparation(profile: profile)
        ? " Tap Prepare local model in diagnostics to copy the bundled file into Application Support."
        : ""
      let title = profile == .betterLocal3B
        ? "Better local model not installed"
        : "Local model not prepared"
      let detailPrefix = profile == .betterLocal3B
        ? "Better local model not installed. Using fallback wording. "
        : ""
      return HostLocalModelReadiness(
        status: .modelMissing,
        title: title,
        detail: "\(detailPrefix)\(presence)\(prepareHint) Expected file: \(profile.modelFileName ?? "none").",
        modelName: profile.modelFileName,
        runtimeName: runtimeName
      )
    }

    return HostLocalModelReadiness(
      status: .ready,
      title: profile == .betterLocal3B ? "Better local model ready" : "Local model ready",
      detail: "\(presence) Source: \(source).",
      modelName: profile.modelFileName,
      runtimeName: runtimeName
    )
  }

  // MARK: - Developer diagnostics

  /// Quick summary for the developer diagnostics panel.
  static var bundleStatusSummary: String {
    let is3BBundled = HostLocalModelFileLocator.is3BBundled
    let is3BInAppSupport = HostLocalModelFileLocator.is3BInApplicationSupport
    let is3BReady = HostLocalModelFileLocator.inferenceModelURL(profile: .betterLocal3B) != nil
    let isSmallBundled = HostLocalModelFileLocator.bundledModelURL(profile: .smallFastLocal) != nil
    let best = HostLocalModelFileLocator.bestAvailableProfile()

    return [
      "3B bundled: \(is3BBundled ? "yes" : "no")",
      "3B in AppSupport: \(is3BInAppSupport ? "yes" : "no")",
      "3B inference-ready: \(is3BReady ? "yes" : "no")",
      "0.5B bundled: \(isSmallBundled ? "yes" : "no")",
      "Best profile: \(best.traceName)"
    ].joined(separator: " | ")
  }
}
