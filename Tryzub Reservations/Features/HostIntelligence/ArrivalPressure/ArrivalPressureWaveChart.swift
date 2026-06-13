//
//  ArrivalPressureWaveChart.swift
//  Tryzub Reservations
//
//  Service-pressure wave chart: smooth area curve + rounded bars.
//  Deterministic rendering — no LLM.
//

import SwiftUI
import OSLog

enum ArrivalPressureChartTrace {
  #if DEBUG
  private static let logger = Logger(
    subsystem: "Bohdan-Solovey.Tryzub-Reservations",
    category: "ArrivalPressure"
  )
  #endif

  static func render(
    bucketCount: Int,
    peak: String,
    pressureLevel: String,
    plotWidth: CGFloat,
    plotHeight: CGFloat
  ) {
    #if DEBUG
    logger.debug(
      "[ARRIVAL_PRESSURE_TRACE] buckets=\(bucketCount, privacy: .public) peak=\(peak, privacy: .public) level=\(pressureLevel, privacy: .public) plotWidth=\(Int(plotWidth), privacy: .public) plotHeight=\(Int(plotHeight), privacy: .public)"
    )
    #endif
  }
}

struct ArrivalPressureWaveChart: View {
  let summary: ArrivalPressureSummary
  var height: CGFloat = 108
  var isToday: Bool = true
  var now: Date = Date()
  var onOpenReservation: ((Int) -> Void)?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  @State private var revealProgress: CGFloat = 0
  @State private var peakPulse = false
  @State private var selectedBucketID: String?
  @State private var sheetBucket: ArrivalPressureBucket?
  @State private var measuredPlotWidth: CGFloat = 0
  @State private var clockNow = Date()

  private let leftGutter: CGFloat = 22
  private let bottomGutter: CGFloat = 14
  private let topGutter: CGFloat = 8
  private static let minChartHeight: CGFloat = 72

  private var buckets: [ArrivalPressureBucket] { summary.buckets }
  private var resolvedHeight: CGFloat { max(height, Self.minChartHeight) }

  private var chartSeriesKey: String {
    buckets.map { "\($0.id):\($0.pressureScore)" }.joined(separator: "|")
  }

  private var hasArrivals: Bool { summary.hasArrivals }

  private var nowBucketIndex: Int? {
    guard isToday else { return nil }
    return buckets.firstIndex { bucket in
      clockNow >= bucket.startTime && clockNow < bucket.endTime
    }
  }

  var body: some View {
    if !hasArrivals {
      emptyState
    } else {
      VStack(alignment: .leading, spacing: 6) {
        chartWithAxes
          .onAppear {
            clockNow = now
            playEntrance()
            traceRender()
          }
          .onChange(of: chartSeriesKey) { _, _ in
            selectedBucketID = nil
            sheetBucket = nil
            playEntrance()
            traceRender()
          }
          .onReceive(
            Timer.publish(every: 30, on: .main, in: .common).autoconnect()
          ) { tick in
            clockNow = tick
          }

        footerCaption
      }
      .sheet(item: $sheetBucket) { bucket in
        ArrivalPressureBucketSheet(
          bucket: bucket,
          onOpenReservation: { remoteID in
            sheetBucket = nil
            onOpenReservation?(remoteID)
          }
        )
      }
    }
  }

