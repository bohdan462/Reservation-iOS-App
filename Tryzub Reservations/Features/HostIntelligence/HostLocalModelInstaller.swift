//
//  HostLocalModelInstaller.swift
//  Tryzub Reservations
//
//  Developer-only manual GGUF import into Application Support. No downloads.
//

import Foundation

enum HostLocalModelInstallerError: LocalizedError, Equatable {
  case invalidFileType
  case sourceMissing
  case bundledModelMissing
  case destinationUnavailable
  case copyFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidFileType:
      return "Selected file must be a .gguf model."
    case .sourceMissing:
      return "Selected model file is not available."
    case .bundledModelMissing:
      return "Bundled briefing model resource is not packaged with this app."
    case .destinationUnavailable:
      return "Application Support model directory is unavailable."
    case .copyFailed(let detail):
      return "Model copy failed: \(detail)"
    }
  }
}

enum HostLocalModelInstaller {
  /// Copies the bundled GGUF into Application Support for diagnostics/manual inference only.
  static func installBundledModel(
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> URL {
    guard let bundledURL = HostLocalModelFileLocator.bundledModelURL() else {
      throw HostLocalModelInstallerError.bundledModelMissing
    }

    if let existing = HostLocalModelFileLocator.applicationSupportModelURL() {
      progress(1.0)
      return existing
    }

    return try await Task.detached(priority: .userInitiated) {
      try installModel(from: bundledURL, progress: progress)
    }.value
  }

  /// Copies a user-selected GGUF into the expected Application Support path.
  /// Renames to `HostLocalModelFileLocator.expectedModelFileName` when needed.
  static func installModel(from sourceURL: URL) throws -> URL {
    try installModel(from: sourceURL, progress: nil)
  }

  private static func installModel(
    from sourceURL: URL,
    progress: (@Sendable (Double) -> Void)?
  ) throws -> URL {
    guard sourceURL.pathExtension.compare(
      HostLocalModelFileLocator.expectedModelExtension,
      options: .caseInsensitive
    ) == .orderedSame else {
      throw HostLocalModelInstallerError.invalidFileType
    }

    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
      throw HostLocalModelInstallerError.sourceMissing
    }

    guard let directory = HostLocalModelFileLocator.applicationSupportModelDirectoryURL(),
          let destination = HostLocalModelFileLocator.applicationSupportModelDestinationURL() else {
      throw HostLocalModelInstallerError.destinationUnavailable
    }

    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      throw HostLocalModelInstallerError.copyFailed(error.localizedDescription)
    }

    let stagingURL = directory.appendingPathComponent("\(expectedModelFileName).importing")

    if fileManager.fileExists(atPath: stagingURL.path) {
      try fileManager.removeItem(at: stagingURL)
    }
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }

    do {
      if let progress {
        try copyFileWithProgress(from: sourceURL, to: stagingURL, progress: progress)
      } else {
        progress?(0)
        try fileManager.copyItem(at: sourceURL, to: stagingURL)
        progress?(1.0)
      }
      try fileManager.moveItem(at: stagingURL, to: destination)
    } catch {
      try? fileManager.removeItem(at: stagingURL)
      throw HostLocalModelInstallerError.copyFailed(error.localizedDescription)
    }

    return destination
  }

  private static func copyFileWithProgress(
    from sourceURL: URL,
    to destinationURL: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) throws {
    let fileManager = FileManager.default
    let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
    let totalBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0

    if totalBytes <= 0 {
      try fileManager.copyItem(at: sourceURL, to: destinationURL)
      progress(1.0)
      return
    }

    fileManager.createFile(atPath: destinationURL.path, contents: nil)
    let input = try FileHandle(forReadingFrom: sourceURL)
    defer { try? input.close() }
    let output = try FileHandle(forWritingTo: destinationURL)
    defer { try? output.close() }

    let chunkSize = 1_024 * 1_024
    var copiedBytes: Int64 = 0

    while true {
      let chunk = input.readData(ofLength: chunkSize)
      if chunk.isEmpty { break }
      output.write(chunk)
      copiedBytes += Int64(chunk.count)
      let fraction = min(1.0, Double(copiedBytes) / Double(totalBytes))
      progress(fraction)
    }

    progress(1.0)
  }

  private static var expectedModelFileName: String {
    HostLocalModelFileLocator.expectedModelFileName
  }
}
