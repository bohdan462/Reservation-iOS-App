//
//  ReservationDensityWaveChart.swift
//  Tryzub Reservations
//
//  15-minute arrival flow chart for the Host/Home service tab.
//
//  Renders compact rounded bars per 15-minute window. A single busy window
//  (e.g. 4 guests at 19:30 with empty surrounding buckets) renders as one clear
//  bar rather than a lonely floating dot over an empty plot.
//

import SwiftUI
import OSLog

enum ReservationDensityCalculator {
  static func bucketStart(for reservation: ReservationRecord, calendar: Calendar = .current) -> Date? {
    ArrivalFlowBucketBuilder.bucketStart(for: reservation, calendar: calendar)
  }

  static func bucketStart(for date: Date, calendar: Calendar = .current) -> Date {
    ArrivalFlowBucketBuilder.bucketStart(for: date, calendar: calendar)
  }

  static func compactAxisLabel(for date: Date, calendar: Calendar) -> String {
    let hour = calendar.component(.hour, from: date)
    let minute = calendar.component(.minute, from: date)
    if minute == 0 {
      return String(format: "%02d:00", hour)
    }
    return String(format: "%02d:%02d", hour, minute)
  }
}

enum ArrivalChartTrace {
  #if DEBUG
  private static let logger = Logger(
    subsystem: "Bohdan-Solovey.Tryzub-Reservations",
    category: "ArrivalChart"
  )
  #endif

  static func render(
    bucketCount: Int,
    arrivalCount: Int,
    peak: String,
    renderer: String,
    widthClass: String,
    labelStrideMinutes: Int,
    plotWidth: CGFloat,
    plotHeight: CGFloat,
    fallback: Bool
  ) {
    #if DEBUG
    logger.debug(
      "[ARRIVAL_CHART_TRACE] buckets=\(bucketCount, privacy: .public) arrivals=\(arrivalCount, privacy: .public) peak=\(peak, privacy: .public) renderer=\(renderer, privacy: .public) widthClass=\(widthClass, privacy: .public) labelStride=\(labelStrideMinutes, privacy: .public)min plotWidth=\(Int(plotWidth), privacy: .public) plotHeight=\(Int(plotHeight), privacy: .public) fallback=\(fallback ? "true" : "false", privacy: .public)"
    )
    #endif
  }
}

struct ReservationDensityWaveChart: View {
  let buckets: [ArrivalFlowBucket]
  var height: CGFloat = 96

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var revealProgress: CGFloat = 0
  @State private var peakPulse = false
  @State private var selectedBucketID: String?
  @State private var measuredPlotWidth: CGFloat = 0
  @State private var measuredPlotHeight: CGFloat = 0

  private let leftGutter: CGFloat = 22
  private let bottomGutter: CGFloat = 14
  private let topGutter: CGFloat = 6

  /// The plot must never render at zero height (which produced a
  /// "Failed to create NxN0 image slot" warning during tab transitions).
  private static let minChartHeight: CGFloat = 64

  private var resolvedHeight: CGFloat {
    max(height, Self.minChartHeight)
  }

  private var chartSeriesKey: String {
    buckets.map { "\($0.id):\($0.guestCount)" }.joined(separator: "|")
  }

  private var arrivalBuckets: [ArrivalFlowBucket] {
    buckets.filter(\.hasArrivals)
  }

  private var hasArrivals: Bool {
    !arrivalBuckets.isEmpty
  }

  private var maxGuests: Int {
    max(buckets.map(\.guestCount).max() ?? 0, 1)
  }

  private var yTicks: [Int] {
    // Cap visible ticks so the axis stays readable when a busy window is large.
    let top = maxGuests
    if top <= 4 {
      return Array(0...top)
    }
    let step = Int((Double(top) / 4).rounded(.up))
    var ticks = Array(stride(from: 0, through: top, by: max(step, 1)))
    if ticks.last != top { ticks.append(top) }
    return ticks
  }

  /// Adaptive x-axis label cadence in minutes. Data is always bucketed every 15 minutes;
  /// only the *labels* thin out so the axis never crowds. iPad (regular width) and wide
  /// plots can show 30-minute labels; iPhone (compact) stays hourly. Very wide plots with
  /// few buckets may even show every 15-minute bucket.
  private var labelStrideMinutes: Int {
    let isRegular = horizontalSizeClass == .regular
    // Approximate pixels available per 15-minute bucket.
    let perBucket = buckets.isEmpty ? 0 : measuredPlotWidth / CGFloat(buckets.count)

    if perBucket >= 34 {
      return 15
    }
    if isRegular || perBucket >= 22 {
      return 30
    }
    return 60
  }

