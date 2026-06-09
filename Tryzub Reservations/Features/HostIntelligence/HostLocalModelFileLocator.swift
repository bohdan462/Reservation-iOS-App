//
//  HostLocalModelFileLocator.swift
//  Tryzub Reservations
//
//  Locates a bundled or Application Support GGUF model. No downloads.
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
  static let expectedModelBaseName = "host-briefing-qwen2_5-0_5b-instruct-q4_k_m"
  static let expectedModelExtension = "gguf"

  static var expectedModelFileName: String {
    "\(expectedModelBaseName).\(expectedModelExtension)"
  }

  static func bundledModelURL() -> URL? {
    guard let url = Bundle.main.url(
      forResource: expectedModelBaseName,
      withExtension: expectedModelExtension
    ) else {
      return nil
    }
    return fileExists(at: url) ? url : nil
  }

  static func applicationSupportModelDestinationURL() -> URL? {
    guard let directory = applicationSupportModelDirectoryURL() else {
      return nil
    }
    return directory.appendingPathComponent(expectedModelFileName)
  }

  static func applicationSupportModelURL() -> URL? {
    guard let candidate = applicationSupportModelDestinationURL() else {
      return nil
    }
    return fileExists(at: candidate) ? candidate : nil
  }

  /// Path used for on-device inference. Never loads directly from the app bundle.
  static func inferenceModelURL() -> URL? {
    applicationSupportModelURL()
  }

  /// Backward-compatible alias for inference path only.
  static func firstAvailableModelURL() -> URL? {
    inferenceModelURL()
  }

  static func resolvedModelSourceKind() -> HostLocalModelSourceKind {
    if applicationSupportModelURL() != nil {
      return .applicationSupport
    }
    if bundledModelURL() != nil {
      return .bundled
    }
    return .missing
  }

  static func resolvedModelSourceDisplayName() -> String {
    resolvedModelSourceKind().displayName
  }

  static func needsBundledModelPreparation() -> Bool {
    applicationSupportModelURL() == nil && bundledModelURL() != nil
  }

  static func modelPresenceDescription() -> String {
    if let appSupport = applicationSupportModelURL() {
      return "Prepared model found in Application Support at \(appSupport.lastPathComponent)."
    }
    if let bundled = bundledModelURL() {
      return "Bundled model resource is packaged (\(bundled.lastPathComponent)) but not prepared for inference."
    }
    return "No model file in app bundle or Application Support (\(expectedModelFileName))."
  }

  static func modelSourceLabel() -> String {
    resolvedModelSourceKind().rawValue
  }

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

  static func expectedApplicationSupportModelPathDescription() -> String {
    applicationSupportModelDestinationURL()?.path ?? "Application Support unavailable"
  }

  static func modelLookupPathDescription() -> String {
    let bundledPath = Bundle.main.path(
      forResource: expectedModelBaseName,
      ofType: expectedModelExtension
    ) ?? "not in app bundle"
    return "Bundle: \(bundledPath). Application Support: \(expectedApplicationSupportModelPathDescription())."
  }

  private static func applicationSupportCandidatePath() -> String {
    expectedApplicationSupportModelPathDescription()
  }

  private static func fileExists(at url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }
}
