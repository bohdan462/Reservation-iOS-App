//
//  PrivacyCoverAuroraBackground.swift
//  Tryzub Reservations
//
//  Animated aurora backdrop for the iPad privacy saver screen.
//

import SwiftUI

// MARK: - Aurora Background

struct PrivacyCoverAuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private let blurRadius: CGFloat = 38

    var body: some View {
        GeometryReader { proxy in
            Group {
                if differentiateWithoutColor {
                    PrivacyCoverAuroraTheme.differentiateWithoutColorBackground(for: colorScheme)
                } else if reduceTransparency {
                    PrivacyCoverAuroraTheme.staticGradient(for: colorScheme)
                } else {
                    animatedAurora(in: proxy)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func animatedAurora(in proxy: GeometryProxy) -> some View {
        ZStack {
            PrivacyCoverAuroraTheme.generalBackground(for: colorScheme)

            ZStack {
                // Dominant blue family — one tone per quadrant
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesBottomTrailing(for: colorScheme),
                    rotationStart: 0,
                    duration: 26,
                    driftPeriod: 9,
                    anchor: .bottomTrailing,
                    sizeMultiplier: 1.06,
                    animate: !reduceMotion
                )
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesTopTrailing(for: colorScheme),
                    rotationStart: 240,
                    duration: 22,
                    driftPeriod: 7.5,
                    anchor: .topTrailing,
                    sizeMultiplier: 1.02,
                    animate: !reduceMotion
                )
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesBottomLeading(for: colorScheme),
                    rotationStart: 120,
                    duration: 34,
                    driftPeriod: 11,
                    anchor: .bottomLeading,
                    sizeMultiplier: 0.98,
                    animate: !reduceMotion
                )
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesTopLeading(for: colorScheme),
                    rotationStart: 180,
                    duration: 30,
                    driftPeriod: 8.5,
                    anchor: .topLeading,
                    sizeMultiplier: 1.04,
                    animate: !reduceMotion
                )

                // Secondary blue wash — extra depth between quadrants
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesMidBlue(for: colorScheme),
                    rotationStart: 55,
                    duration: 28,
                    driftPeriod: 10,
                    anchor: .center,
                    sizeMultiplier: 0.88,
                    animate: !reduceMotion
                )

                // Yellow accents — smaller, softer
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesSunGold(for: colorScheme),
                    rotationStart: 40,
                    duration: 20,
                    driftPeriod: 6.5,
                    anchor: UnitPoint(x: 0.58, y: 0.34),
                    sizeMultiplier: 0.48,
                    opacity: 0.54,
                    animate: !reduceMotion
                )
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesSunHoney(for: colorScheme),
                    rotationStart: 310,
                    duration: 24,
                    driftPeriod: 8,
                    anchor: UnitPoint(x: 0.36, y: 0.62),
                    sizeMultiplier: 0.42,
                    opacity: 0.46,
                    animate: !reduceMotion
                )
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesSunPale(for: colorScheme),
                    rotationStart: 140,
                    duration: 32,
                    driftPeriod: 9.5,
                    anchor: UnitPoint(x: 0.72, y: 0.58),
                    sizeMultiplier: 0.38,
                    opacity: 0.40,
                    animate: !reduceMotion
                )
            }
            .blur(radius: blurRadius)
        }
    }
}

// MARK: - Cloud

private final class PrivacyAuroraCloudProvider: ObservableObject {
    let offset: CGSize
    let frameHeightRatio: CGFloat

    init() {
        frameHeightRatio = CGFloat.random(in: 0.52 ... 0.92)
        offset = CGSize(
            width: CGFloat.random(in: -190 ... 190),
            height: CGFloat.random(in: -190 ... 190)
        )
    }
}

private struct PrivacyAuroraCloud: View {
    @StateObject private var provider = PrivacyAuroraCloudProvider()

    let size: CGSize
    let color: Color
    let rotationStart: Double
    let duration: Double
    let driftPeriod: Double
    let anchor: UnitPoint
    var sizeMultiplier: CGFloat = 1
    var opacity: CGFloat = 0.88
    let animate: Bool

    private var cloudDiameter: CGFloat {
        let base = max(size.width, size.height, 360)
        return (base / provider.frameHeightRatio) * sizeMultiplier
    }

    var body: some View {
        Group {
            if animate {
                TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { context in
                    cloudBody(
                        rotationDegrees: rotationStart + rotationProgress(at: context.date) * 360,
                        drift: driftOffset(at: context.date)
                    )
                }
            } else {
                cloudBody(rotationDegrees: rotationStart, drift: .zero)
            }
        }
    }

    private func rotationProgress(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
        return elapsed.truncatingRemainder(dividingBy: duration) / duration
    }

    private func driftOffset(at date: Date) -> CGSize {
        let elapsed = date.timeIntervalSinceReferenceDate
        let phase = elapsed / driftPeriod
        return CGSize(
            width: cos(phase * .pi * 2) * 52,
            height: sin(phase * .pi * 2) * 44
        )
    }

