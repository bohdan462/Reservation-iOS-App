//
//  HostPulseIcon.swift
//  Tryzub Reservations
//
//  Subtle operational awareness indicator for the Host pulse card.
//

import SwiftUI

struct HostPulseIcon: View {
  var isActive: Bool
  var size: CGFloat = 18

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var animate = false

  var body: some View {
    ZStack {
      Circle()
        .strokeBorder(TryzubColors.primaryControl.opacity(ringOpacity), lineWidth: 1.25)
        .frame(width: size, height: size)
        .scaleEffect(animate && isActive && !reduceMotion ? 1.08 : 1)
        .opacity(animate && isActive && !reduceMotion ? 0.55 : 0.9)

      Circle()
        .fill(TryzubColors.primaryControl.opacity(centerOpacity))
        .frame(width: size * divotScale, height: size * divotScale)

      Circle()
        .fill(TryzubColors.primaryControl)
        .frame(width: size * 0.2, height: size * 0.2)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
    .onAppear {
      updateAnimation()
    }
    .onChange(of: isActive) { _, _ in
      updateAnimation()
    }
    .onChange(of: reduceMotion) { _, _ in
      updateAnimation()
    }
  }

  private var ringOpacity: Double {
    isActive ? 0.55 : 0.28
  }

  private var centerOpacity: Double {
    isActive ? 0.14 : 0.08
  }

  private var divotScale: CGFloat {
    isActive ? 0.52 : 0.46
  }

  private func updateAnimation() {
    guard isActive, !reduceMotion else {
      animate = false
      return
    }
    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
      animate = true
    }
  }
}
