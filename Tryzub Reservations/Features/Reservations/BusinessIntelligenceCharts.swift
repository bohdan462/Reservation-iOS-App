//
//  BusinessIntelligenceCharts.swift
//  Tryzub Reservations
//

import Charts
import SwiftUI

struct BusinessIntelligenceChartBar: Identifiable {
    let id: String
    let label: String
    let value: Int
    var isPeak: Bool = false
}

enum BusinessIntelligenceChartData {
    private static let minimumArrivalBars = 3
    private static let minimumWeekdayBars = 2
    private static let minimumGuestMixTotal = 5
    private static let maxArrivalBars = 8

    static func arrivalBars(from rows: [BusinessFifteenMinuteBucketRowDTO]) -> [BusinessIntelligenceChartBar]? {
        let sorted = rows
            .map { row -> (row: BusinessFifteenMinuteBucketRowDTO, guests: Int) in
                let guests = row.guestsCount ?? row.reservationsCount ?? 0
                return (row, guests)
            }
            .filter { $0.guests > 0 }
            .sorted { $0.row.time < $1.row.time }

        guard sorted.count >= minimumArrivalBars else { return nil }

        let capped = downsample(sorted, limit: maxArrivalBars)
        let peakValue = capped.map(\.guests).max() ?? 0

        return capped.map { item in
            BusinessIntelligenceChartBar(
                id: item.row.time,
                label: BusinessIntelligenceFormatting.displayHour(item.row.time),
                value: item.guests,
                isPeak: item.guests == peakValue && peakValue > 0
            )
        }
    }

    static func weekdayBars(from rows: [BusinessWeekdayBucketRowDTO]) -> [BusinessIntelligenceChartBar]? {
        let bars = rows
            .map { row -> (row: BusinessWeekdayBucketRowDTO, guests: Int) in
                let guests = row.guestsCount ?? row.reservationsCount ?? 0
                return (row, guests)
            }
            .filter { $0.guests > 0 }
            .sorted {
                let left = $0.row.weekday ?? Int.max
                let right = $1.row.weekday ?? Int.max
                if left == right {
                    return ($0.row.weekdayLabel ?? "") < ($1.row.weekdayLabel ?? "")
                }
                return left < right
            }

        guard bars.count >= minimumWeekdayBars else { return nil }

        let peakValue = bars.map(\.guests).max() ?? 0
        return bars.map { item in
            let label = weekdayChartLabel(for: item.row)
            return BusinessIntelligenceChartBar(
                id: item.row.id,
                label: label,
                value: item.guests,
                isPeak: item.guests == peakValue && peakValue > 0
            )
        }
    }

    static func guestMixBars(from guests: GuestRelationshipMetricsDTO) -> [BusinessIntelligenceChartBar]? {
        let firstTime = guests.firstTimeGuestCount ?? 0
        let repeatGuests = (guests.returningGuestCount ?? 0)
            + (guests.regularGuestCount ?? 0)
            + (guests.frequentRegularCount ?? 0)
        let total = firstTime + repeatGuests

        guard total >= minimumGuestMixTotal, firstTime > 0 || repeatGuests > 0 else {
            return nil
        }

        let peakValue = max(firstTime, repeatGuests)
        return [
            BusinessIntelligenceChartBar(
                id: "new",
                label: "New",
                value: firstTime,
                isPeak: firstTime == peakValue
            ),
            BusinessIntelligenceChartBar(
                id: "repeat",
                label: "Returning",
                value: repeatGuests,
                isPeak: repeatGuests == peakValue
            ),
        ]
    }

    private static func weekdayChartLabel(for row: BusinessWeekdayBucketRowDTO) -> String {
        if let label = row.weekdayLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label.count > 5 ? String(label.prefix(3)) : label
        }

        switch row.weekday {
        case 0: return "Mon"
        case 1: return "Tue"
        case 2: return "Wed"
        case 3: return "Thu"
        case 4: return "Fri"
        case 5: return "Sat"
        case 6: return "Sun"
        default:
            return BusinessIntelligenceFormatting.missingValue
        }
    }

    private static func downsample<T>(
        _ items: [T],
        limit: Int
    ) -> [T] {
        guard items.count > limit else { return items }
        let stride = max(Double(items.count) / Double(limit), 1)
        var result: [T] = []
        var index = 0.0
        while Int(index) < items.count, result.count < limit {
            result.append(items[Int(index)])
            index += stride
        }
        return result
    }
}

struct BusinessIntelligenceVerticalBarChart: View {
    let bars: [BusinessIntelligenceChartBar]
    var height: CGFloat = 132

    private var maxValue: Int {
        max(bars.map(\.value).max() ?? 1, 1)
    }

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Label", bar.label),
                y: .value("Guests", bar.value)
            )
            .foregroundStyle(
                TryzubColors.primaryControl.opacity(bar.isPeak ? 0.85 : 0.34)
            )
            .cornerRadius(3)
        }
        .chartYScale(domain: 0...Double(maxValue))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(TryzubColors.border.opacity(0.6))
                AxisValueLabel()
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(6, max(bars.count, 1)))) { _ in
                AxisValueLabel()
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .frame(height: height.tryzubFiniteNonNegativeLayoutValue)
    }
}

struct BusinessIntelligenceHorizontalBarChart: View {
    let bars: [BusinessIntelligenceChartBar]

    private var maxValue: Int {
        max(bars.map(\.value).max() ?? 1, 1)
    }

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Guests", bar.value),
                y: .value("Label", bar.label),
                height: .ratio(0.62)
            )
            .foregroundStyle(
                TryzubColors.primaryControl.opacity(bar.isPeak ? 0.85 : 0.34)
            )
            .cornerRadius(4)
        }
        .chartYScale(domain: bars.map(\.label).reversed())
        .chartXScale(domain: 0...max(Double(maxValue) * 1.12, 1))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading) { _ in
                AxisValueLabel()
                    .font(.caption.weight(.medium))
            }
        }
        .frame(height: (CGFloat(bars.count) * 28 + 8).tryzubFiniteNonNegativeLayoutValue)
    }
}
