//
//  ReservationDensityWaveChart.swift
//  Tryzub Reservations
//
//  15-minute guest-density wave for the Host/Home service tab.
//

import SwiftUI

struct ReservationDensityPoint: Identifiable, Equatable {
  let id: String
  let bucketStart: Date
  let bucketLabel: String
  let guestCount: Int
  let reservationCount: Int
  let isPeak: Bool
}

enum ReservationDensityCalculator {
  private static let bucketMinutes = 15

  static func points(
    from reservations: [ReservationRecord],
    selectedDate: Date,
    serviceOpen: Date?,
    serviceClose: Date?,
    calendar: Calendar = .current
  ) -> [ReservationDensityPoint] {
    let active = reservations.filter { $0.isExpectedGuest && !$0.isHidden }
    guard let range = resolveBucketRange(
      reservations: active,
      selectedDate: selectedDate,
      serviceOpen: serviceOpen,
      serviceClose: serviceClose,
      calendar: calendar
    ) else {
      return []
    }

    var bucketStarts: [Date] = []
    var guestCounts: [Date: Int] = [:]
    var reservationCounts: [Date: Int] = [:]

    var cursor = range.lowerBound
    while cursor <= range.upperBound {
      bucketStarts.append(cursor)
      guestCounts[cursor] = 0
      reservationCounts[cursor] = 0
      guard let next = calendar.date(byAdding: .minute, value: bucketMinutes, to: cursor) else { break }
      cursor = next
    }

    for reservation in active {
      guard let serviceDate = reservation.serviceDateTime else { continue }
      let bucket = floorToBucketStart(serviceDate, calendar: calendar)
      guard guestCounts[bucket] != nil else { continue }
      guestCounts[bucket, default: 0] += reservation.partySize
      reservationCounts[bucket, default: 0] += 1
    }

    let peakGuestCount = guestCounts.values.max() ?? 0

    return bucketStarts.map { bucketStart in
      let guests = guestCounts[bucketStart] ?? 0
      let reservations = reservationCounts[bucketStart] ?? 0
      return ReservationDensityPoint(
        id: "\(bucketStart.timeIntervalSince1970)",
        bucketStart: bucketStart,
        bucketLabel: bucketLabel(for: bucketStart, calendar: calendar),
        guestCount: guests,
        reservationCount: reservations,
        isPeak: guests > 0 && guests == peakGuestCount
      )
    }
  }

  static func peakPoint(in points: [ReservationDensityPoint]) -> ReservationDensityPoint? {
    points.first(where: { $0.isPeak && $0.guestCount > 0 })
  }

  static func bucketStart(for reservation: ReservationRecord, calendar: Calendar = .current) -> Date? {
    guard let serviceDate = reservation.serviceDateTime else { return nil }
    return floorToBucketStart(serviceDate, calendar: calendar)
  }

  static func bucketStart(for date: Date, calendar: Calendar = .current) -> Date {
    floorToBucketStart(date, calendar: calendar)
  }

  // MARK: - Private

  private static func resolveBucketRange(
    reservations: [ReservationRecord],
    selectedDate: Date,
    serviceOpen: Date?,
    serviceClose: Date?,
    calendar: Calendar
  ) -> ClosedRange<Date>? {
    if let serviceOpen, let serviceClose, serviceOpen <= serviceClose {
      let lower = floorToBucketStart(serviceOpen, calendar: calendar)
      let upper = floorToBucketStart(serviceClose, calendar: calendar)
      return extendRangeIfNeeded(
        lower: lower,
        upper: upper,
        reservations: reservations,
        calendar: calendar
      )
    }

    let serviceDates = reservations.compactMap(\.serviceDateTime)
    guard let earliest = serviceDates.min(), let latest = serviceDates.max() else {
      return nil
    }

    let paddedLower = calendar.date(byAdding: .hour, value: -1, to: earliest) ?? earliest
    let paddedUpper = calendar.date(byAdding: .hour, value: 1, to: latest) ?? latest
    let lower = floorToBucketStart(paddedLower, calendar: calendar)
    let upper = floorToBucketStart(paddedUpper, calendar: calendar)
    return lower...max(lower, upper)
  }

