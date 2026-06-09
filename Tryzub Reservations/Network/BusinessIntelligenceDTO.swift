//
//  BusinessIntelligenceDTO.swift
//  Tryzub Reservations
//
//  DTOs for GET /business-intelligence/summary.
//

import Foundation

// MARK: - Summary Root

struct BusinessIntelligenceSummaryDTO: Decodable, Equatable {
    let contractVersion: String?
    let scope: String?
    let source: String?
    let dataQuality: IntelligenceDataQualityDTO?
    let range: BusinessIntelligenceRangeDTO
    let generatedAt: String?
    let summary: BusinessIntelligenceSummaryMetricsDTO
    let demand: BusinessDemandMetricsDTO
    let guestRelationships: GuestRelationshipMetricsDTO
    let risk: BusinessRiskMetricsDTO
    let breakdowns: BusinessBreakdownsDTO
    let peakWindows: [BusinessPeakWindowDTO]
    let pipeline: BusinessPipelineMetricsDTO

    enum CodingKeys: String, CodingKey {
        case contractVersion
        case scope
        case source
        case dataQuality
        case range
        case generatedAt
        case summary
        case demand
        case guestRelationships
        case risk
        case breakdowns
        case peakWindows
        case pipeline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try container.decodeIfPresent(String.self, forKey: .contractVersion)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        dataQuality = try container.decodeIfPresent(IntelligenceDataQualityDTO.self, forKey: .dataQuality)
        range = try container.decodeIfPresent(BusinessIntelligenceRangeDTO.self, forKey: .range)
            ?? BusinessIntelligenceRangeDTO(from: nil, to: nil)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        summary = try container.decodeIfPresent(BusinessIntelligenceSummaryMetricsDTO.self, forKey: .summary)
            ?? BusinessIntelligenceSummaryMetricsDTO()
        demand = try container.decodeIfPresent(BusinessDemandMetricsDTO.self, forKey: .demand)
            ?? BusinessDemandMetricsDTO()
        guestRelationships = try container.decodeIfPresent(GuestRelationshipMetricsDTO.self, forKey: .guestRelationships)
            ?? GuestRelationshipMetricsDTO()
        risk = try container.decodeIfPresent(BusinessRiskMetricsDTO.self, forKey: .risk)
            ?? BusinessRiskMetricsDTO()
        breakdowns = try container.decodeIfPresent(BusinessBreakdownsDTO.self, forKey: .breakdowns)
            ?? BusinessBreakdownsDTO()
        peakWindows = try container.decodeIfPresent([BusinessPeakWindowDTO].self, forKey: .peakWindows) ?? []
        pipeline = try container.decodeIfPresent(BusinessPipelineMetricsDTO.self, forKey: .pipeline)
            ?? BusinessPipelineMetricsDTO()
    }
}

// MARK: - Range

struct BusinessIntelligenceRangeDTO: Decodable, Equatable {
    let from: String?
    let to: String?

    init(from: String?, to: String?) {
        self.from = from
        self.to = to
    }
}

// MARK: - Summary Metrics

struct BusinessIntelligenceSummaryMetricsDTO: Decodable, Equatable {
    let totalReservations: Int?
    let activeReservations: Int?
    let completedReservations: Int?
    let cancelledReservations: Int?
    let noShowReservations: Int?
    let totalGuests: Int?
    let activeGuests: Int?
    let averagePartySize: Double?
    let largestPartySize: Int?
    let largePartyCount: Int?