  private var emptyState: some View {
    HStack(spacing: 8) {
      Image(systemName: "waveform.path")
        .foregroundStyle(TryzubColors.mutedText)
      Text("No arrival pressure for this day.")
        .font(.caption.weight(.medium))
        .foregroundStyle(TryzubColors.mutedText)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
  }

  private var footerCaption: some View {
    Group {
      if let selected = selectedBucket {
        VStack(alignment: .leading, spacing: 2) {
          Text(bucketHeadline(selected))
            .font(.caption.weight(.semibold))
            .foregroundStyle(TryzubColors.primaryText)
          Text(bucketDetail(selected))
            .font(.caption2)
            .foregroundStyle(TryzubColors.mutedText)
        }
      } else {
        Text("Tap a wave to see who is coming.")
          .font(.caption2)
          .foregroundStyle(TryzubColors.mutedText)
      }
    }
  }

  private func bucketHeadline(_ bucket: ArrivalPressureBucket) -> String {
    let guests = bucket.guestCount == 1 ? "1 guest" : "\(bucket.guestCount) guests"
    return "\(bucket.windowLabel) · \(guests)"
  }

  private func bucketDetail(_ bucket: ArrivalPressureBucket) -> String {
    var parts: [String] = []
    let res = bucket.reservationCount == 1 ? "1 reservation" : "\(bucket.reservationCount) reservations"
    parts.append(res)
    if bucket.noTableCount > 0 {
      parts.append("\(bucket.noTableCount) need tables")
    }
    if bucket.largePartyCount > 0 {
      parts.append("\(bucket.largePartyCount) large \(bucket.largePartyCount == 1 ? "party" : "parties")")
    }
    return parts.joined(separator: " · ")
  }

  private func playEntrance() {
    peakPulse = false
    if reduceMotion {
      revealProgress = 1
      return
    }
    revealProgress = 0
    withAnimation(.easeOut(duration: 0.55)) { revealProgress = 1 }
    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { peakPulse = true }
  }

  private func traceRender() {
    ArrivalPressureChartTrace.render(
      bucketCount: buckets.count,
      peak: summary.peakBucket?.displayTime ?? "none",
      pressureLevel: summary.pressureLevel.displayName,
      plotWidth: measuredPlotWidth,
      plotHeight: resolvedHeight - bottomGutter
    )
  }

  // MARK: - Axes + Chart

  private var chartWithAxes: some View {
    HStack(alignment: .top, spacing: 4) {
      yAxisLabels
      VStack(spacing: 2) {
        chartBody
        xAxisLabels
      }
    }
  }

  private var yAxisLabels: some View {
    let plotHeight = resolvedHeight - bottomGutter - topGutter
    let ticks = [0, 50, 100].map { Int($0) }
    return ZStack(alignment: .topLeading) {
      ForEach(ticks.reversed(), id: \.self) { tick in
        if tick > 0 {
          Text("\(tick)%")
            .font(.system(size: 7, weight: .medium, design: .rounded))
            .foregroundStyle(TryzubColors.mutedText.opacity(0.7))
            .offset(y: yOffsetForNormalized(Double(tick) / 100.0, plotHeight: plotHeight))
        }
      }
    }
    .frame(width: leftGutter - 2, height: resolvedHeight, alignment: .topLeading)
    .accessibilityHidden(true)
  }

  private func yOffsetForNormalized(_ fraction: Double, plotHeight: CGFloat) -> CGFloat {
    topGutter + plotHeight * CGFloat(1 - fraction) - 5
  }

  private var xAxisLabels: some View {
    GeometryReader { proxy in
      let plotWidth = max(proxy.size.width, 1)
      ZStack(alignment: .topLeading) {
        ForEach(xLabelIndices, id: \.self) { index in
          Text(buckets[index].axisLabel.isEmpty
               ? buckets[index].displayTime
               : buckets[index].axisLabel)
            .font(.system(size: 8, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(TryzubColors.mutedText.opacity(0.9))
            .fixedSize()
            .position(x: centerX(index, plotWidth: plotWidth), y: 6)
        }
      }
    }
    .frame(height: bottomGutter)
    .accessibilityHidden(true)
  }

  private var labelStrideMinutes: Int {
    let isRegular = horizontalSizeClass == .regular
    let perBucket = buckets.isEmpty ? 0 : measuredPlotWidth / CGFloat(buckets.count)
    if perBucket >= 34 { return 15 }
    if isRegular || perBucket >= 22 { return 30 }
    return 60
  }

  private var xLabelIndices: [Int] {
    guard !buckets.isEmpty else { return [] }
    let stride = labelStrideMinutes
    let calendar = Calendar.current
    var indices: [Int] = []
    var lastKey: Int?
    for index in buckets.indices {
      let bucket = buckets[index]
      let hour = calendar.component(.hour, from: bucket.startTime)
      let minute = calendar.component(.minute, from: bucket.startTime)
      guard minute % stride == 0 else { continue }
      let key = hour * 60 + minute
      guard key != lastKey else { continue }
      indices.append(index)
      lastKey = key
    }
    if indices.count >= 2 { return indices }
    let fallback = max(buckets.count / 5, 1)
    return Array(Swift.stride(from: 0, to: buckets.count, by: fallback))
  }

  private var chartBody: some View {
    let plotHeight = max(resolvedHeight - bottomGutter, Self.minChartHeight - bottomGutter)
    let usableHeight = max(plotHeight - topGutter, 1)

    return GeometryReader { proxy in
      let plotWidth = max(proxy.size.width, 1)
      let barWidth = self.barWidth(plotWidth: plotWidth)

      ZStack(alignment: .bottomLeading) {
        baselineRule(plotWidth: plotWidth, plotHeight: plotHeight)

        if plotWidth > 1 {
          // Wave fill
          wavePath(plotWidth: plotWidth, usableHeight: usableHeight, plotHeight: plotHeight)
            .fill(
              LinearGradient(
                colors: [
                  TryzubColors.primaryControl.opacity(0.22),
                  TryzubColors.primaryControl.opacity(0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
              )
            )
            .opacity(Double(revealProgress) * 0.85)
            .allowsHitTesting(false)

          // Wave stroke
          wavePath(plotWidth: plotWidth, usableHeight: usableHeight, plotHeight: plotHeight)
            .stroke(TryzubColors.primaryControl.opacity(0.35), lineWidth: 1.2)
            .opacity(Double(revealProgress))
            .allowsHitTesting(false)

          // Current-time marker
          if let nowIndex = nowBucketIndex {
            nowMarker(index: nowIndex, plotWidth: plotWidth, plotHeight: plotHeight)
          }

          // Bars
          ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
            barView(
              bucket: bucket,
              index: index,
              plotWidth: plotWidth,
              plotHeight: plotHeight,
              usableHeight: usableHeight,
              barWidth: barWidth
            )
          }
        }
      }
      .frame(width: plotWidth, height: plotHeight, alignment: .bottomLeading)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onEnded { value in
            selectBucket(at: value.location.x, plotWidth: plotWidth)
          }
      )
      .onAppear { measuredPlotWidth = plotWidth }
      .onChange(of: plotWidth) { _, w in measuredPlotWidth = w }
    }
    .frame(height: plotHeight)
  }

  private func wavePath(plotWidth: CGFloat, usableHeight: CGFloat, plotHeight: CGFloat) -> Path {
    var path = Path()
    guard buckets.count > 1 else { return path }

    let points: [CGPoint] = buckets.indices.map { index in
      let bucket = buckets[index]
      let x = centerX(index, plotWidth: plotWidth)
      let h = usableHeight * CGFloat(bucket.normalizedPressure) * revealProgress
      let y = plotHeight - h
      return CGPoint(x: x, y: y)
    }

    guard let first = points.first else { return path }
    path.move(to: CGPoint(x: first.x, y: plotHeight))
    path.addLine(to: first)

    for index in 1..<points.count {
      let prev = points[index - 1]
      let curr = points[index]
      let midX = (prev.x + curr.x) / 2
      path.addCurve(
        to: curr,
        control1: CGPoint(x: midX, y: prev.y),
        control2: CGPoint(x: midX, y: curr.y)
      )
    }

    if let last = points.last {
      path.addLine(to: CGPoint(x: last.x, y: plotHeight))
    }
    path.closeSubpath()
    return path
  }

  private func nowMarker(index: Int, plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
    let x = centerX(index, plotWidth: plotWidth)
    return Rectangle()
      .fill(Color.accentColor.opacity(0.45))
      .frame(width: 1, height: plotHeight - topGutter)
      .position(x: x, y: plotHeight / 2)
      .allowsHitTesting(false)
  }

  @ViewBuilder
  private func barView(
    bucket: ArrivalPressureBucket,
    index: Int,
    plotWidth: CGFloat,
    plotHeight: CGFloat,
    usableHeight: CGFloat,
    barWidth: CGFloat
  ) -> some View {
    let pressureHeight = max(usableHeight * CGFloat(bucket.normalizedPressure), bucket.hasArrivals ? 6 : 2)
    let animatedHeight = pressureHeight * revealProgress
    let isSelected = selectedBucketID == bucket.id
    let centerX = centerX(index, plotWidth: plotWidth)

    let opacity: Double = {
      if bucket.isPast { return 0.38 }
      if bucket.isNextArrival { return 1.0 }
      return 0.82
    }()

    let tint: Color = {
      if !bucket.hasArrivals { return TryzubColors.border.opacity(0.4) }
      if bucket.isPeak { return TryzubColors.primaryControl }
      if bucket.noTableCount > 0 { return TryzubColors.warning.opacity(0.85) }
      return TryzubColors.primaryControl.opacity(0.72)
    }()

    ZStack(alignment: .bottom) {
      Capsule()
        .fill(tint.opacity(opacity))
        .frame(width: barWidth, height: animatedHeight)
        .overlay {
          if isSelected {
            Capsule()
              .stroke(TryzubColors.primaryControl, lineWidth: 1.5)
              .frame(width: barWidth, height: animatedHeight)
          }
        }
        .scaleEffect(
          x: 1,
          y: bucket.isPeak && peakPulse && !reduceMotion && !isSelected ? 1.05 : 1,
          anchor: .bottom
        )

      if bucket.hasArrivals {
        Text("\(bucket.guestCount)")
          .font(.system(size: 8, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(bucket.isPeak ? TryzubColors.primaryControl : TryzubColors.mutedText)
          .opacity(Double(revealProgress) * (bucket.isPast ? 0.5 : 1))
          .offset(y: -(animatedHeight + 7))
      }
    }
    .frame(width: barWidth, height: plotHeight, alignment: .bottom)
    .position(x: centerX, y: plotHeight / 2)
    .accessibilityLabel(accessibilityLabel(for: bucket))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func accessibilityLabel(for bucket: ArrivalPressureBucket) -> String {
    var parts = [bucket.windowLabel]
    parts.append(bucket.guestCount == 1 ? "1 guest" : "\(bucket.guestCount) guests")
    if bucket.isPeak { parts.insert("Peak pressure", at: 0) }
    if bucket.noTableCount > 0 {
      parts.append("\(bucket.noTableCount) without tables")
    }
    return parts.joined(separator: ", ")
  }

  private func baselineRule(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
    Rectangle()
      .fill(TryzubColors.border.opacity(0.4))
      .frame(width: plotWidth, height: 0.75)
      .position(x: plotWidth / 2, y: plotHeight - 0.5)
      .allowsHitTesting(false)
  }

  private func barWidth(plotWidth: CGFloat) -> CGFloat {
    guard buckets.count > 0 else { return 6 }
    let slot = plotWidth / CGFloat(buckets.count)
    return min(max(slot * 0.55, 4), 20)
  }

  private func centerX(_ index: Int, plotWidth: CGFloat) -> CGFloat {
    guard buckets.count > 1 else { return plotWidth / 2 }
    let slot = plotWidth / CGFloat(buckets.count)
    return slot * (CGFloat(index) + 0.5)
  }

  private var selectedBucket: ArrivalPressureBucket? {
    guard let selectedBucketID else { return nil }
    return buckets.first(where: { $0.id == selectedBucketID })
  }

  private func selectBucket(at x: CGFloat, plotWidth: CGFloat) {
    guard !buckets.isEmpty else { return }
    let nearestIndex = buckets.indices.min(by: { lhs, rhs in
      abs(centerX(lhs, plotWidth: plotWidth) - x) < abs(centerX(rhs, plotWidth: plotWidth) - x)
    })
    guard let nearestIndex else { return }
    let bucket = buckets[nearestIndex]
    guard bucket.hasArrivals else { return }

    selectedBucketID = bucket.id
    sheetBucket = bucket
  }
}

// Make bucket identifiable for sheet
extension ArrivalPressureBucket: Hashable {
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
