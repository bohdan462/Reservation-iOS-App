//
//  TryzubGlassChrome.swift
//  Tryzub Reservations
//
//  Shared minimal grouped + glass surfaces for intro and sign-in.
//

import SwiftUI

enum TryzubGlassChrome {
  static let surfaceCorner: CGFloat = 18
  static let surfaceStrokeOpacity: Double = 0.08
}

struct TryzubGroupedCanvas<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    ZStack {
      Color(.systemGroupedBackground)
        .ignoresSafeArea()

      Circle()
        .fill(Color.accentColor.opacity(0.07))
        .frame(width: 280, height: 280)
        .blur(radius: 70)
        .offset(x: -90, y: -260)

      Circle()
        .fill(Color.accentColor.opacity(0.05))
        .frame(width: 220, height: 220)
        .blur(radius: 60)
        .offset(x: 110, y: 280)

      content()
    }
  }
}

struct TryzubGlassCapsuleButtonStyle: ButtonStyle {
  var isEnabled: Bool = true

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.primary.opacity(isEnabled ? 0.88 : 0.38))
      .background {
        glassCapsuleBackground
      }
      .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
      .opacity(configuration.isPressed && isEnabled ? 0.92 : 1)
      .animation(.snappy(duration: 0.18), value: configuration.isPressed)
  }

  @ViewBuilder
  private var glassCapsuleBackground: some View {
    if #available(iOS 26.0, *) {
      Capsule()
        .fill(.clear)
        .glassEffect(.regular.interactive(), in: .capsule)
    } else {
      Capsule()
        .fill(.regularMaterial)
        .overlay {
          Capsule()
            .stroke(Color.primary.opacity(TryzubGlassChrome.surfaceStrokeOpacity), lineWidth: 1)
        }
    }
  }
}

struct TryzubGlassBarButtonStyle: ButtonStyle {
  var isEnabled: Bool = true

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(isEnabled ? Color.primary.opacity(0.9) : Color.primary.opacity(0.35))
      .frame(maxWidth: .infinity, minHeight: 46)
      .background {
        glassBarBackground
      }
      .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
      .opacity(configuration.isPressed && isEnabled ? 0.94 : 1)
      .animation(.snappy(duration: 0.18), value: configuration.isPressed)
  }

  @ViewBuilder
  private var glassBarBackground: some View {
    let corner: CGFloat = 14
    if #available(iOS 26.0, *) {
      RoundedRectangle(cornerRadius: corner, style: .continuous)
        .fill(.clear)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: corner))
    } else {
      RoundedRectangle(cornerRadius: corner, style: .continuous)
        .fill(.regularMaterial)
        .overlay {
          RoundedRectangle(cornerRadius: corner, style: .continuous)
            .stroke(Color.primary.opacity(TryzubGlassChrome.surfaceStrokeOpacity), lineWidth: 1)
        }
    }
  }
}

extension View {
  func tryzubMinimalSurface(cornerRadius: CGFloat = TryzubGlassChrome.surfaceCorner) -> some View {
    background(
      Color(.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(Color.primary.opacity(TryzubGlassChrome.surfaceStrokeOpacity), lineWidth: 1)
    }
  }

  func tryzubLoginFieldChrome() -> some View {
    padding(.horizontal, 13)
      .frame(minHeight: 48)
      .background {
        if #available(iOS 26.0, *) {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.clear)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.systemBackground))
            .overlay {
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
      }
  }
}
