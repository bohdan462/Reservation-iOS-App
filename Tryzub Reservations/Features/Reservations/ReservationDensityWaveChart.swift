//
//  ReservationDensityWaveChart.swift
//  Tryzub Reservations
//
//  15-minute arrival flow chart for the Host/Home service tab.
//

import SwiftUI

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

struct ReservationDensityWaveChart: View {
  let buckets: [ArrivalFlowBucket]
  var height: CGFloat = 96

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealProgress: CGFloat = 0
  @State private var peakPulse = false
  @State private var gridOpacity: Double = 0.35
  @State private var selectedBucketID: String?

  private let leftGutter: CGFloat = 22
  private let bottomGutter: CGFloat = 14
  private let topGutter: CGFloat = 4

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
    Array(0...maxGuests)
  }

  private var xLabelIndices: [Int] {
    guard !buckets.isEmpty else { return [] }
    return Array(buckets.indices)
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
          .onAppear { playChartEntrance() }
          .onChange(of: chartSeriesKey) { _, _ in
            selectedBucketID = nil
            playChartEntrance()
          }

        footerCaption
          .padding(.bottom, 2)
      }
      .accessibilityElement(children: .contain)
    }
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
      Text("Tap a spike to see who is coming.")
        .font(.caption2)
        .foregroundStyle(TryzubColors.mutedText)
        .accessibilityHidden(true)
    }
  }

  private func playChartEntrance() {
    peakPulse = false
    if reduceMotion {
      revealProgress = 1
      gridOpacity = 1
      return
    }

    revealProgress = 0
    gridOpacity = 0.35
    withAnimation(.easeOut(duration: 0.95)) {
      revealProgress = 1
      gridOpacity = 1
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
    let plotHeight = height.tryzubFiniteNonNegativeLayoutValue - bottomGutter - topGutter
    return ZStack(alignment: .topLeading) {
      ForEach(yTicks.reversed(), id: \.self) { tick in
        Text("\(tick)")
          .font(.system(size: 8, weight: .medium, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(TryzubColors.mutedText.opacity(0.35 + revealProgress * 0.5))
          .offset(y: yOffset(for: tick, plotHeight: plotHeight))
      }
    }
    .frame(width: leftGutter - 2, height: height.tryzubFiniteNonNegativeLayoutValue, alignment: .topLeading)
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
          Text(buckets[index].axisLabel)
            .font(.system(size: 8, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(TryzubColors.mutedText.opacity(0.9))
            .fixedSize()
            .position(
              x: xPosition(for: index, plotWidth: plotWidth, bucketCount: buckets.count),
              y: 6
            )
        }
      }
    }
    .frame(height: bottomGutter)
    .accessibilityHidden(true)
  }

  private var chartBody: some View {
    let chartMaxGuests = maxGuests
    let plotHeight = height.tryzubFiniteNonNegativeLayoutValue - bottomGutter

    return GeometryReader { proxy in
      let plotWidth = max(proxy.size.width, 1)
      let linePoints = waveLinePoints(plotWidth: plotWidth, plotHeight: plotHeight, chartMaxGuests: chartMaxGuests)

      ZStack {
        Canvas { context, size in
          drawGrid(
            context: &context,
            size: size,
            chartMaxGuests: chartMaxGuests,
            gridOpacity: gridOpacity
          )
        }

        if arrivalBuckets.count == 1,
           let bucket = arrivalBuckets.first,
           let index = buckets.firstIndex(where: { $0.id == bucket.id }) {
          let point = CGPoint(
            x: plotX(index, plotWidth: plotWidth, bucketCount: buckets.count),
            y: plotY(for: bucket.guestCount, plotHeight: plotHeight, chartMaxGuests: chartMaxGuests)
          )
          singlePointMarker(at: point)
            .opacity(Double(revealProgress))
        } else if buckets.count > 1 {
          Canvas { context, size in
            drawWave(
              context: &context,
              size: size,
              chartMaxGuests: chartMaxGuests,
              revealProgress: revealProgress,
              plotWidth: plotWidth,
              plotHeight: plotHeight
            )
          }
          .mask(alignment: .leading) {
            Rectangle()
              .frame(width: plotWidth * revealProgress)
          }

          if let selectedBucket,
             let index = buckets.firstIndex(where: { $0.id == selectedBucket.id }) {
            Canvas { context, size in
              let x = plotX(index, plotWidth: plotWidth, bucketCount: buckets.count)
              var guide = Path()
              guide.move(to: CGPoint(x: x, y: 0))
              guide.addLine(to: CGPoint(x: x, y: size.height))
              context.stroke(
                guide,
                with: .color(TryzubColors.primaryControl.opacity(0.28)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
              )
            }
            .allowsHitTesting(false)
          }
        }

        dataPointMarkers(
          plotWidth: plotWidth,
          plotHeight: plotHeight,
          chartMaxGuests: chartMaxGuests
        )
        .opacity(Double(revealProgress))
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onEnded { value in
            selectBucket(at: value.location.x, plotWidth: plotWidth)
          }
      )
    }
    .frame(height: plotHeight)
  }

  private func selectBucket(at x: CGFloat, plotWidth: CGFloat) {
    guard !buckets.isEmpty else { return }

    let nearestIndex = buckets.indices.min(by: { lhs, rhs in
      let lhsDistance = abs(plotX(lhs, plotWidth: plotWidth, bucketCount: buckets.count) - x)
      let rhsDistance = abs(plotX(rhs, plotWidth: plotWidth, bucketCount: buckets.count) - x)
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

  private func waveLinePoints(
    plotWidth: CGFloat,
    plotHeight: CGFloat,
    chartMaxGuests: Int
  ) -> [CGPoint] {
    buckets.enumerated().map { index, bucket in
      CGPoint(
        x: plotX(index, plotWidth: plotWidth, bucketCount: buckets.count),
        y: plotY(for: bucket.guestCount, plotHeight: plotHeight, chartMaxGuests: chartMaxGuests)
      )
    }
  }

  private func plotX(_ index: Int, plotWidth: CGFloat, bucketCount: Int) -> CGFloat {
    guard bucketCount > 1 else { return plotWidth / 2 }
    return plotWidth * CGFloat(index) / CGFloat(bucketCount - 1)
  }

  private func plotY(for guestCount: Int, plotHeight: CGFloat, chartMaxGuests: Int) -> CGFloat {
    let fraction = CGFloat.tryzubSafeRatio(
      numerator: CGFloat(guestCount),
      denominator: CGFloat(chartMaxGuests)
    )
    return topGutter + (plotHeight - topGutter) * (1 - fraction)
  }

  private func drawGrid(
    context: inout GraphicsContext,
    size: CGSize,
    chartMaxGuests: Int,
    gridOpacity: Double
  ) {
    guard buckets.count >= 1, size.width > 1, size.height > 1 else { return }

    let plotWidth = size.width
    let plotHeight = size.height.tryzubFiniteNonNegativeLayoutValue
    let gridColor = TryzubColors.border.opacity(0.22 * gridOpacity)
    let majorGridColor = TryzubColors.border.opacity(0.34 * gridOpacity)

    for tick in 0...chartMaxGuests {
      let y = plotY(for: tick, plotHeight: plotHeight, chartMaxGuests: chartMaxGuests)
      var path = Path()
      path.move(to: CGPoint(x: 0, y: y))
      path.addLine(to: CGPoint(x: plotWidth, y: y))
      context.stroke(
        path,
        with: .color(tick == 0 ? majorGridColor : gridColor),
        style: StrokeStyle(lineWidth: tick == 0 ? 0.75 : 0.5)
      )
    }

    for index in buckets.indices {
      let x = plotX(index, plotWidth: plotWidth, bucketCount: buckets.count)
      let isHour = Calendar.current.component(.minute, from: buckets[index].bucketStart) == 0
      var path = Path()
      path.move(to: CGPoint(x: x, y: 0))
      path.addLine(to: CGPoint(x: x, y: plotHeight))
      context.stroke(
        path,
        with: .color(isHour ? majorGridColor : gridColor),
        style: StrokeStyle(lineWidth: isHour ? 0.65 : 0.45)
      )
    }
  }

  private func drawWave(
    context: inout GraphicsContext,
    size: CGSize,
    chartMaxGuests: Int,
    revealProgress: CGFloat,
    plotWidth: CGFloat,
    plotHeight: CGFloat
  ) {
    guard buckets.count >= 2, size.width > 1, size.height > 1 else { return }

    let linePoints = waveLinePoints(
      plotWidth: plotWidth,
      plotHeight: plotHeight,
      chartMaxGuests: chartMaxGuests
    )

    var areaPath = linearPath(through: linePoints)
    areaPath.addLine(to: CGPoint(x: linePoints.last?.x ?? 0, y: plotHeight))
    areaPath.addLine(to: CGPoint(x: linePoints.first?.x ?? 0, y: plotHeight))
    areaPath.closeSubpath()

    let fillOpacity = 0.12 + Double(revealProgress) * 0.08
    context.fill(
      areaPath,
      with: .linearGradient(
        Gradient(colors: [
          TryzubColors.primaryControl.opacity(fillOpacity + 0.06),
          TryzubColors.primaryControl.opacity(0.02)
        ]),
        startPoint: CGPoint(x: 0, y: 0),
        endPoint: CGPoint(x: 0, y: plotHeight)
      )
    )

    let strokePath = linearPath(through: linePoints)
    context.stroke(
      strokePath,
      with: .color(TryzubColors.primaryControl.opacity(0.68 + Double(revealProgress) * 0.18)),
      style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
    )

  }

  @ViewBuilder
  private func singlePointMarker(at point: CGPoint) -> some View {
    if let bucket = arrivalBuckets.first {
      let isSelected = selectedBucketID == bucket.id
      ZStack {
        if isSelected {
          Circle()
            .stroke(TryzubColors.primaryControl.opacity(0.35), lineWidth: 2)
            .frame(width: 16, height: 16)
        }
        Circle()
          .fill(TryzubColors.primaryControl)
          .frame(width: bucket.isPeak ? 8 : 6, height: bucket.isPeak ? 8 : 6)
          .scaleEffect(bucket.isPeak && peakPulse && !reduceMotion ? 1.12 : 1)
      }
      .position(point)
      .accessibilityLabel(ArrivalFlowBucketBuilder.accessibilityLabel(for: bucket))
    }
  }

  @ViewBuilder
  private func dataPointMarkers(
    plotWidth: CGFloat,
    plotHeight: CGFloat,
    chartMaxGuests: Int
  ) -> some View {
    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
      if bucket.hasArrivals {
        let center = CGPoint(
          x: plotX(index, plotWidth: plotWidth, bucketCount: buckets.count),
          y: plotY(for: bucket.guestCount, plotHeight: plotHeight, chartMaxGuests: chartMaxGuests)
        )
        let isSelected = selectedBucketID == bucket.id
        let dotSize: CGFloat = isSelected ? 8 : (bucket.isPeak ? 7 : 5)

        ZStack {
          if isSelected {
            Circle()
              .stroke(TryzubColors.primaryControl.opacity(0.4), lineWidth: 2)
              .frame(width: 16, height: 16)
          } else if bucket.isNextArrival {
            Circle()
              .stroke(TryzubColors.primaryControl.opacity(0.25), lineWidth: 1.5)
              .frame(width: 12, height: 12)
          }

          Circle()
            .fill(bucket.isPeak ? TryzubColors.primaryControl : TryzubColors.primaryControl.opacity(0.88))
            .frame(width: dotSize, height: dotSize)
            .scaleEffect(bucket.isPeak && peakPulse && !reduceMotion && !isSelected ? 1.12 : 1)
        }
        .position(center)
        .accessibilityElement()
        .accessibilityLabel(ArrivalFlowBucketBuilder.accessibilityLabel(for: bucket))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
  }

  private func xPosition(for index: Int, plotWidth: CGFloat, bucketCount: Int) -> CGFloat {
    plotX(index, plotWidth: plotWidth, bucketCount: bucketCount)
  }

  private func linearPath(through points: [CGPoint]) -> Path {
    guard let first = points.first else { return Path() }
    var path = Path()
    path.move(to: first)
    for point in points.dropFirst() {
      path.addLine(to: point)
    }
    return path
  }
}
