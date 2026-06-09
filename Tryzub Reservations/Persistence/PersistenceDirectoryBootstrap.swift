//
//  PersistenceDirectoryBootstrap.swift
//  Tryzub Reservations
//
//  Ensures Application Support exists before SwiftData/CoreData opens default.store.
//

import Foundation

enum PersistenceDirectoryBootstrap {
  enum BootstrapError: LocalizedError {
    case applicationSupportUnavailable
    case directoryCreationFailed(underlying: Error)

    var errorDescription: String? {
      switch self {
      case .applicationSupportUnavailable:
        return "Application Support directory URL is unavailable."
      case .directoryCreationFailed(let underlying):
        return "Could not create Application Support directory: \(underlying.localizedDescription)"
      }
    }
  }

  static func ensureApplicationSupportDirectoryExists() throws {
    guard let applicationSupportURL = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      throw BootstrapError.applicationSupportUnavailable
    }

    do {
      try FileManager.default.createDirectory(
        at: applicationSupportURL,
        withIntermediateDirectories: true
      )
    } catch {
      #if DEBUG
      print("[PERSISTENCE] Failed to create Application Support directory: \(error.localizedDescription)")
      #endif
      throw BootstrapError.directoryCreationFailed(underlying: error)
    }

    #if DEBUG
    print("[PERSISTENCE] Application Support directory ready at \(applicationSupportURL.path)")
    #endif
  }
}
