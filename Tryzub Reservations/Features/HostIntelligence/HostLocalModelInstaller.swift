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
  case destinationUnavailable
  case copyFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidFileType:
      return "Selected file must be a .gguf model."
    case .sourceMissing:
      return "Selected model file is not available."
    case .destinationUnavailable:
      return "Application Support model directory is unavailable."
    case .copyFailed(let detail):
      return "Model copy failed: \(detail)"
    }
  }
}

enum HostLocalModelInstaller {
  /// Copies a user-selected GGUF into the expected Application Support path.
  /// Renames to `HostLocalModelFileLocator.expectedModelFileName` when needed.
  static func installModel(from sourceURL: URL) throws -> URL {
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
      try fileManager.copyItem(at: sourceURL, to: stagingURL)
      try fileManager.moveItem(at: stagingURL, to: destination)
    } catch {
      try? fileManager.removeItem(at: stagingURL)
      throw HostLocalModelInstallerError.copyFailed(error.localizedDescription)
    }

    return destination
  }

  private static var expectedModelFileName: String {
    HostLocalModelFileLocator.expectedModelFileName
  }
}
