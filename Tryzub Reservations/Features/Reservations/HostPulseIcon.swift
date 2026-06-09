//
//  HostPulseIcon.swift
//  Tryzub Reservations
//
//  Subtle operational awareness indicator for the Host board card.
//

import SwiftUI

struct HostPulseIcon: View {
  var isActive: Bool
  var size: CGFloat = 12

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulse = false
  @State private var ripple = false

  var body: some View {
    ZStack {
      if isActive, !reduceMotion {
        Circle()
          .stroke(TryzubColors.primaryControl.opacity(0.35), lineWidth: 0.75)
          .frame(width: size, height: size)
          .scaleEffect(ripple ? 1.55 : 0.85)
          .opacity(ripple ? 0 : 0.45)
      }

      Circle()
        .strokeBorder(TryzubColors.primaryControl.opacity(ringOpacity), lineWidth: 1)
        .frame(width: size, height: size)
        .scaleEffect(pulse && isActive && !reduceMotion ? 1.12 : 1)

      Circle()
        .fill(TryzubColors.primaryControl.opacity(centerOpacity))
        .frame(width: size * 0.5, height: size * 0.5)

      Circle()
        .fill(TryzubColors.primaryControl)
        .frame(width: size * 0.22, height: size * 0.22)
        .scaleEffect(pulse && isActive && !reduceMotion ? 1.15 : 1)
    }
    .frame(width: size * 1.6, height: size * 1.6)
    .accessibilityLabel("Service awareness")
    .onAppear { updateAnimation() }
    .onChange(of: isActive) { _, _ in updateAnimation() }
    .onChange(of: reduceMotion) { _, _ in updateAnimation() }
  }

  private var ringOpacity: Double {
    isActive ? 0.7 : 0.25
  }

  private var centerOpacity: Double {
    isActive ? 0.18 : 0.07
  }

  private func updateAnimation() {
    guard isActive, !reduceMotion else {
      pulse = false
      ripple = false
      return
    }
    withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
      pulse = true
    }
    withAnimation(.easeOut(duration: 1.35).repeatForever(autoreverses: false)) {
      ripple = true
    }
  }
}