    init(
        totalReservations: Int? = nil,
        activeReservations: Int? = nil,
        completedReservations: Int? = nil,
        cancelledReservations: Int? = nil,
        noShowReservations: Int? = nil,
        totalGuests: Int? = nil,
        activeGuests: Int? = nil,
        averagePartySize: Double? = nil,
        largestPartySize: Int? = nil,
        largePartyCount: Int? = nil
    ) {
        self.totalReservations = totalReservations
        self.activeReservations = activeReservations
        self.completedReservations = completedReservations
        self.cancelledReservations = cancelledReservations
        self.noShowReservations = noShowReservations
        self.totalGuests = totalGuests
        self.activeGuests = activeGuests
        self.averagePartySize = averagePartySize
        self.largestPartySize = largestPartySize
        self.largePartyCount = largePartyCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalReservations = try container.decodeFlexibleIntIfPresent(forKey: .totalReservations)
        activeReservations = try container.decodeFlexibleIntIfPresent(forKey: .activeReservations)
        completedReservations = try container.decodeFlexibleIntIfPresent(forKey: .completedReservations)
        cancelledReservations = try container.decodeFlexibleIntIfPresent(forKey: .cancelledReservations)
        noShowReservations = try container.decodeFlexibleIntIfPresent(forKey: .noShowReservations)
        totalGuests = try container.decodeFlexibleIntIfPresent(forKey: .totalGuests)
        activeGuests = try container.decodeFlexibleIntIfPresent(forKey: .activeGuests)
        averagePartySize = try container.decodeFlexibleDoubleIfPresent(forKey: .averagePartySize)
        largestPartySize = try container.decodeFlexibleIntIfPresent(forKey: .largestPartySize)
        largePartyCount = try container.decodeFlexibleIntIfPresent(forKey: .largePartyCount)
    }

    private enum CodingKeys: String, CodingKey {
        case totalReservations
        case activeReservations
        case completedReservations
        case cancelledReservations
        case noShowReservations
        case totalGuests
        case activeGuests
        case averagePartySize
        case largestPartySize
        case largePartyCount
    }
}

// MARK: - Demand

struct BusinessDemandMetricsDTO: Decodable, Equatable {
    let busiestDate: String?
    let busiestWeekday: Int?
    let busiestWeekdayLabel: String?
    let busiestHour: String?
    let peak15MinWindow: String?
    let averageLeadTimeDays: Double?
    let sameDayBookingCount: Int?
    let sameDayBookingRate: Double?
    let futureBookedGuests: Int?

    init(
        busiestDate: String? = nil,
        busiestWeekday: Int? = nil,
        busiestWeekdayLabel: String? = nil,
        busiestHour: String? = nil,
        peak15MinWindow: String? = nil,
        averageLeadTimeDays: Double? = nil,
        sameDayBookingCount: Int? = nil,
        sameDayBookingRate: Double? = nil,
        futureBookedGuests: Int? = nil
    ) {
        self.busiestDate = busiestDate
        self.busiestWeekday = busiestWeekday
        self.busiestWeekdayLabel = busiestWeekdayLabel
        self.busiestHour = busiestHour
        self.peak15MinWindow = peak15MinWindow
        self.averageLeadTimeDays = averageLeadTimeDays
        self.sameDayBookingCount = sameDayBookingCount
        self.sameDayBookingRate = sameDayBookingRate
        self.futureBookedGuests = futureBookedGuests
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        busiestDate = try container.decodeIfPresent(String.self, forKey: .busiestDate)
        busiestWeekday = try container.decodeFlexibleIntIfPresent(forKey: .busiestWeekday)
        busiestWeekdayLabel = try container.decodeIfPresent(String.self, forKey: .busiestWeekdayLabel)
        busiestHour = try container.decodeIfPresent(String.self, forKey: .busiestHour)
        peak15MinWindow = try container.decodeIfPresent(String.self, forKey: .peak15MinWindow)
        averageLeadTimeDays = try container.decodeFlexibleDoubleIfPresent(forKey: .averageLeadTimeDays)
        sameDayBookingCount = try container.decodeFlexibleIntIfPresent(forKey: .sameDayBookingCount)
        sameDayBookingRate = try container.decodeFlexibleDoubleIfPresent(forKey: .sameDayBookingRate)
        futureBookedGuests = try container.decodeFlexibleIntIfPresent(forKey: .futureBookedGuests)
    }

    private enum CodingKeys: String, CodingKey {
        case busiestDate
        case busiestWeekday
        case busiestWeekdayLabel
        case busiestHour
        case peak15MinWindow
        case averageLeadTimeDays
        case sameDayBookingCount
        case sameDayBookingRate
        case futureBookedGuests
    }
}

