//
//  ArrivalPressureWaveChart.swift
//  Tryzub Reservations
//
//  Service-pressure wave chart: smooth area curve with tap targets.
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
  var height: CGFloat = 120
  var isToday: Bool = true
  var now: Date = Date()
  var onOpenReservation: ((Int) -> Void)?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.colorScheme) private var colorScheme

  @State private var revealProgress: CGFloat = 0
  @State private var peakPulse = false
  @State private var selectedBucketID: String?
  @State private var sheetBucket: ArrivalPressureBucket?
  @State private var measuredPlotWidth: CGFloat = 0
  @State private var clockNow = Date()

  private let bottomGutter: CGFloat = 16
  private let topGutter: CGFloat = 10
  private static let minChartHeight: CGFloat = 88

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
        chartBody
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
    withAnimation(.easeOut(duration: 0.7)) { revealProgress = 1 }
    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { peakPulse = true }
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

  // MARK: - Chart

  private var chartBody: some View {
    let plotHeight = max(resolvedHeight - bottomGutter, Self.minChartHeight - bottomGutter)
    let usableHeight = max(plotHeight - topGutter, 1)

    return VStack(spacing: 0) {
      GeometryReader { proxy in
        let plotWidth = max(proxy.size.width, 1)

        ZStack(alignment: .bottomLeading) {
          // Subtle horizontal guides
          gridLines(plotWidth: plotWidth, plotHeight: plotHeight, usableHeight: usableHeight)

          if plotWidth > 1 {
            // Past wave (muted)
            if let split = nowBucketIndex, split > 0 {
              waveSegment(
                plotWidth: plotWidth,
                usableHeight: usableHeight,
                plotHeight: plotHeight,
                range: 0..<split,
                fillOpacity: 0.10,
                strokeOpacity: 0.22,
                strokeWidth: 1.2
              )
              waveSegment(
                plotWidth: plotWidth,
                usableHeight: usableHeight,
                plotHeight: plotHeight,
                range: max(0, split - 1)..<buckets.count,
                fillOpacity: 0.28,
                strokeOpacity: 0.55,
                strokeWidth: 2.0
              )
            } else {
              waveSegment(
                plotWidth: plotWidth,
                usableHeight: usableHeight,
                plotHeight: plotHeight,
                range: 0..<buckets.count,
                fillOpacity: isToday ? 0.26 : 0.22,
                strokeOpacity: 0.50,
                strokeWidth: 2.0
              )
            }

            // Arrival dots on the wave
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
              if bucket.hasArrivals {
                arrivalDot(
                  bucket: bucket,
                  index: index,
                  plotWidth: plotWidth,
                  usableHeight: usableHeight,
                  plotHeight: plotHeight
                )
              }
            }

            // Peak ring
            if let peakIndex = buckets.firstIndex(where: { $0.isPeak && $0.hasArrivals }) {
              peakMarker(
                index: peakIndex,
                plotWidth: plotWidth,
                usableHeight: usableHeight,
                plotHeight: plotHeight
              )
            }

            // Now line
            if let nowIndex = nowBucketIndex {
              nowMarker(index: nowIndex, plotWidth: plotWidth, plotHeight: plotHeight)
            }

            // Tap zones
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
              if bucket.hasArrivals {
                tapZone(index: index, plotWidth: plotWidth, plotHeight: plotHeight)
              }
            }
          }
        }
        .frame(width: plotWidth, height: plotHeight, alignment: .bottomLeading)
        .onAppear { measuredPlotWidth = plotWidth }
        .onChange(of: plotWidth) { _, w in measuredPlotWidth = w }
      }
      .frame(height: plotHeight)

      xAxisLabels
    }
  }

  // MARK: - Wave segments

  @ViewBuilder
  private func waveSegment(
    plotWidth: CGFloat,
    usableHeight: CGFloat,
    plotHeight: CGFloat,
    range: Range<Int>,
    fillOpacity: Double,
    strokeOpacity: Double,
    strokeWidth: CGFloat
  ) -> some View {
    let waveColor = colorScheme == .dark
      ? Color.accentColor
      : TryzubColors.primaryControl

    wavePath(
      plotWidth: plotWidth,
      usableHeight: usableHeight,
      plotHeight: plotHeight,
      range: range
    )
    .fill(
      LinearGradient(
        colors: [
          waveColor.opacity(fillOpacity),
          waveColor.opacity(fillOpacity * 0.15)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .opacity(Double(revealProgress))
    .allowsHitTesting(false)

    wavePath(
      plotWidth: plotWidth,
      usableHeight: usableHeight,
      plotHeight: plotHeight,
      range: range
    )
    .stroke(
      waveColor.opacity(strokeOpacity),
      style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
    )
    .opacity(Double(revealProgress))
    .allowsHitTesting(false)
  }

  private func wavePath(
    plotWidth: CGFloat,
    usableHeight: CGFloat,
    plotHeight: CGFloat,
    range: Range<Int>
  ) -> Path {
    var path = Path()
    guard !range.isEmpty, buckets.count > 1 else { return path }

    let indices = Array(range).filter { buckets.indices.contains($0) }
    guard indices.count >= 2 else {
      if let only = indices.first {
        let x = centerX(only, plotWidth: plotWidth)
        let h = usableHeight * CGFloat(buckets[only].normalizedPressure) * revealProgress
        path.move(to: CGPoint(x: x, y: plotHeight))
        path.addLine(to: CGPoint(x: x, y: plotHeight - h))
        path.addLine(to: CGPoint(x: x, y: plotHeight))
        path.closeSubpath()
      }
      return path
    }

    let points: [CGPoint] = indices.map { index in
      let bucket = buckets[index]
      let x = centerX(index, plotWidth: plotWidth)
      let h = usableHeight * CGFloat(bucket.normalizedPressure) * revealProgress
      return CGPoint(x: x, y: plotHeight - max(h, 2))
    }

    path.move(to: CGPoint(x: points[0].x, y: plotHeight))
    path.addLine(to: points[0])

    for index in 1..<points.count {
      let prev = points[index - 1]
      let curr = points[index]
      let tension: CGFloat = 0.35
      let dx = (curr.x - prev.x) * tension
      path.addCurve(
        to: curr,
        control1: CGPoint(x: prev.x + dx, y: prev.y),
        control2: CGPoint(x: curr.x - dx, y: curr.y)
      )
    }

    if let last = points.last {
      path.addLine(to: CGPoint(x: last.x, y: plotHeight))
    }
    path.closeSubpath()
    return path
  }

  // MARK: - Markers

  private func gridLines(plotWidth: CGFloat, plotHeight: CGFloat, usableHeight: CGFloat) -> some View {
    ZStack(alignment: .bottomLeading) {
      ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
        Rectangle()
          .fill(Color.primary.opacity(0.05))
          .frame(width: plotWidth, height: 0.5)
          .offset(y: -(usableHeight * CGFloat(fraction)))
      }
      Rectangle()
        .fill(TryzubColors.border.opacity(0.35))
        .frame(width: plotWidth, height: 0.75)
    }
    .frame(width: plotWidth, height: plotHeight, alignment: .bottomLeading)
    .allowsHitTesting(false)
  }

  private func arrivalDot(
    bucket: ArrivalPressureBucket,
    index: Int,
    plotWidth: CGFloat,
    usableHeight: CGFloat,
    plotHeight: CGFloat
  ) -> some View {
    let x = centerX(index, plotWidth: plotWidth)
    let h = usableHeight * CGFloat(bucket.normalizedPressure) * revealProgress
    let y = plotHeight - max(h, 4)
    let isSelected = selectedBucketID == bucket.id
    let isPast = bucket.isPast

    let dotColor: Color = {
      if bucket.isPeak { return Color.accentColor }
      if bucket.noTableCount > 0 { return TryzubColors.warning }
      return Color.accentColor.opacity(0.75)
    }()

    return ZStack {
      Circle()
        .fill(dotColor.opacity(isPast ? 0.45 : 0.9))
        .frame(width: isSelected ? 7 : 5, height: isSelected ? 7 : 5)
        .overlay {
          if isSelected {
            Circle().stroke(Color.accentColor, lineWidth: 1.5).frame(width: 11, height: 11)
          }
        }

      if bucket.isPeak || isSelected {
        Text("\(bucket.guestCount)")
          .font(.system(size: 8, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(bucket.isPeak ? Color.accentColor : TryzubColors.mutedText)
          .opacity(isPast ? 0.55 : 1)
          .offset(y: -14)
      }
    }
    .position(x: x, y: y)
    .opacity(Double(revealProgress))
    .allowsHitTesting(false)
  }

  private func peakMarker(
    index: Int,
    plotWidth: CGFloat,
    usableHeight: CGFloat,
    plotHeight: CGFloat
  ) -> some View {
    let x = centerX(index, plotWidth: plotWidth)
    let h = usableHeight * CGFloat(buckets[index].normalizedPressure) * revealProgress
    let y = plotHeight - max(h, 4)

    return Circle()
      .stroke(Color.accentColor.opacity(0.35), lineWidth: 1.5)
      .frame(width: peakPulse && !reduceMotion ? 18 : 14, height: peakPulse && !reduceMotion ? 18 : 14)
      .position(x: x, y: y)
      .opacity(Double(revealProgress) * 0.8)
      .allowsHitTesting(false)
  }

  private func nowMarker(index: Int, plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
    let x = centerX(index, plotWidth: plotWidth)
    return ZStack(alignment: .top) {
      Rectangle()
        .fill(Color.accentColor.opacity(0.40))
        .frame(width: 1, height: plotHeight - topGutter)

      Text("Now")
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.85), in: Capsule())
        .offset(y: 2)
    }
    .frame(width: 1, height: plotHeight, alignment: .top)
    .position(x: x, y: plotHeight / 2)
    .allowsHitTesting(false)
  }

  private func tapZone(index: Int, plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
    let x = centerX(index, plotWidth: plotWidth)
    let bucket = buckets[index]
    return Circle()
      .fill(Color.clear)
      .frame(width: max(tapRadius(plotWidth: plotWidth), 28), height: max(tapRadius(plotWidth: plotWidth), 28))
      .contentShape(Circle())
      .position(x: x, y: plotHeight * 0.45)
      .onTapGesture {
        selectedBucketID = bucket.id
        sheetBucket = bucket
      }
      .accessibilityLabel(accessibilityLabel(for: bucket))
      .accessibilityAddTraits(.isButton)
  }

  private func tapRadius(plotWidth: CGFloat) -> CGFloat {
    guard buckets.count > 0 else { return 14 }
    return max(plotWidth / CGFloat(buckets.count) * 0.7, 14)
  }

  // MARK: - X axis

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
            .foregroundStyle(TryzubColors.mutedText.opacity(0.85))
            .fixedSize()
            .position(x: centerX(index, plotWidth: plotWidth), y: 7)
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

  private func centerX(_ index: Int, plotWidth: CGFloat) -> CGFloat {
    guard buckets.count > 1 else { return plotWidth / 2 }
    let slot = plotWidth / CGFloat(buckets.count)
    return slot * (CGFloat(index) + 0.5)
  }

  private var selectedBucket: ArrivalPressureBucket? {
    guard let selectedBucketID else { return nil }
    return buckets.first(where: { $0.id == selectedBucketID })
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
}

extension ArrivalPressureBucket: Hashable {
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