  private var xLabelIndices: [Int] {
    guard !buckets.isEmpty else { return [] }

    let stride = labelStrideMinutes
    let calendar = Calendar.current
    var indices: [Int] = []
    var lastLabeledKey: Int?

    for index in buckets.indices {
      let bucket = buckets[index]
      let hour = calendar.component(.hour, from: bucket.bucketStart)
      let minute = calendar.component(.minute, from: bucket.bucketStart)
      guard minute % stride == 0 else { continue }
      // De-duplicate so identical hour:minute labels never stack.
      let key = hour * 60 + minute
      guard key != lastLabeledKey else { continue }
      indices.append(index)
      lastLabeledKey = key
    }

    if indices.count >= 2 {
      return indices
    }

    let fallbackStride = max(buckets.count / 5, 1)
    return Array(Swift.stride(from: 0, to: buckets.count, by: fallbackStride))
  }

  private var selectedBucket: ArrivalFlowBucket? {
    guard let selectedBucketID else { return nil }
    return buckets.first(where: { $0.id == selectedBucketID })
  }

  var body: some View {
    if !hasArrivals {
      HStack(spacing: 8) {
        Image(systemName: "clock")
          .foregroundStyle(TryzubColors.mutedText)
        Text("No arrivals for this day.")
          .font(.caption.weight(.medium))
          .foregroundStyle(TryzubColors.mutedText)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("No arrivals for this day.")
    } else {
      VStack(alignment: .leading, spacing: 6) {
        chartWithAxes
          .onAppear {
            playChartEntrance()
            traceRender()
          }
          .onChange(of: chartSeriesKey) { _, _ in
            selectedBucketID = nil
            playChartEntrance()
            traceRender()
          }

        footerCaption
          .padding(.bottom, 2)
      }
      .accessibilityElement(children: .contain)
    }
  }

  private func traceRender() {
    let peak = ArrivalFlowBucketBuilder.peakBucket(in: buckets)
    let resolvedPlotHeight = measuredPlotHeight > 0
      ? measuredPlotHeight
      : (resolvedHeight - bottomGutter)
    ArrivalChartTrace.render(
      bucketCount: buckets.count,
      arrivalCount: arrivalBuckets.count,
      peak: peak?.displayTime ?? "none",
      renderer: "rounded_bars",
      widthClass: horizontalSizeClass == .regular ? "regular" : "compact",
      labelStrideMinutes: labelStrideMinutes,
      plotWidth: measuredPlotWidth,
      plotHeight: resolvedPlotHeight,
      fallback: resolvedPlotHeight < 1 || measuredPlotWidth < 1
    )
  }

  @ViewBuilder
  private var footerCaption: some View {
    if let selectedBucket {
      let summary = ArrivalFlowBucketBuilder.selectedSummary(for: selectedBucket)
      VStack(alignment: .leading, spacing: 2) {
        Text(summary.headline)
          .font(.caption.weight(.semibold))
          .foregroundStyle(TryzubColors.primaryText)
        if let detail = summary.detail {
          Text(detail)
            .font(.caption2)
            .foregroundStyle(TryzubColors.mutedText)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(ArrivalFlowBucketBuilder.accessibilityLabel(for: selectedBucket))
    } else {
      Text("Tap a bar to see who is coming.")
        .font(.caption2)
        .foregroundStyle(TryzubColors.mutedText)
        .accessibilityHidden(true)
    }
  }

  private func playChartEntrance() {
    peakPulse = false
    if reduceMotion {
      revealProgress = 1
      return
    }

    revealProgress = 0
    withAnimation(.easeOut(duration: 0.55)) {
      revealProgress = 1
    }
    withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) {
      peakPulse = true
    }
  }

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
    let resolvedHeight = height.tryzubFinitePositiveLayoutValue
    let plotHeight = max(resolvedHeight - bottomGutter - topGutter, 1)
    return ZStack(alignment: .topLeading) {
      ForEach(yTicks.reversed(), id: \.self) { tick in
        Text("\(tick)")
          .font(.system(size: 8, weight: .medium, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(TryzubColors.mutedText.opacity(0.85))
          .offset(y: yOffset(for: tick, plotHeight: plotHeight))
      }
    }
    .frame(width: leftGutter - 2, height: resolvedHeight, alignment: .topLeading)
    .accessibilityHidden(true)
  }

  private func yOffset(for tick: Int, plotHeight: CGFloat) -> CGFloat {
    let fraction = CGFloat.tryzubSafeRatio(
      numerator: CGFloat(maxGuests - tick),
      denominator: CGFloat(max(maxGuests, 1))
    )
    return topGutter + plotHeight * fraction - 5
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
            .position(x: barCenterX(index, plotWidth: plotWidth), y: 6)
        }
      }
    }
    .frame(height: bottomGutter)
    .accessibilityHidden(true)
  }

