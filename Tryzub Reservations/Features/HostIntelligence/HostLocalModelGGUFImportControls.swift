//
//  HostLocalModelGGUFImportControls.swift
//  Tryzub Reservations
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  static let hostBriefingGGUF = UTType(filenameExtension: "gguf") ?? .data
}

struct HostLocalModelGGUFImportControls: View {
  @Binding var isShowingModelImporter: Bool
  @Binding var modelImportMessage: String?
  @Binding var modelImportError: String?
  var compact: Bool = false
  let onImportSuccess: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !compact {
        Text("Local model import")
          .font(.subheadline.weight(.semibold))

        Text("Copies a .gguf from Files into Application Support on this iPhone. No network.")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      Button("Import GGUF from Files") {
        modelImportMessage = nil
        modelImportError = nil
        isShowingModelImporter = true
      }

      if let modelImportMessage, !modelImportMessage.isEmpty {
        Text(modelImportMessage)
          .font(.caption)
          .foregroundStyle(.green)
          .textSelection(.enabled)
      }

      if let modelImportError, !modelImportError.isEmpty {
        Text(modelImportError)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
    .padding(.vertical, compact ? 0 : 4)
    .fileImporter(
      isPresented: $isShowingModelImporter,
      allowedContentTypes: [.hostBriefingGGUF],
      allowsMultipleSelection: false
    ) { result in
      handleImport(result)
    }
  }

  private func handleImport(_ result: Result<[URL], Error>) {
    switch result {
    case .failure(let error):
      modelImportError = error.localizedDescription
      modelImportMessage = nil
    case .success(let urls):
      guard let sourceURL = urls.first else {
        modelImportError = "No file was selected."
        modelImportMessage = nil
        return
      }
      importModel(from: sourceURL)
    }
  }

  private func importModel(from sourceURL: URL) {
    let didAccess = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let destination = try HostLocalModelInstaller.installModel(from: sourceURL)
      modelImportMessage = "Model installed at \(destination.lastPathComponent)"
      modelImportError = nil
      HostLocalModelAutoPrepareCoordinator.shared.markCompleted()
      onImportSuccess()
    } catch {
      modelImportError = error.localizedDescription
      modelImportMessage = nil
    }
  }
}
