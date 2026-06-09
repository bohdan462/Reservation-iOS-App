//
//  TryzubEngineWelcomeScene.swift
//  Tryzub Reservations
//
//  Cinematic “operational engine” visuals for first launch.
//

import SwiftUI

// MARK: - Backdrop

struct EngineWelcomeBackdrop: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1 / 24)) { timeline in
      let phase = reduceMotion ? 0.5 : timeline.date.timeIntervalSinceReferenceDate

      ZStack {
        LinearGradient(
          colors: [
            Color(red: 0.02, green: 0.04, blue: 0.11),
            Color(red: 0.04, green: 0.07, blue: 0.16),
            Color(red: 0.01, green: 0.02, blue: 0.08)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )

        if #available(iOS 18.0, *) {
          MeshGradient(
            width: 3,
            height: 3,
            points: [
              .init(0, 0), .init(0.5, 0), .init(1, 0),
              .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
              .init(0, 1), .init(0.5, 1), .init(1, 1)
            ],
            colors: meshColors(phase: phase)
          )
          .opacity(0.55)
          .blur(radius: 28)
        }

        driftingOrb(
          color: Color.accentColor.opacity(0.34),
          size: 320,
          x: -80 + CGFloat(sin(phase * 0.35)) * 24,
          y: -220 + CGFloat(cos(phase * 0.28)) * 18
        )

        driftingOrb(
          color: Color.cyan.opacity(0.16),
          size: 260,
          x: 120 + CGFloat(cos(phase * 0.22)) * 20,
          y: 240 + CGFloat(sin(phase * 0.31)) * 16
        )

        RadialGradient(
          colors: [
            Color.clear,
            Color.black.opacity(0.45)
          ],
          center: .center,
          startRadius: 80,
          endRadius: 420
        )
      }
    }
    .ignoresSafeArea()
  }

  private func driftingOrb(color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
    Circle()
      .fill(color)
      .frame(width: size, height: size)
      .blur(radius: 70)
      .offset(x: x, y: y)
  }

  @available(iOS 18.0, *)
  private func meshColors(phase: TimeInterval) -> [Color] {
    let pulse = (sin(phase * 0.55) + 1) / 2
    let accent = Color.accentColor.opacity(0.22 + pulse * 0.14)
    let deep = Color(red: 0.03, green: 0.06, blue: 0.14)
    let mid = Color(red: 0.06, green: 0.10, blue: 0.22)
    return [
      deep, mid.opacity(0.9), deep,
      mid, accent, mid.opacity(0.85),
      deep, mid, deep
    ]
  }
}

// MARK: - Viewport

struct EngineWelcomeViewport: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var breathe = false

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 36, style: .continuous)
        .fill(Color.white.opacity(0.035))

      EngineWaveSilhouette(reduceMotion: reduceMotion)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .opacity(0.9)

      EngineOrbitRings(reduceMotion: reduceMotion)

      ZStack {
        if !reduceMotion {
          Circle()
            .fill(Color.accentColor.opacity(0.16))
            .frame(width: breathe ? 120 : 88, height: breathe ? 120 : 88)
            .blur(radius: 22)
            .opacity(breathe ? 0.55 : 0.25)
        }

        HostPulseIcon(isActive: true, size: 30)
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: 36, style: .continuous)
        .stroke(
          LinearGradient(
            colors: [
              Color.white.opacity(0.34),
              Color.accentColor.opacity(0.42),
              Color.white.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 1
        )
    }
    .tryzubEngineGlass(cornerRadius: 36)
    .shadow(color: Color.accentColor.opacity(0.18), radius: 32, y: 18)
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
        breathe = true
      }
    }
  }
}

// MARK: - Wave silhouette

private struct EngineWaveSilhouette: View {
  let reduceMotion: Bool

  private let wavePoints: [CGFloat] = [0.08, 0.42, 0.22, 0.68, 0.38, 0.82, 0.55, 0.92]

  var body: some View {
    TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1 / 30)) { timeline in
      let phase = reduceMotion ? 1.0 : timeline.date.timeIntervalSinceReferenceDate
      Canvas { context, size in
        let points = wavePoints.enumerated().map { index, yFraction in
          let xFraction = CGFloat(index) / CGFloat(max(wavePoints.count - 1, 1))
          let wobble = reduceMotion ? 0 : CGFloat(sin(phase * 1.1 + Double(index) * 0.7)) * 0.04
          return CGPoint(
            x: xFraction * size.width,
            y: (yFraction + wobble) * size.height
          )
        }

        var area = engineSmoothPath(through: points)
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.addLine(to: CGPoint(x: 0, y: size.height))
        area.closeSubpath()

        context.fill(
          area,
          with: .linearGradient(
            Gradient(colors: [
              Color.accentColor.opacity(0.22),
              Color.accentColor.opacity(0.02)
            ]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
          )
        )

        let stroke = engineSmoothPath(through: points)
        context.stroke(
          stroke,
          with: .color(Color.accentColor.opacity(0.55)),
          style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        )

        for (index, point) in points.enumerated() where index % 2 == 0 {
          let dot = CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)
          context.fill(Path(ellipseIn: dot), with: .color(Color.accentColor.opacity(0.7)))
        }
      }
    }
  }
}

// MARK: - Orbit rings

private struct EngineOrbitRings: View {
  let reduceMotion: Bool

  var body: some View {
    TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1 / 30)) { timeline in
      let t = timeline.date.timeIntervalSinceReferenceDate
      ZStack {
        orbitRing(size: CGSize(width: 220, height: 120), degrees: reduceMotion ? 0 : t * (360 / 28))
        orbitRing(size: CGSize(width: 170, height: 92), degrees: reduceMotion ? 0 : -t * (360 / 22))
        orbitRing(size: CGSize(width: 120, height: 64), degrees: reduceMotion ? 0 : t * (360 / 16))
      }
    }
  }

  private func orbitRing(size: CGSize, degrees: Double) -> some View {
    Ellipse()
      .stroke(
        AngularGradient(
          colors: [
            Color.accentColor.opacity(0.02),
            Color.accentColor.opacity(0.28),
            Color.white.opacity(0.12),
            Color.accentColor.opacity(0.02)
          ],
          center: .center
        ),
        style: StrokeStyle(lineWidth: 0.8, dash: [5, 7])
      )
      .frame(width: size.width, height: size.height)
      .rotationEffect(.degrees(degrees))
  }
}

// MARK: - Glass + path

extension View {
  @ViewBuilder
  func tryzubEngineGlass(cornerRadius: CGFloat) -> some View {
    if #available(iOS 26.0, *) {
      self
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
    } else {
      self
        .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
  }
}

private func engineSmoothPath(through points: [CGPoint]) -> Path {
  guard points.count > 1 else { return Path() }
  var path = Path()
  path.move(to: points[0])
  for index in 1..<points.count {
    let previous = points[index - 1]
    let current = points[index]
    let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
    if index == 1 {
      path.addLine(to: midpoint)
    } else {
      path.addQuadCurve(to: midpoint, control: previous)
    }
  }
  if let last = points.last {
    path.addLine(to: last)
  }
  return path
}