// MARK: - Guest Relationships

struct GuestRelationshipMetricsDTO: Decodable, Equatable {
    let estimatedUniqueGuests: Int?
    let firstTimeGuestCount: Int?
    let returningGuestCount: Int?
    let regularGuestCount: Int?
    let frequentRegularCount: Int?
    let repeatGuestRate: Double?
    let guestsWithPreferences: Int?
    let guestsWithAllergyOrAccessibilityNotes: Int?
    let guestsWithPriorNotes: Int?

    init(
        estimatedUniqueGuests: Int? = nil,
        firstTimeGuestCount: Int? = nil,
        returningGuestCount: Int? = nil,
        regularGuestCount: Int? = nil,
        frequentRegularCount: Int? = nil,
        repeatGuestRate: Double? = nil,
        guestsWithPreferences: Int? = nil,
        guestsWithAllergyOrAccessibilityNotes: Int? = nil,
        guestsWithPriorNotes: Int? = nil
    ) {
        self.estimatedUniqueGuests = estimatedUniqueGuests
        self.firstTimeGuestCount = firstTimeGuestCount
        self.returningGuestCount = returningGuestCount
        self.regularGuestCount = regularGuestCount
        self.frequentRegularCount = frequentRegularCount
        self.repeatGuestRate = repeatGuestRate
        self.guestsWithPreferences = guestsWithPreferences
        self.guestsWithAllergyOrAccessibilityNotes = guestsWithAllergyOrAccessibilityNotes
        self.guestsWithPriorNotes = guestsWithPriorNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        estimatedUniqueGuests = try container.decodeFlexibleIntIfPresent(forKey: .estimatedUniqueGuests)
        firstTimeGuestCount = try container.decodeFlexibleIntIfPresent(forKey: .firstTimeGuestCount)
        returningGuestCount = try container.decodeFlexibleIntIfPresent(forKey: .returningGuestCount)
        regularGuestCount = try container.decodeFlexibleIntIfPresent(forKey: .regularGuestCount)
        frequentRegularCount = try container.decodeFlexibleIntIfPresent(forKey: .frequentRegularCount)
        repeatGuestRate = try container.decodeFlexibleDoubleIfPresent(forKey: .repeatGuestRate)
        guestsWithPreferences = try container.decodeFlexibleIntIfPresent(forKey: .guestsWithPreferences)
        guestsWithAllergyOrAccessibilityNotes = try container.decodeFlexibleIntIfPresent(
            forKey: .guestsWithAllergyOrAccessibilityNotes
        )
        guestsWithPriorNotes = try container.decodeFlexibleIntIfPresent(forKey: .guestsWithPriorNotes)
    }

    private enum CodingKeys: String, CodingKey {
        case estimatedUniqueGuests
        case firstTimeGuestCount
        case returningGuestCount
        case regularGuestCount
        case frequentRegularCount
        case repeatGuestRate
        case guestsWithPreferences
        case guestsWithAllergyOrAccessibilityNotes
        case guestsWithPriorNotes
    }
}

// MARK: - Risk

struct BusinessRiskMetricsDTO: Decodable, Equatable {
    let cancelRate: Double?
    let noShowRate: Double?
    let needsReviewCount: Int?
    let unconfirmedCount: Int?
    let noTableCount: Int?
    let largePartyWithoutTableCount: Int?
    let possibleDuplicateCount: Int?
    let correctionOrSupersededCount: Int?

