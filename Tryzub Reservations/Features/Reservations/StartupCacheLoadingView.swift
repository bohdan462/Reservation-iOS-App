//
//  StartupCacheLoadingView.swift
//  Tryzub Reservations
//
//  Entrance loading screen when the app is not ready to show cached UI.
//

import SwiftUI

struct StartupCacheLoadingView: View {
  let mode: StartupCacheLoadingMode
  let errorMessage: String?
  let onRetry: () -> Void

  @State private var showsDelayedMessage = false

  var body: some View {
    VStack(spacing: 20) {
      Spacer()

      VStack(spacing: 8) {
        Text("Tryzub Reservations")
          .font(.title2.weight(.semibold))

        Text(title)
          .font(.headline)

        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)
      }

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .font(.footnote.weight(.medium))
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)

        Button("Retry", action: onRetry)
          .buttonStyle(.borderedProminent)
      } else {
        ProgressView()
          .controlSize(.regular)
          .padding(.top, 4)

        if showsDelayedMessage {
          Text("Still connecting…")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
    .task {
      guard errorMessage == nil, mode == .loadingFromNetwork else { return }
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled else { return }
      showsDelayedMessage = true
    }
  }

  private var title: String {
    switch mode {
    case .checkingSavedData:
      return "Loading saved data"
    case .loadingSavedReservations:
      return "Loading saved reservations"
    case .loadingFromNetwork:
      return "Loading reservations"
    }
  }

  private var subtitle: String {
    switch mode {
    case .checkingSavedData:
      return "Preparing the latest saved schedule."
    case .loadingSavedReservations:
      return "Opening the latest saved schedule."
    case .loadingFromNetwork:
      return "Checking the latest bookings."
    }
  }
}
