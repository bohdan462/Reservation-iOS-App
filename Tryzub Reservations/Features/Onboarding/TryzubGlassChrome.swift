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
  static let hostBoardAccentBlue = Color(.systemBlue)
}

// MARK: - Host Board Canvas

struct TryzubHostBoardCanvas<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    ZStack {
      hostBoardAtmosphere
      content()
    }
  }

  private var hostBoardAtmosphere: some View {
    ZStack {
      Color(.systemBackground)
        .ignoresSafeArea()

      Circle()
        .fill(Color.accentColor.opacity(0.10))
        .frame(width: 360, height: 360)
        .blur(radius: 95)
        .offset(x: -130, y: -300)

      Circle()
        .fill(Color.blue.opacity(0.06))
        .frame(width: 300, height: 300)
        .blur(radius: 80)
        .offset(x: 150, y: 240)

      Circle()
        .fill(Color.accentColor.opacity(0.05))
        .frame(width: 220, height: 220)
        .blur(radius: 60)
        .offset(x: -60, y: 400)
    }
  }
}

// MARK: - Host Board Glass Surfaces

extension View {
  /// Liquid glass fill (iOS 26+) with a light material fallback. No stroke.
  func hostBoardGlassSurface(cornerRadius: CGFloat = 14) -> some View {
    background {
      Group {
        if #available(iOS 26.0, *) {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
        } else {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial.opacity(0.42))
        }
      }
    }
  }

  func hostBoardGlassPanel(
    cornerRadius: CGFloat = 14,
    strokeOpacity: Double = TryzubGlassChrome.surfaceStrokeOpacity
  ) -> some View {
    hostBoardGlassSurface(cornerRadius: cornerRadius)
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
  }

  func hostBoardGlassCapsule(strokeOpacity: Double = 0.08) -> some View {
    background {
      Group {
        if #available(iOS 26.0, *) {
          Capsule()
            .fill(.clear)
            .glassEffect(.clear, in: .capsule)
        } else {
          Capsule()
            .fill(.ultraThinMaterial.opacity(0.42))
        }
      }
    }
    .overlay {
      Capsule()
        .strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1)
    }
  }

  /// Host Board date chips and compact controls — clear glass when idle, Apple blue liquid glass when selected.
  func hostBoardGlassChip(
    cornerRadius: CGFloat,
    isSelected: Bool,
    strokeOpacity: Double = 0.08
  ) -> some View {
    background {
      Group {
        if #available(iOS 26.0, *) {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .glassEffect(
              isSelected
                ? .regular.tint(TryzubGlassChrome.hostBoardAccentBlue).interactive()
                : .clear,
              in: .rect(cornerRadius: cornerRadius)
            )
        } else {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
              isSelected
                ? TryzubGlassChrome.hostBoardAccentBlue.opacity(0.90)
                : .ultraThinMaterial.opacity(0.42)
            )
        }
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(
          isSelected
            ? TryzubGlassChrome.hostBoardAccentBlue.opacity(0.38)
            : Color.primary.opacity(strokeOpacity),
          lineWidth: 1
        )
    }
  }
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