    init(
        cancelRate: Double? = nil,
        noShowRate: Double? = nil,
        needsReviewCount: Int? = nil,
        unconfirmedCount: Int? = nil,
        noTableCount: Int? = nil,
        largePartyWithoutTableCount: Int? = nil,
        possibleDuplicateCount: Int? = nil,
        correctionOrSupersededCount: Int? = nil
    ) {
        self.cancelRate = cancelRate
        self.noShowRate = noShowRate
        self.needsReviewCount = needsReviewCount
        self.unconfirmedCount = unconfirmedCount
        self.noTableCount = noTableCount
        self.largePartyWithoutTableCount = largePartyWithoutTableCount
        self.possibleDuplicateCount = possibleDuplicateCount
        self.correctionOrSupersededCount = correctionOrSupersededCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cancelRate = try container.decodeFlexibleDoubleIfPresent(forKey: .cancelRate)
        noShowRate = try container.decodeFlexibleDoubleIfPresent(forKey: .noShowRate)
        needsReviewCount = try container.decodeFlexibleIntIfPresent(forKey: .needsReviewCount)
        unconfirmedCount = try container.decodeFlexibleIntIfPresent(forKey: .unconfirmedCount)
        noTableCount = try container.decodeFlexibleIntIfPresent(forKey: .noTableCount)
        largePartyWithoutTableCount = try container.decodeFlexibleIntIfPresent(forKey: .largePartyWithoutTableCount)
        possibleDuplicateCount = try container.decodeFlexibleIntIfPresent(forKey: .possibleDuplicateCount)
        correctionOrSupersededCount = try container.decodeFlexibleIntIfPresent(forKey: .correctionOrSupersededCount)
    }

    private enum CodingKeys: String, CodingKey {
        case cancelRate
        case noShowRate
        case needsReviewCount
        case unconfirmedCount
        case noTableCount
        case largePartyWithoutTableCount
        case possibleDuplicateCount
        case correctionOrSupersededCount
    }
}

// MARK: - Breakdowns

struct BusinessBreakdownsDTO: Decodable, Equatable {
    let byStatus: [BusinessStatusBucketRowDTO]
    let byWeekday: [BusinessWeekdayBucketRowDTO]
    let byHour: [BusinessHourBucketRowDTO]
    let by15MinWindow: [BusinessFifteenMinuteBucketRowDTO]
    let byPartySizeBucket: [BusinessPartySizeBucketRowDTO]
    let bySource: [BusinessSourceBucketRowDTO]
    let byLeadTimeBucket: [BusinessLeadTimeBucketRowDTO]

    init(
        byStatus: [BusinessStatusBucketRowDTO] = [],
        byWeekday: [BusinessWeekdayBucketRowDTO] = [],
        byHour: [BusinessHourBucketRowDTO] = [],
        by15MinWindow: [BusinessFifteenMinuteBucketRowDTO] = [],
        byPartySizeBucket: [BusinessPartySizeBucketRowDTO] = [],
        bySource: [BusinessSourceBucketRowDTO] = [],
        byLeadTimeBucket: [BusinessLeadTimeBucketRowDTO] = []
    ) {
        self.byStatus = byStatus
        self.byWeekday = byWeekday
        self.byHour = byHour
        self.by15MinWindow = by15MinWindow
        self.byPartySizeBucket = byPartySizeBucket
        self.bySource = bySource
        self.byLeadTimeBucket = byLeadTimeBucket
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        byStatus = try container.decodeIfPresent([BusinessStatusBucketRowDTO].self, forKey: .byStatus) ?? []
        byWeekday = try container.decodeIfPresent([BusinessWeekdayBucketRowDTO].self, forKey: .byWeekday) ?? []
        byHour = try container.decodeIfPresent([BusinessHourBucketRowDTO].self, forKey: .byHour) ?? []
        by15MinWindow = try container.decodeIfPresent([BusinessFifteenMinuteBucketRowDTO].self, forKey: .by15MinWindow) ?? []
        byPartySizeBucket = try container.decodeIfPresent([BusinessPartySizeBucketRowDTO].self, forKey: .byPartySizeBucket) ?? []
        bySource = try container.decodeIfPresent([BusinessSourceBucketRowDTO].self, forKey: .bySource) ?? []
        byLeadTimeBucket = try container.decodeIfPresent([BusinessLeadTimeBucketRowDTO].self, forKey: .byLeadTimeBucket) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case byStatus
        case byWeekday
        case byHour
        case by15MinWindow
        case byPartySizeBucket
        case bySource
        case byLeadTimeBucket
    }
}

// MARK: - Bucket Rows