    private func cloudBody(rotationDegrees: Double, drift: CGSize) -> some View {
        GeometryReader { geo in
            Circle()
                .fill(color)
                .frame(width: cloudDiameter, height: cloudDiameter)
                .offset(
                    x: provider.offset.width + drift.width,
                    y: provider.offset.height + drift.height
                )
                .rotationEffect(.degrees(rotationDegrees))
                .position(
                    x: geo.size.width * anchor.x,
                    y: geo.size.height * anchor.y
                )
                .opacity(opacity)
        }
    }
}

// MARK: - Theme

private enum PrivacyCoverAuroraTheme {
    static func generalBackground(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.88, green: 0.92, blue: 0.99)
        case .dark:
            return Color(red: 0.02, green: 0.05, blue: 0.11)
        @unknown default:
            return Color(red: 0.02, green: 0.05, blue: 0.11)
        }
    }

    // MARK: Blue tones (dominant)

    /// Deep ocean — top leading
    static func ellipsesTopLeading(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.03, green: 0.30, blue: 0.68, opacity: 0.82)
        case .dark:
            return Color(red: 0.00, green: 0.18, blue: 0.44, opacity: 0.88)
        @unknown default:
            return Color(red: 0.00, green: 0.18, blue: 0.44, opacity: 0.88)
        }
    }

    /// Royal bright — top trailing
    static func ellipsesTopTrailing(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.14, green: 0.44, blue: 0.94, opacity: 0.76)
        case .dark:
            return Color(red: 0.10, green: 0.34, blue: 0.82, opacity: 0.82)
        @unknown default:
            return Color(red: 0.10, green: 0.34, blue: 0.82, opacity: 0.82)
        }
    }

    /// Powder periwinkle — bottom trailing
    static func ellipsesBottomTrailing(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.48, green: 0.66, blue: 0.96, opacity: 0.72)
        case .dark:
            return Color(red: 0.24, green: 0.40, blue: 0.78, opacity: 0.78)
        @unknown default:
            return Color(red: 0.24, green: 0.40, blue: 0.78, opacity: 0.78)
        }
    }

    /// Teal-cyan — bottom leading
    static func ellipsesBottomLeading(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.08, green: 0.52, blue: 0.78, opacity: 0.68)
        case .dark:
            return Color(red: 0.06, green: 0.40, blue: 0.62, opacity: 0.74)
        @unknown default:
            return Color(red: 0.06, green: 0.40, blue: 0.62, opacity: 0.74)
        }
    }

    /// Mid wash — bridges quadrants
    static func ellipsesMidBlue(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.22, green: 0.56, blue: 0.92, opacity: 0.58)
        case .dark:
            return Color(red: 0.14, green: 0.42, blue: 0.76, opacity: 0.64)
        @unknown default:
            return Color(red: 0.14, green: 0.42, blue: 0.76, opacity: 0.64)
        }
    }

    // MARK: Yellow tones (accent)

    /// Warm gold
    static func ellipsesSunGold(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 1.00, green: 0.82, blue: 0.20, opacity: 0.56)
        case .dark:
            return Color(red: 1.00, green: 0.76, blue: 0.12, opacity: 0.60)
        @unknown default:
            return Color(red: 1.00, green: 0.76, blue: 0.12, opacity: 0.60)
        }
    }

    /// Honey amber
    static func ellipsesSunHoney(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.98, green: 0.70, blue: 0.22, opacity: 0.50)
        case .dark:
            return Color(red: 0.94, green: 0.62, blue: 0.16, opacity: 0.54)
        @unknown default:
            return Color(red: 0.94, green: 0.62, blue: 0.16, opacity: 0.54)
        }
    }

    /// Pale sunshine
    static func ellipsesSunPale(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 1.00, green: 0.90, blue: 0.52, opacity: 0.44)
        case .dark:
            return Color(red: 0.98, green: 0.84, blue: 0.42, opacity: 0.48)
        @unknown default:
            return Color(red: 0.98, green: 0.84, blue: 0.42, opacity: 0.48)
        }
    }

    static func staticGradient(for scheme: ColorScheme) -> some View {
        LinearGradient(
            colors: [
                ellipsesTopLeading(for: scheme),
                ellipsesTopTrailing(for: scheme),
                ellipsesMidBlue(for: scheme),
                ellipsesBottomLeading(for: scheme),
                ellipsesBottomTrailing(for: scheme),
                ellipsesSunGold(for: scheme),
                ellipsesSunHoney(for: scheme),
                ellipsesSunPale(for: scheme)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func differentiateWithoutColorBackground(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(white: 0.95)
        case .dark:
            return Color(white: 0.18)
        @unknown default:
            return Color(white: 0.18)
        }
    }
}

#if DEBUG
#Preview("Privacy Aurora") {
    PrivacyCoverAuroraBackground()
}
#endif
