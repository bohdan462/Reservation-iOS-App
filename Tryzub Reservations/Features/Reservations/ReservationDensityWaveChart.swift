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
    ReservationFormatters.shortTime.string(from: date)
  }
}

struct ReservationDensityWaveChart: View {
  let points: [ReservationDensityPoint]
  var highlightBucketStart: Date?
  var height: CGFloat = 68

  private var hasPressure: Bool {
    points.contains { $0.guestCount > 0 }
  }

  private var maxGuests: Int {
    max(points.map(\.guestCount).max() ?? 0, 1)
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
      VStack(alignment: .leading, spacing: 6) {
        chartBody
        axisLabels
        Text("Guest density by 15-minute arrival window")
          .font(.caption2)
          .foregroundStyle(TryzubColors.mutedText)
      }
    }
  }

  private var chartBody: some View {
    let chartMaxGuests = maxGuests
    return Canvas { context, size in
      guard points.count >= 1, size.width > 1, size.height > 1 else { return }

      let safeHeight = size.height.tryzubFiniteNonNegativeLayoutValue
      let inset = EdgeInsets(top: 8, leading: 2, bottom: 4, trailing: 2)
      let plotWidth = max(size.width - inset.leading - inset.trailing, 1)
      let plotHeight = max(safeHeight - inset.top - inset.bottom, 1)

      func xPosition(for index: Int) -> CGFloat {
        guard points.count > 1 else { return inset.leading + plotWidth / 2 }
        return inset.leading + plotWidth * CGFloat(index) / CGFloat(points.count - 1)
      }

      func yPosition(for guestCount: Int) -> CGFloat {
        let fraction = CGFloat.tryzubSafeRatio(
          numerator: CGFloat(guestCount),
          denominator: CGFloat(chartMaxGuests)
        )
        return inset.top + plotHeight * (1 - fraction)
      }

      var linePoints: [CGPoint] = []
      linePoints.reserveCapacity(points.count)
      for (index, point) in points.enumerated() {
        linePoints.append(CGPoint(x: xPosition(for: index), y: yPosition(for: point.guestCount)))
      }

      if linePoints.count == 1, let point = linePoints.first {
        let dotRect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
        context.fill(Path(ellipseIn: dotRect), with: .color(TryzubColors.primaryControl.opacity(0.9)))
        return
      }

      var areaPath = smoothPath(through: linePoints)
      areaPath.addLine(to: CGPoint(x: linePoints.last?.x ?? inset.leading, y: inset.top + plotHeight))
      areaPath.addLine(to: CGPoint(x: linePoints.first?.x ?? inset.leading, y: inset.top + plotHeight))
      areaPath.closeSubpath()

      context.fill(
        areaPath,
        with: .linearGradient(
          Gradient(colors: [
            TryzubColors.primaryControl.opacity(0.22),
            TryzubColors.primaryControl.opacity(0.04)
          ]),
          startPoint: CGPoint(x: 0, y: inset.top),
          endPoint: CGPoint(x: 0, y: inset.top + plotHeight)
        )
      )

      let strokePath = smoothPath(through: linePoints)
      context.stroke(
        strokePath,
        with: .color(TryzubColors.primaryControl.opacity(0.9)),
        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
      )

      for (index, point) in points.enumerated() where point.guestCount > 0 {
        let center = CGPoint(x: xPosition(for: index), y: yPosition(for: point.guestCount))
        let radius: CGFloat
        let fill: Color
        if point.isPeak {
          radius = 4.5
          fill = TryzubColors.primaryControl
        } else if let highlightBucketStart, highlightBucketStart == point.bucketStart {
          radius = 4
          fill = TryzubColors.primaryControl.opacity(0.85)
        } else {
          continue
        }
        let dot = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: dot), with: .color(fill))
      }
    }
    .frame(height: height.tryzubFiniteNonNegativeLayoutValue)
  }

  private var axisLabels: some View {
    HStack {
      if let first = points.first {
        Text(first.bucketLabel)
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(TryzubColors.mutedText)
      }
      Spacer(minLength: 8)
      if let peak = ReservationDensityCalculator.peakPoint(in: points) {
        Text("Peak \(peak.bucketLabel)")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(TryzubColors.primaryText)
      }
      Spacer(minLength: 8)
      if let last = points.last {
        Text(last.bucketLabel)
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(TryzubColors.mutedText)
      }
    }
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