struct BusinessStatusBucketRowDTO: Decodable, Equatable, Identifiable {
    let status: String
    let reservationsCount: Int?
    let guestsCount: Int?

    var id: String { status }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        reservationsCount = try container.decodeFlexibleIntIfPresent(forKey: .reservationsCount)
            ?? container.decodeFlexibleIntIfPresent(forKey: .count)
        guestsCount = try container.decodeFlexibleIntIfPresent(forKey: .guestsCount)
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case reservationsCount
        case guestsCount
        case count
    }
}

struct BusinessWeekdayBucketRowDTO: Decodable, Equatable, Identifiable {
    let weekday: Int?
    let weekdayLabel: String?
    let reservationsCount: Int?
    let guestsCount: Int?

    var id: String {
        if let weekdayLabel, !weekdayLabel.isEmpty {
            return weekdayLabel
        }
        return "weekday-\(weekday ?? -1)"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekday = try container.decodeFlexibleIntIfPresent(forKey: .weekday)
        weekdayLabel = try container.decodeIfPresent(String.self, forKey: .weekdayLabel)
        reservationsCount = try container.decodeFlexibleIntIfPresent(forKey: .reservationsCount)
            ?? container.decodeFlexibleIntIfPresent(forKey: .count)
        guestsCount = try container.decodeFlexibleIntIfPresent(forKey: .guestsCount)
    }

    private enum CodingKeys: String, CodingKey {
        case weekday
        case weekdayLabel
        case reservationsCount
        case guestsCount
        case count
    }
}

struct BusinessHourBucketRowDTO: Decodable, Equatable, Identifiable {
    let hour: String
    let reservationsCount: Int?
    let guestsCount: Int?

    var id: String { hour }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intHour = try container.decodeFlexibleIntIfPresent(forKey: .hour) {
            hour = String(format: "%02d:00", intHour)
        } else {
            hour = try container.decodeIfPresent(String.self, forKey: .hour) ?? "unknown"
        }
        reservationsCount = try container.decodeFlexibleIntIfPresent(forKey: .reservationsCount)
            ?? container.decodeFlexibleIntIfPresent(forKey: .count)
        guestsCount = try container.decodeFlexibleIntIfPresent(forKey: .guestsCount)
    }

    private enum CodingKeys: String, CodingKey {
        case hour
        case reservationsCount
        case guestsCount
        case count
    }
}

struct BusinessFifteenMinuteBucketRowDTO: Decodable, Equatable, Identifiable {
    let time: String
    let reservationsCount: Int?
    let guestsCount: Int?

    var id: String { time }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedTime = try container.decodeIfPresent(String.self, forKey: .time),
           !decodedTime.isEmpty {
            time = decodedTime
        } else if let legacyWindow = try container.decodeIfPresent(String.self, forKey: .window),
                  !legacyWindow.isEmpty {
            time = legacyWindow
        } else {
            time = "unknown"
        }
        reservationsCount = try container.decodeFlexibleIntIfPresent(forKey: .reservationsCount)
            ?? container.decodeFlexibleIntIfPresent(forKey: .count)
        guestsCount = try container.decodeFlexibleIntIfPresent(forKey: .guestsCount)
    }

    private enum CodingKeys: String, CodingKey {
        case time
        case window
        case reservationsCount
        case guestsCount
        case count
    }
}

struct BusinessPartySizeBucketRowDTO: Decodable, Equatable, Identifiable {
    let bucket: String
    let reservationsCount: Int?
    let guestsCount: Int?

    var id: String { bucket }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bucket = try container.decodeIfPresent(String.self, forKey: .bucket) ?? "unknown"
        reservationsCount = try container.decodeFlexibleIntIfPresent(forKey: .reservationsCount)
            ?? container.decodeFlexibleIntIfPresent(forKey: .count)
        guestsCount = try container.decodeFlexibleIntIfPresent(forKey: .guestsCount)
    }

    private enum CodingKeys: String, CodingKey {
        case bucket
        case reservationsCount
        case guestsCount
        case count
    }
}

struct BusinessSourceBucketRowDTO: Decodable, Equatable, Identifiable {
    let source: String
    let reservationsCount: Int?
    let guestsCount: Int?

