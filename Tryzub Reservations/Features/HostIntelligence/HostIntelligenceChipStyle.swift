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
  func hostIntelligenceCompactPanel(cornerRadius: CGFloat) -> some View {
    background {
      Group {
        if #available(iOS 26.0, *) {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
        } else {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground).opacity(0.96))
        }
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
    }
  }

  func hostIntelligenceCompactCapsule(strokeOpacity: Double) -> some View {
    background(Color(.tertiarySystemGroupedBackground).opacity(0.92), in: Capsule())
      .overlay {
        Capsule()
          .strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 0.65)
      }
  }

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
      .overlay {
        HostInlineChipBorder(
          cornerRadius: cornerRadius,
          staticOpacity: staticBorderOpacity,
          lineWidth: lineWidth
        )
      }
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
      return AnyShapeStyle(tint.opacity(0.10))
    case .secondaryAction:
      return AnyShapeStyle(tint.opacity(0.055))
    case .info:
      return AnyShapeStyle(Color(.tertiarySystemGroupedBackground).opacity(0.90))
    }
  }

  private var staticBorderOpacity: Double {
    switch role {
    case .primaryAction: return 0.22
    case .secondaryAction: return 0.13
    case .info: return 0.05
    }
  }

  private var lineWidth: CGFloat {
    switch role {
    case .primaryAction: return 1.15
    case .secondaryAction: return 0.75
    case .info: return 0.55
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
