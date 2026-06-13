//
//  HostLocalModelFileLocator.swift
//  Tryzub Reservations
//
//  Locates a bundled or Application Support GGUF model. No downloads.
//
//  Resolution order for inference:
//    1. Application Support  (manually prepared from bundle or imported via Files)
//    2. Bundle resource      (readable directly by llama.cpp on iOS/iPadOS)
//  This means a bundled 3B model is immediately usable without a prepare step.
//

import Foundation

enum HostLocalModelSourceKind: String, Equatable {
  case applicationSupport
  case bundled
  case missing

  var displayName: String {
    switch self {
    case .applicationSupport: return "Application Support"
    case .bundled: return "Bundled"
    case .missing: return "Missing"
    }
  }
}

enum HostLocalModelFileLocator {
  // MARK: - Model filenames

  /// Base name used by the small 0.5B model.
  static let smallModelBaseName = "host-briefing-qwen2_5-0_5b-instruct-q4_k_m"
  /// Shared extension for all GGUF models.
  static let expectedModelExtension = "gguf"

  // Legacy alias kept for compatibility with older call sites.
  static var expectedModelBaseName: String { smallModelBaseName }
  static var expectedModelFileName: String { "\(smallModelBaseName).\(expectedModelExtension)" }

  // MARK: - Best-available resolution (demo / iPad build)

  /// Returns the best inference URL available, preferring betterLocal3B over smallFastLocal.
  /// Pass `excluding` to skip model paths that failed to load this session.
  static func bestAvailableInferenceModelURL(excluding failedPaths: Set<String> = []) -> URL? {
    for profile in [LocalWordingModelProfile.betterLocal3B, .smallFastLocal] {
      guard let url = inferenceModelURL(profile: profile) else { continue }
      guard !failedPaths.contains(url.path) else { continue }
      return url
    }
    return nil
  }

  /// Returns the best available wording profile given current model files on disk.
  static func bestAvailableProfile(excluding failedPaths: Set<String> = []) -> LocalWordingModelProfile {
    for profile in [LocalWordingModelProfile.betterLocal3B, .smallFastLocal] {
      guard let url = inferenceModelURL(profile: profile) else { continue }
      guard !failedPaths.contains(url.path) else { continue }
      return profile
    }
    return .template
  }

  // MARK: - Per-profile lookups

  static func bundledModelURL(profile: LocalWordingModelProfile) -> URL? {
    guard let modelBaseName = modelBaseName(profile: profile) else { return nil }
    guard let url = Bundle.main.url(
      forResource: modelBaseName,
      withExtension: expectedModelExtension
    ) else {
      return nil
    }
    return fileExists(at: url) ? url : nil
  }

  static func applicationSupportModelDestinationURL(profile: LocalWordingModelProfile) -> URL? {
    guard let directory = applicationSupportModelDirectoryURL() else {
      return nil
    }
    guard let fileName = profile.modelFileName else { return nil }
    return directory.appendingPathComponent(fileName)
  }

  /// True when the model is in the bundle but hasn't been prepared in Application Support.
  static func needsBundledModelPreparation(profile: LocalWordingModelProfile) -> Bool {
    applicationSupportModelURL(profile: profile) == nil && bundledModelURL(profile: profile) != nil
  }

  /// Returns the model URL in Application Support, or nil if not present.
  static func applicationSupportModelURL(profile: LocalWordingModelProfile) -> URL? {
    guard let candidate = applicationSupportModelDestinationURL(profile: profile) else {
      return nil
    }
    return fileExists(at: candidate) ? candidate : nil
  }

  /// Path used for on-device inference.
  /// Checks Application Support first, then the bundle resource (direct GGUF read on iOS).
  /// Never loads from the bundle if a prepared App Support copy already exists.
  static func inferenceModelURL(profile: LocalWordingModelProfile) -> URL? {
    if let appSupportURL = applicationSupportModelURL(profile: profile) {
      return appSupportURL
    }
    // Fall back to the bundled resource path. llama.cpp can read directly from the
    // app bundle on iOS/iPadOS because it is an uncompressed resource directory.
    if let bundledURL = bundledModelURL(profile: profile) {
      return bundledURL
    }
    return nil
  }

  // MARK: - Source kind