    var id: String { source }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "unknown"
        reservationsCount = try container.decodeFlexibleIntIfPresent(forKey: .reservationsCount)
            ?? container.decodeFlexibleIntIfPresent(forKey: .count)
        guestsCount = try container.decodeFlexibleIntIfPresent(forKey: .guestsCount)
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case reservationsCount
        case guestsCount
        case count
    }
}

struct BusinessLeadTimeBucketRowDTO: Decodable, Equatable, Identifiable {
    let bucket: String
    let reservationsCount: Int?
    let guestsCount: Int?

    var id: String { bucket }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bucket = try container.decodeIfPresent(String.self, forKey: .bucket) ?? "unknown"
        reservationsCount = try container.decodeFlexibleIntIfPresent(forKey: .reservationsCount)
            ?? container.decodeFlexibleIntIfPresent(forKey: .count)
        guestsCount = try container.decodeFlexibleIntIfPresent(forKey: .guestsCount)
    }

    private enum CodingKeys: String, CodingKey {
        case bucket
        case reservationsCount
        case guestsCount
        case count
    }
}

// MARK: - Peak Windows

struct BusinessPeakWindowDTO: Decodable, Equatable, Identifiable {
    let weekday: Int?
    let weekdayLabel: String?
    let time: String?
    let averageGuests: Double?
    let reservationCount: Int?
    let sampleCount: Int?

    var id: String {
        "\(weekdayLabel ?? "day")-\(time ?? "time")-\(reservationCount ?? 0)"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekday = try container.decodeFlexibleIntIfPresent(forKey: .weekday)
        weekdayLabel = try container.decodeIfPresent(String.self, forKey: .weekdayLabel)
        time = try container.decodeIfPresent(String.self, forKey: .time)
        averageGuests = try container.decodeFlexibleDoubleIfPresent(forKey: .averageGuests)
        reservationCount = try container.decodeFlexibleIntIfPresent(forKey: .reservationCount)
        sampleCount = try container.decodeFlexibleIntIfPresent(forKey: .sampleCount)
    }

    private enum CodingKeys: String, CodingKey {
        case weekday
        case weekdayLabel
        case time
        case averageGuests
        case reservationCount
        case sampleCount
    }
}

// MARK: - Pipeline

struct BusinessPipelineMetricsDTO: Decodable, Equatable {
    let newCount: Int?
    let needsReviewCount: Int?
    let confirmedCount: Int?
    let seatedCount: Int?
    let completedCount: Int?
    let cancelledCount: Int?
    let noShowCount: Int?

    init(
        newCount: Int? = nil,
        needsReviewCount: Int? = nil,
        confirmedCount: Int? = nil,
        seatedCount: Int? = nil,
        completedCount: Int? = nil,
        cancelledCount: Int? = nil,
        noShowCount: Int? = nil
    ) {
        self.newCount = newCount
        self.needsReviewCount = needsReviewCount
        self.confirmedCount = confirmedCount
        self.seatedCount = seatedCount
        self.completedCount = completedCount
        self.cancelledCount = cancelledCount
        self.noShowCount = noShowCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        newCount = try container.decodeFlexibleIntIfPresent(forKey: .newCount)
        needsReviewCount = try container.decodeFlexibleIntIfPresent(forKey: .needsReviewCount)
        confirmedCount = try container.decodeFlexibleIntIfPresent(forKey: .confirmedCount)
        seatedCount = try container.decodeFlexibleIntIfPresent(forKey: .seatedCount)
        completedCount = try container.decodeFlexibleIntIfPresent(forKey: .completedCount)
        cancelledCount = try container.decodeFlexibleIntIfPresent(forKey: .cancelledCount)
        noShowCount = try container.decodeFlexibleIntIfPresent(forKey: .noShowCount)
    }

    private enum CodingKeys: String, CodingKey {
        case newCount
        case needsReviewCount
        case confirmedCount
        case seatedCount
        case completedCount
        case cancelledCount
        case noShowCount
    }
}
