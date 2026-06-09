//
//  HostLocalModelFileLocator.swift
//  Tryzub Reservations
//
//  Locates a bundled or Application Support GGUF model. No downloads.
//

import Foundation

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

  static func applicationSupportModelURL() -> URL? {
    let candidate = URL(fileURLWithPath: applicationSupportCandidatePath())
    return fileExists(at: candidate) ? candidate : nil
  }

  static func firstAvailableModelURL() -> URL? {
    bundledModelURL() ?? applicationSupportModelURL()
  }

  static func modelPresenceDescription() -> String {
    if let bundled = bundledModelURL() {
      return "Bundled model found at \(bundled.lastPathComponent)."
    }
    if let appSupport = applicationSupportModelURL() {
      return "Application Support model found at \(appSupport.path)."
    }
    return "No model file in app bundle or Application Support (\(expectedModelFileName))."
  }

  static func modelSourceLabel() -> String {
    if bundledModelURL() != nil {
      return "bundled"
    }
    if applicationSupportModelURL() != nil {
      return "application support"
    }
    return "missing"
  }

  static func modelLookupPathDescription() -> String {
    let bundledPath = Bundle.main.path(
      forResource: expectedModelBaseName,
      ofType: expectedModelExtension
    ) ?? "not in app bundle"
    let appSupportPath = applicationSupportCandidatePath()
    return "Bundle: \(bundledPath). Application Support: \(appSupportPath)."
  }

  private static func applicationSupportCandidatePath() -> String {
    guard let supportDirectory = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      return "Application Support unavailable"
    }

    return supportDirectory
      .appendingPathComponent("HostIntelligence", isDirectory: true)
      .appendingPathComponent("Models", isDirectory: true)
      .appendingPathComponent(expectedModelFileName)
      .path
  }

  private static func fileExists(at url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }
}
