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
                } else if colorScheme == .dark {
                    classicAnimatedAurora(in: proxy)
                } else {
                    lightBlueYellowAnimatedAurora(in: proxy)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    /// Original teal / green / cyan / blue aurora — used in dark mode.
    @ViewBuilder
    private func classicAnimatedAurora(in proxy: GeometryProxy) -> some View {
        ZStack {
            PrivacyCoverAuroraTheme.classicGeneralBackground(for: colorScheme)

            ZStack {
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.classicTopLeading(for: colorScheme),
                    rotationStart: 180,
                    duration: 30,
                    driftPeriod: 8.5,
                    anchor: .topLeading,
                    sizeMultiplier: 1.04,
                    animate: !reduceMotion
                )
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.classicTopTrailing(for: colorScheme),
                    rotationStart: 240,
                    duration: 22,
                    driftPeriod: 7.5,
                    anchor: .topTrailing,
                    sizeMultiplier: 1.02,
                    animate: !reduceMotion
                )
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.classicBottomTrailing(for: colorScheme),
                    rotationStart: 0,
                    duration: 26,
                    driftPeriod: 9,
                    anchor: .bottomTrailing,
                    sizeMultiplier: 1.06,
                    animate: !reduceMotion
                )
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.classicBottomLeading(for: colorScheme),
                    rotationStart: 120,
                    duration: 34,
                    driftPeriod: 11,
                    anchor: .bottomLeading,
                    sizeMultiplier: 0.98,
                    animate: !reduceMotion
                )
            }
            .blur(radius: blurRadius)
        }
    }

    /// Multi-tone blue + yellow aurora — light mode only.
    @ViewBuilder
    private func lightBlueYellowAnimatedAurora(in proxy: GeometryProxy) -> some View {
        ZStack {
            PrivacyCoverAuroraTheme.lightGeneralBackground()

            ZStack {
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesBottomTrailing(for: .light),
                    rotationStart: 0,
                    duration: 26,
                    driftPeriod: 9,
                    anchor: .bottomTrailing,
                    sizeMultiplier: 1.06,
                    animate: !reduceMotion
                )
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesTopTrailing(for: .light),
                    rotationStart: 240,
                    duration: 22,
                    driftPeriod: 7.5,
                    anchor: .topTrailing,
                    sizeMultiplier: 1.02,
                    animate: !reduceMotion
                )
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesBottomLeading(for: .light),
                    rotationStart: 120,
                    duration: 34,
                    driftPeriod: 11,
                    anchor: .bottomLeading,
                    sizeMultiplier: 0.98,
                    animate: !reduceMotion
                )
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesTopLeading(for: .light),
                    rotationStart: 180,
                    duration: 30,
                    driftPeriod: 8.5,
                    anchor: .topLeading,
                    sizeMultiplier: 1.04,
                    animate: !reduceMotion
                )
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesMidBlue(for: .light),
                    rotationStart: 55,
                    duration: 28,
                    driftPeriod: 10,
                    anchor: .center,
                    sizeMultiplier: 0.88,
                    animate: !reduceMotion
                )
                PrivacyAuroraCloud(
                    size: proxy.size,
                    color: PrivacyCoverAuroraTheme.ellipsesSunGold(for: .light),
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
                    color: PrivacyCoverAuroraTheme.ellipsesSunHoney(for: .light),
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
                    color: PrivacyCoverAuroraTheme.ellipsesSunPale(for: .light),
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
    // MARK: Classic aurora (dark mode — original Cephalopod-style palette)

    static func classicGeneralBackground(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.86, green: 0.93, blue: 0.97)
        case .dark:
            return Color(red: 0.02, green: 0.08, blue: 0.14)
        @unknown default:
            return Color(red: 0.02, green: 0.08, blue: 0.14)
        }
    }

    static func classicTopLeading(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.04, green: 0.42, blue: 0.58, opacity: 0.72)
        case .dark:
            return Color(red: 0.00, green: 0.34, blue: 0.52, opacity: 0.82)
        @unknown default:
            return Color(red: 0.00, green: 0.34, blue: 0.52, opacity: 0.82)
        }
    }

    static func classicTopTrailing(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.18, green: 0.72, blue: 0.46, opacity: 0.55)
        case .dark:
            return Color(red: 0.28, green: 0.62, blue: 0.44, opacity: 0.62)
        @unknown default:
            return Color(red: 0.28, green: 0.62, blue: 0.44, opacity: 0.62)
        }
    }

    static func classicBottomTrailing(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.38, green: 0.58, blue: 0.92, opacity: 0.62)
        case .dark:
            return Color(red: 0.22, green: 0.40, blue: 0.78, opacity: 0.68)
        @unknown default:
            return Color(red: 0.22, green: 0.40, blue: 0.78, opacity: 0.68)
        }
    }

    static func classicBottomLeading(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.14, green: 0.62, blue: 0.72, opacity: 0.58)
        case .dark:
            return Color(red: 0.42, green: 0.72, blue: 0.78, opacity: 0.52)
        @unknown default:
            return Color(red: 0.42, green: 0.72, blue: 0.78, opacity: 0.52)
        }
    }

    // MARK: Light-mode blue + yellow palette

    static func lightGeneralBackground() -> Color {
        Color(red: 0.88, green: 0.92, blue: 0.99)
    }

    static func ellipsesTopLeading(for scheme: ColorScheme) -> Color {
        Color(red: 0.03, green: 0.30, blue: 0.68, opacity: 0.82)
    }

    static func ellipsesTopTrailing(for scheme: ColorScheme) -> Color {
        Color(red: 0.14, green: 0.44, blue: 0.94, opacity: 0.76)
    }

    static func ellipsesBottomTrailing(for scheme: ColorScheme) -> Color {
        Color(red: 0.48, green: 0.66, blue: 0.96, opacity: 0.72)
    }

    static func ellipsesBottomLeading(for scheme: ColorScheme) -> Color {
        Color(red: 0.08, green: 0.52, blue: 0.78, opacity: 0.68)
    }

    static func ellipsesMidBlue(for scheme: ColorScheme) -> Color {
        Color(red: 0.22, green: 0.56, blue: 0.92, opacity: 0.58)
    }

    static func ellipsesSunGold(for scheme: ColorScheme) -> Color {
        Color(red: 1.00, green: 0.82, blue: 0.20, opacity: 0.56)
    }

    static func ellipsesSunHoney(for scheme: ColorScheme) -> Color {
        Color(red: 0.98, green: 0.70, blue: 0.22, opacity: 0.50)
    }

    static func ellipsesSunPale(for scheme: ColorScheme) -> Color {
        Color(red: 1.00, green: 0.90, blue: 0.52, opacity: 0.44)
    }

    @ViewBuilder
    static func staticGradient(for scheme: ColorScheme) -> some View {
        if scheme == .dark {
            LinearGradient(
                colors: [
                    classicTopLeading(for: scheme),
                    classicTopTrailing(for: scheme),
                    classicBottomLeading(for: scheme),
                    classicBottomTrailing(for: scheme)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
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
