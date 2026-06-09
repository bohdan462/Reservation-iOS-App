//
//  OnDeviceSupportStatusBanner.swift
//  Tryzub Reservations
//
//  Non-blocking staff-facing status for on-device support preparation.
//

import SwiftUI

enum OnDeviceSupportStatusBannerStyle {
  case compact
  case card
}

struct OnDeviceSupportStatusBanner: View {
  let phase: HostOnDeviceSupportPhase
  var style: OnDeviceSupportStatusBannerStyle = .compact

  var body: some View {
    switch style {
    case .compact:
      compactBanner
    case .card:
      cardBanner
    }
  }

  @ViewBuilder
  private var compactBanner: some View {
    if let line = phase.hostTabLine {
      HStack(spacing: 8) {
        HostPulseIcon(isActive: phase.pulseIsActive, size: 14)
        if let fraction = phase.copyProgressFraction, case .preparing = phase {
          VStack(alignment: .leading, spacing: 4) {
            Text(line)
              .font(.caption.weight(.medium))
              .foregroundStyle(TryzubColors.primaryText)
            ProgressView(value: fraction)
              .tint(TryzubColors.primaryControl)
          }
        } else {
          Text(line)
            .font(.caption.weight(.medium))
            .foregroundStyle(phase.failedStaffMessage != nil ? TryzubColors.mutedText : TryzubColors.primaryText)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        Color(.secondarySystemGroupedBackground),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .allowsHitTesting(false)
      .accessibilityElement(children: .combine)
    }
  }

  private var cardBanner: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        HostPulseIcon(isActive: phase.pulseIsActive, size: 20)
        VStack(alignment: .leading, spacing: 2) {
          Text(phase.title)
            .font(.subheadline.weight(.semibold))
          if let subtitle = phase.subtitle {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 0)
      }

      if let fraction = phase.copyProgressFraction, case .preparing = phase {
        ProgressView(value: fraction) {
          Text("Preparing on-device assistance · \(Int((fraction * 100).rounded()))%")
            .font(.caption.weight(.medium))
        }
        .tint(TryzubColors.primaryControl)
      } else if case .waitingForSafeMoment = phase {
        ProgressView()
          .controlSize(.small)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
  }
}

private extension HostOnDeviceSupportPhase {
  var failedStaffMessage: String? {
    if case .failed(let message) = self { return message }
    return nil
  }
}

struct OnDeviceSupportMoreSection: View {
  @ObservedObject var coordinator: HostLocalModelAutoPrepareCoordinator

  var body: some View {
    if shouldShowSection {
      Section("On-device support") {
        OnDeviceSupportStatusBanner(phase: displayPhase, style: .card)

        if coordinator.hasCompletedAutoPrepare
          || HostLocalModelFileLocator.applicationSupportModelURL() != nil {
          Label("Works privately on this iPhone", systemImage: "lock.iphone")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var shouldShowSection: Bool {
    if displayPhase.showsMoreSection { return true }
    if coordinator.hasCompletedAutoPrepare,
       HostLocalModelFileLocator.applicationSupportModelURL() != nil {
      return false
    }
    if HostLocalModelFileLocator.bundledModelURL() == nil,
       HostLocalModelRuntimeFactory.isRuntimeIntegrated {
      return true
    }
    return coordinator.isPrepareInFlight
  }

  private var displayPhase: HostOnDeviceSupportPhase {
    if case .idle = coordinator.phase,
       HostLocalModelFileLocator.bundledModelURL() == nil,
       HostLocalModelRuntimeFactory.isRuntimeIntegrated,
       HostLocalModelFileLocator.applicationSupportModelURL() == nil {
      return .unavailable
    }
    return coordinator.phase
  }
}