  private static func extendRangeIfNeeded(
    lower: Date,
    upper: Date,
    reservations: [ReservationRecord],
    calendar: Calendar
  ) -> ClosedRange<Date> {
    var rangeLower = lower
    var rangeUpper = upper

    for reservation in reservations {
      guard let serviceDate = reservation.serviceDateTime else { continue }
      let bucket = floorToBucketStart(serviceDate, calendar: calendar)
      if bucket < rangeLower {
        rangeLower = bucket
      }
      if bucket > rangeUpper {
        rangeUpper = bucket
      }
    }

    return rangeLower...rangeUpper
  }

  private static func floorToBucketStart(_ date: Date, calendar: Calendar) -> Date {
    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    let minute = components.minute ?? 0
    components.minute = (minute / bucketMinutes) * bucketMinutes
    components.second = 0
    components.nanosecond = 0
    return calendar.date(from: components) ?? date
  }

  private static func bucketLabel(for date: Date, calendar: Calendar) -> String {
    compactAxisLabel(for: date, calendar: calendar)
  }

  static func compactAxisLabel(for date: Date, calendar: Calendar) -> String {
    let hour = calendar.component(.hour, from: date)
    let minute = calendar.component(.minute, from: date)
    let adjustedHour = hour % 12 == 0 ? 12 : hour % 12
    if minute == 0 {
      return "\(adjustedHour)"
    }
    return String(format: "%d:%02d", adjustedHour, minute)
  }
}

struct ReservationDensityWaveChart: View {
  let points: [ReservationDensityPoint]
  var highlightBucketStart: Date?
  var height: CGFloat = 88

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealProgress: CGFloat = 0
  @State private var peakPulse = false
  @State private var gridOpacity: Double = 0.35

  private let leftGutter: CGFloat = 18
  private let bottomGutter: CGFloat = 14
  private let topGutter: CGFloat = 2

  private var chartSeriesKey: String {
    points.map { "\($0.id):\($0.guestCount)" }.joined(separator: "|")
  }

  private var hasPressure: Bool {
    points.contains { $0.guestCount > 0 }
  }

  private var maxGuests: Int {
    max(points.map(\.guestCount).max() ?? 0, 1)
  }

  private var yTicks: [Int] {
    Array(0...maxGuests)
  }

  private var xLabelIndices: [Int] {
    guard !points.isEmpty else { return [] }
    let count = points.count
    let step: Int
    if count <= 17 {
      step = 1
    } else if count <= 33 {
      step = 2
    } else {
      step = 4
    }
    return stride(from: 0, to: count, by: step).map { $0 }
  }

