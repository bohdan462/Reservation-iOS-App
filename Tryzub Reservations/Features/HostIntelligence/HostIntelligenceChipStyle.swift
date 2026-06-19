//
//  HostIntelligenceChipStyle.swift
//  Tryzub Reservations
//
//  Compact Host Board intelligence chip chrome.
//

import SwiftUI

enum HostIntelligenceInlineVisualRole {
  case primaryAction
  case secondaryAction
  case info
}

extension View {
  func hostIntelligenceInlineChipChrome(
    role: HostIntelligenceInlineVisualRole,
    tint: Color,
    animateBorder _: Bool,
    cornerRadius: CGFloat = 13
  ) -> some View {
    modifier(
      HostIntelligenceInlineChipChromeModifier(
        role: role,
        tint: tint,
        cornerRadius: cornerRadius
      )
    )
  }
}

private struct HostIntelligenceInlineChipChromeModifier: ViewModifier {
  let role: HostIntelligenceInlineVisualRole
  let tint: Color
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .background(backgroundFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .background(tint.opacity(tintFillOpacity), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay {
        HostInlineChipBorder(
          cornerRadius: cornerRadius,
          staticOpacity: staticBorderOpacity,
          lineWidth: lineWidth
        )
      }
      .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 1)
  }

  private var horizontalPadding: CGFloat {
    switch role {
    case .primaryAction: return 9
    case .secondaryAction: return 8
    case .info: return 7
    }
  }

  private var verticalPadding: CGFloat {
    switch role {
    case .primaryAction: return 5
    case .secondaryAction, .info: return 4
    }
  }

  private var backgroundFill: some ShapeStyle {
    switch role {
    case .primaryAction:
      return AnyShapeStyle(.thinMaterial)
    case .secondaryAction:
      return AnyShapeStyle(.ultraThinMaterial)
    case .info:
      return AnyShapeStyle(Color.primary.opacity(0.025))
    }
  }

  private var staticBorderOpacity: Double {
    switch role {
    case .primaryAction: return 0.22
    case .secondaryAction: return 0.13
    case .info: return 0.05
    }
  }

  private var tintFillOpacity: Double {
    switch role {
    case .primaryAction: return 0.085
    case .secondaryAction: return 0.045
    case .info: return 0.0
    }
  }

  private var lineWidth: CGFloat {
    switch role {
    case .primaryAction: return 1.15
    case .secondaryAction: return 0.75
    case .info: return 0.55
    }
  }

  private var shadowColor: Color {
    switch role {
    case .primaryAction:
      return tint.opacity(0.12)
    case .secondaryAction:
      return tint.opacity(0.05)
    case .info:
      return .clear
    }
  }

  private var shadowRadius: CGFloat {
    switch role {
    case .primaryAction: return 6
    case .secondaryAction: return 2
    case .info: return 0
    }
  }
}

private struct HostInlineChipBorder: View {
  let cornerRadius: CGFloat
  let staticOpacity: Double
  let lineWidth: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .stroke(Color.white.opacity(staticOpacity), lineWidth: lineWidth)
      .allowsHitTesting(false)
  }
}
