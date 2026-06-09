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

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var showsDelayedMessage = false
  @State private var pulse = false

  var body: some View {
    ZStack {
      StartupLoadingBackdrop()

      VStack(spacing: 22) {
        Spacer()

        VStack(spacing: 14) {
          ZStack {
            if !reduceMotion {
              Circle()
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                .frame(width: 54, height: 54)
                .scaleEffect(pulse ? 1.18 : 0.92)
                .opacity(pulse ? 0 : 0.55)
            }

            HostPulseIcon(isActive: true, size: 14)
          }
          .frame(height: 56)

          VStack(spacing: 6) {
            Text("Tryzub")
              .font(.title2.weight(.semibold))
              .foregroundStyle(.primary.opacity(0.9))

            Text(title)
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .startupGlassCard()

        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle")
            .font(.footnote.weight(.medium))
            .foregroundStyle(TryzubColors.danger)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

          Button("Retry", action: onRetry)
            .buttonStyle(.borderedProminent)
        } else {
          ProgressView()
            .controlSize(.regular)

          if showsDelayedMessage {
            Text("Still connecting…")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
        }

        Spacer()
      }
      .padding(.horizontal, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
        pulse = true
      }
    }
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
      return "Opening saved schedule"
    case .loadingSavedReservations:
      return "Loading reservations"
    case .loadingFromNetwork:
      return "Syncing bookings"
    }
  }
}

private struct StartupLoadingBackdrop: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(.systemGroupedBackground),
          Color(.systemGroupedBackground).opacity(0.92),
          Color.accentColor.opacity(0.06)
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      Circle()
        .fill(Color.accentColor.opacity(0.12))
        .frame(width: 220, height: 220)
        .blur(radius: 60)
        .offset(y: -180)
    }
    .ignoresSafeArea()
  }
}

private extension View {
  @ViewBuilder
  func startupGlassCard() -> some View {
    if #available(iOS 26.0, *) {
      self
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    } else {
      self
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
  }
}