  var body: some View {
    if !hasPressure {
      HStack(spacing: 8) {
        Image(systemName: "waveform.path")
          .foregroundStyle(TryzubColors.mutedText)
        Text("No reservation pressure for this date.")
          .font(.caption.weight(.medium))
          .foregroundStyle(TryzubColors.mutedText)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    } else {
      VStack(alignment: .leading, spacing: 4) {
        chartWithAxes
          .onAppear { playChartEntrance() }
          .onChange(of: chartSeriesKey) { _, _ in playChartEntrance() }
        Text("Guests per 15-minute arrival window")
          .font(.caption2)
          .foregroundStyle(TryzubColors.mutedText)
          .opacity(0.35 + revealProgress * 0.65)
      }
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
          Text(points[index].bucketLabel)
            .font(.system(size: 8, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(TryzubColors.mutedText.opacity(0.9))
            .fixedSize()
            .position(
              x: xPosition(for: index, plotWidth: plotWidth, bucketCount: points.count),
              y: 6
            )
        }
      }
    }
    .frame(height: bottomGutter)
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

        if linePoints.count == 1, let point = linePoints.first {
          singlePointMarker(at: point)
            .opacity(Double(revealProgress))
        } else {
          Canvas { context, size in
            drawWave(
              context: &context,
              size: size,
              chartMaxGuests: chartMaxGuests,
              revealProgress: revealProgress
            )
          }
          .mask(alignment: .leading) {
            Rectangle()
              .frame(width: plotWidth * revealProgress)
          }

          peakMarkers(
            plotWidth: plotWidth,
            plotHeight: plotHeight,
            chartMaxGuests: chartMaxGuests
          )
          .opacity(Double(revealProgress))
        }
      }
    }
    .frame(height: plotHeight)
  }

  private func waveLinePoints(
    plotWidth: CGFloat,
    plotHeight: CGFloat,
    chartMaxGuests: Int
  ) -> [CGPoint] {
    points.enumerated().map { index, point in
      CGPoint(
        x: plotX(index, plotWidth: plotWidth, bucketCount: points.count),
        y: plotY(for: point.guestCount, plotHeight: plotHeight, chartMaxGuests: chartMaxGuests)
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
    return plotHeight * (1 - fraction)
  }

  private func drawGrid(
    context: inout GraphicsContext,
    size: CGSize,
    chartMaxGuests: Int,
    gridOpacity: Double
  ) {
    guard points.count >= 1, size.width > 1, size.height > 1 else { return }

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

    for index in points.indices {
      let x = plotX(index, plotWidth: plotWidth, bucketCount: points.count)
      let isHour = Calendar.current.component(.minute, from: points[index].bucketStart) == 0
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
    revealProgress: CGFloat
  ) {
    guard points.count >= 2, size.width > 1, size.height > 1 else { return }

    let plotWidth = size.width
    let plotHeight = size.height.tryzubFiniteNonNegativeLayoutValue
    let linePoints = waveLinePoints(
      plotWidth: plotWidth,
      plotHeight: plotHeight,
      chartMaxGuests: chartMaxGuests
    )

    var areaPath = smoothPath(through: linePoints)
    areaPath.addLine(to: CGPoint(x: linePoints.last?.x ?? 0, y: plotHeight))
    areaPath.addLine(to: CGPoint(x: linePoints.first?.x ?? 0, y: plotHeight))
    areaPath.closeSubpath()

    let fillOpacity = 0.18 + Double(revealProgress) * 0.12
    context.fill(
      areaPath,
      with: .linearGradient(
        Gradient(colors: [
          TryzubColors.primaryControl.opacity(fillOpacity + 0.1),
          TryzubColors.primaryControl.opacity(0.03)
        ]),
        startPoint: CGPoint(x: 0, y: 0),
        endPoint: CGPoint(x: 0, y: plotHeight)
      )
    )

    let strokePath = smoothPath(through: linePoints)
    context.stroke(
      strokePath,
      with: .color(TryzubColors.primaryControl.opacity(0.72 + Double(revealProgress) * 0.2)),
      style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
    )
  }

  @ViewBuilder
  private func singlePointMarker(at point: CGPoint) -> some View {
    Circle()
      .fill(TryzubColors.primaryControl)
      .frame(width: 7, height: 7)
      .position(point)
      .scaleEffect(peakPulse ? 1.14 : 0.94)
  }

  @ViewBuilder
  private func peakMarkers(
    plotWidth: CGFloat,
    plotHeight: CGFloat,
    chartMaxGuests: Int
  ) -> some View {
    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
      if point.guestCount > 0,
         point.isPeak || highlightBucketStart == point.bucketStart {
        let center = CGPoint(
          x: plotX(index, plotWidth: plotWidth, bucketCount: points.count),
          y: plotY(for: point.guestCount, plotHeight: plotHeight, chartMaxGuests: chartMaxGuests)
        )
        let isPeak = point.isPeak

        Circle()
          .fill(isPeak ? TryzubColors.primaryControl : TryzubColors.primaryControl.opacity(0.85))
          .frame(width: isPeak ? 7 : 6, height: isPeak ? 7 : 6)
          .scaleEffect(isPeak && peakPulse && !reduceMotion ? 1.14 : 1)
          .position(center)
      }
    }
  }

  private func xPosition(for index: Int, plotWidth: CGFloat, bucketCount: Int) -> CGFloat {
    plotX(index, plotWidth: plotWidth, bucketCount: bucketCount)
  }

  private func smoothPath(through points: [CGPoint]) -> Path {
    guard !points.isEmpty else { return Path() }
    guard points.count > 1 else {
      var path = Path()
      path.addEllipse(in: CGRect(x: points[0].x - 3, y: points[0].y - 3, width: 6, height: 6))
      return path
    }

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
}
