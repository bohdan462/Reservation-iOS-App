//
//  TryzubProductIntroView.swift
//  Tryzub Reservations
//
//  First launch — operational engine core, glass continue.
//

import SwiftUI

struct TryzubProductIntroView: View {
  var onFinished: () -> Void

  var body: some View {
    ZStack {
      EngineWelcomeBackdrop()

      EngineWelcomeViewport()
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 76)

      VStack {
        Spacer()
        Button(action: onFinished) {
          HStack(spacing: 7) {
            Text("Continue")
            Image(systemName: "arrow.right")
              .font(.caption2.weight(.bold))
          }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white.opacity(0.92))
          .padding(.horizontal, 24)
          .padding(.vertical, 12)
        }
        .buttonStyle(TryzubEngineContinueButtonStyle())
        .padding(.bottom, 30)
      }
    }
    .preferredColorScheme(.dark)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Tryzub operational engine")
  }
}

// MARK: - Continue

struct TryzubEngineContinueButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background {
        ZStack {
          if #available(iOS 26.0, *) {
            Capsule()
              .fill(.clear)
              .glassEffect(.regular.interactive(), in: .capsule)
          } else {
            Capsule()
              .fill(.ultraThinMaterial.opacity(0.7))
          }

          Capsule()
            .stroke(
              LinearGradient(
                colors: [
                  Color.white.opacity(0.38),
                  Color.accentColor.opacity(0.55),
                  Color.white.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ),
              lineWidth: 0.85
            )
        }
      }
      .shadow(color: Color.accentColor.opacity(configuration.isPressed ? 0.2 : 0.38), radius: 14, y: 4)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.snappy(duration: 0.18), value: configuration.isPressed)
  }
}

#if DEBUG
#Preview {
  TryzubProductIntroView(onFinished: {})
}
#endif