  private var chartBody: some View {
    let chartMaxGuests = maxGuests
    let plotHeight = max(resolvedHeight.tryzubFinitePositiveLayoutValue - bottomGutter, Self.minChartHeight - bottomGutter, 1)

    return GeometryReader { proxy in
      let plotWidth = max(proxy.size.width, 1)
      let usableHeight = max(plotHeight - topGutter, 1)
      let barWidth = barWidth(plotWidth: plotWidth)

      ZStack(alignment: .bottomLeading) {
        baselineRule(plotWidth: plotWidth, plotHeight: plotHeight)

        // Only draw bars when there is real plot area. A transient zero-width pass
        // (e.g. mid tab transition) renders just the baseline, never a 0-sized layer.
        if plotWidth > 1 {
          ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
            bar(
              for: bucket,
              index: index,
              plotWidth: plotWidth,
              plotHeight: plotHeight,
              usableHeight: usableHeight,
              barWidth: barWidth,
              chartMaxGuests: chartMaxGuests
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
      .onAppear { updateMeasured(width: plotWidth, height: plotHeight) }
      .onChange(of: plotWidth) { _, newWidth in updateMeasured(width: newWidth, height: plotHeight) }
    }
    .frame(height: plotHeight)
  }

  private func updateMeasured(width: CGFloat, height: CGFloat) {
    if abs(width - measuredPlotWidth) > 0.5 {
      measuredPlotWidth = width
    }
    if abs(height - measuredPlotHeight) > 0.5 {
      measuredPlotHeight = height
    }
  }

  @ViewBuilder
  private func baselineRule(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
    Rectangle()
      .fill(TryzubColors.border.opacity(0.4))
      .frame(width: plotWidth, height: 0.75)
      .position(x: plotWidth / 2, y: plotHeight - 0.5)
      .allowsHitTesting(false)
  }

  @ViewBuilder
  private func bar(
    for bucket: ArrivalFlowBucket,
    index: Int,
    plotWidth: CGFloat,
    plotHeight: CGFloat,
    usableHeight: CGFloat,
    barWidth: CGFloat,
    chartMaxGuests: Int
  ) -> some View {
    let fraction = CGFloat.tryzubSafeRatio(
      numerator: CGFloat(bucket.guestCount),
      denominator: CGFloat(chartMaxGuests)
    )
    // Empty buckets show only a faint baseline nub so empty hours never dominate.
    let fullHeight = bucket.hasArrivals ? max(usableHeight * fraction, 6) : 3
    let animatedHeight = max(fullHeight * revealProgress, bucket.hasArrivals ? 2 : 1)
    let isSelected = selectedBucketID == bucket.id
    let centerX = barCenterX(index, plotWidth: plotWidth)

    let tint: Color = {
      if !bucket.hasArrivals { return TryzubColors.border.opacity(0.5) }
      if bucket.isPeak { return TryzubColors.primaryControl }
      return TryzubColors.primaryControl.opacity(0.78)
    }()

    ZStack(alignment: .bottom) {
      RoundedRectangle(cornerRadius: barWidth / 2.4, style: .continuous)
        .fill(tint)
        .frame(width: barWidth, height: animatedHeight)
        .overlay(alignment: .bottom) {
          if isSelected {
            RoundedRectangle(cornerRadius: barWidth / 2.4, style: .continuous)
              .stroke(TryzubColors.primaryControl, lineWidth: 1.5)
              .frame(width: barWidth, height: animatedHeight)
          }
        }
        .scaleEffect(
          x: 1,
          y: bucket.isPeak && peakPulse && !reduceMotion && !isSelected ? 1.04 : 1,
          anchor: .bottom
        )

      // Value label above the bar for arrival windows.
      if bucket.hasArrivals {
        Text("\(bucket.guestCount)")
          .font(.system(size: 8, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(bucket.isPeak ? TryzubColors.primaryControl : TryzubColors.mutedText)
          .opacity(Double(revealProgress))
          .offset(y: -(animatedHeight + 7))
      }
    }
    .frame(width: barWidth, height: plotHeight, alignment: .bottom)
    .position(x: centerX, y: plotHeight / 2)
    .accessibilityElement()
    .accessibilityLabel(ArrivalFlowBucketBuilder.accessibilityLabel(for: bucket))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func barWidth(plotWidth: CGFloat) -> CGFloat {
    guard buckets.count > 0 else { return 6 }
    let slot = plotWidth / CGFloat(buckets.count)
    return min(max(slot * 0.62, 4), 22)
  }

  private func barCenterX(_ index: Int, plotWidth: CGFloat) -> CGFloat {
    guard buckets.count > 1 else { return plotWidth / 2 }
    let slot = plotWidth / CGFloat(buckets.count)
    return slot * (CGFloat(index) + 0.5)
  }

  private func selectBucket(at x: CGFloat, plotWidth: CGFloat) {
    guard !buckets.isEmpty else { return }

    let nearestIndex = buckets.indices.min(by: { lhs, rhs in
      let lhsDistance = abs(barCenterX(lhs, plotWidth: plotWidth) - x)
      let rhsDistance = abs(barCenterX(rhs, plotWidth: plotWidth) - x)
      return lhsDistance < rhsDistance
    })

    guard let nearestIndex else { return }
    let bucket = buckets[nearestIndex]
    guard bucket.hasArrivals else { return }

    if selectedBucketID == bucket.id {
      selectedBucketID = nil
    } else {
      selectedBucketID = bucket.id
    }
  }
}