  static func resolvedModelSourceKind(profile: LocalWordingModelProfile) -> HostLocalModelSourceKind {
    if applicationSupportModelURL(profile: profile) != nil {
      return .applicationSupport
    }
    if bundledModelURL(profile: profile) != nil {
      return .bundled
    }
    return .missing
  }

  static func resolvedModelSourceDisplayName(profile: LocalWordingModelProfile) -> String {
    resolvedModelSourceKind(profile: profile).displayName
  }

  // MARK: - Diagnostics

  /// True when the 3B wording model is present in the app bundle.
  static var is3BBundled: Bool {
    bundledModelURL(profile: .betterLocal3B) != nil
  }

  /// True when the 3B wording model has been prepared in Application Support.
  static var is3BInApplicationSupport: Bool {
    applicationSupportModelURL(profile: .betterLocal3B) != nil
  }

  /// Human-readable presence description for settings/diagnostics UI.
  static func modelPresenceDescription(profile: LocalWordingModelProfile) -> String {
    guard let expectedFileName = profile.modelFileName else {
      return "Template wording does not use a local model file."
    }
    if let appSupport = applicationSupportModelURL(profile: profile) {
      return "Prepared model found in Application Support at \(appSupport.lastPathComponent)."
    }
    if let bundled = bundledModelURL(profile: profile) {
      return "Bundled model resource packaged (\(bundled.lastPathComponent)). Readable directly for inference."
    }
    return "No model file in app bundle or Application Support (\(expectedFileName))."
  }

  static func modelLookupPathDescription(profile: LocalWordingModelProfile) -> String {
    guard let modelBaseName = modelBaseName(profile: profile),
          let modelFileName = profile.modelFileName else {
      return "Template wording does not use model lookup paths."
    }
    let bundledPath = Bundle.main.path(
      forResource: modelBaseName,
      ofType: expectedModelExtension
    ) ?? "not in app bundle"
    let appSupportPath = applicationSupportModelDestinationURL(profile: profile)?.path
      ?? "Application Support unavailable"
    return "Bundle: \(bundledPath). Application Support: \(appSupportPath). Expected file: \(modelFileName)."
  }

  // MARK: - Application Support directory

  static func applicationSupportModelDirectoryURL() -> URL? {
    guard let supportDirectory = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      return nil
    }
    return supportDirectory
      .appendingPathComponent("HostIntelligence", isDirectory: true)
      .appendingPathComponent("Models", isDirectory: true)
  }

  // MARK: - Legacy no-arg aliases (smallFastLocal default)

  static func bundledModelURL() -> URL? {
    bundledModelURL(profile: .smallFastLocal)
  }

  static func applicationSupportModelDestinationURL() -> URL? {
    applicationSupportModelDestinationURL(profile: .smallFastLocal)
  }

  static func applicationSupportModelURL() -> URL? {
    applicationSupportModelURL(profile: .smallFastLocal)
  }

  static func inferenceModelURL() -> URL? {
    inferenceModelURL(profile: .smallFastLocal)
  }

  static func firstAvailableModelURL() -> URL? {
    inferenceModelURL()
  }

  static func resolvedModelSourceKind() -> HostLocalModelSourceKind {
    resolvedModelSourceKind(profile: .smallFastLocal)
  }

  static func resolvedModelSourceDisplayName() -> String {
    resolvedModelSourceKind().displayName
  }

  static func needsBundledModelPreparation() -> Bool {
    needsBundledModelPreparation(profile: .smallFastLocal)
  }

  static func modelPresenceDescription() -> String {
    modelPresenceDescription(profile: .smallFastLocal)
  }

  static func modelLookupPathDescription() -> String {
    modelLookupPathDescription(profile: .smallFastLocal)
  }

  static func modelSourceLabel() -> String {
    resolvedModelSourceKind().rawValue
  }

  static func expectedApplicationSupportModelPathDescription(profile: LocalWordingModelProfile) -> String {
    applicationSupportModelDestinationURL(profile: profile)?.path ?? "Application Support unavailable"
  }

  static func expectedApplicationSupportModelPathDescription() -> String {
    expectedApplicationSupportModelPathDescription(profile: .smallFastLocal)
  }

  // MARK: - Private helpers

  private static func modelBaseName(profile: LocalWordingModelProfile) -> String? {
    guard let fileName = profile.modelFileName else { return nil }
    return (fileName as NSString).deletingPathExtension
  }

  private static func fileExists(at url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }
}
