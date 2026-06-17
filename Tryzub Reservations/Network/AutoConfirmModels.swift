//
//  AutoConfirmModels.swift
//  Tryzub Reservations
//
//  Backend auto-confirm dry-run and email usage models (db 1.10.0).
//

import Foundation

// MARK: - Defaults

enum AutoConfirmDefaults {
    static let enabled = false
    static let requireEmail = true
    static let blockGuestNotes = true
    static let blockDuplicates = true
    static let blockSuspicious = true
    static let policy = AutoConfirmPolicy(rules: [], excludedDates: [])
    static let emailDailyLimit = 100
    static let emailMonthlyLimit = 3000
}

// MARK: - Policy

struct AutoConfirmPolicy: Codable, Equatable {
    let rules: [AutoConfirmRule]
    let excludedDates: [String]

    enum CodingKeys: String, CodingKey {
        case rules
        case excludedDates = "excluded_dates"
    }

    init(rules: [AutoConfirmRule], excludedDates: [String]) {
        self.rules = rules
        self.excludedDates = excludedDates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = try container.decodeIfPresent([AutoConfirmRule].self, forKey: .rules) ?? []
        excludedDates = try container.decodeIfPresent([String].self, forKey: .excludedDates) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rules, forKey: .rules)
        try container.encode(excludedDates, forKey: .excludedDates)
    }
}

struct AutoConfirmRule: Codable, Equatable, Identifiable {
    let id: String
    let enabled: Bool
    let weekday: Int
    let startTime: String
    let endTime: String
    let maxPartySize: Int

    enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case weekday
        case startTime = "start_time"
        case endTime = "end_time"
        case maxPartySize = "max_party_size"
    }

    init(
        id: String,
        enabled: Bool,
        weekday: Int,
        startTime: String,
        endTime: String,
        maxPartySize: Int
    ) {
        self.id = id
        self.enabled = enabled
        self.weekday = weekday
        self.startTime = startTime
        self.endTime = endTime
        self.maxPartySize = maxPartySize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        enabled = try container.decodeFlexibleBoolIfPresent(forKey: .enabled) ?? false
        weekday = try container.decodeFlexibleIntIfPresent(forKey: .weekday) ?? 0
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime) ?? ""
        endTime = try container.decodeIfPresent(String.self, forKey: .endTime) ?? ""
        maxPartySize = try container.decodeFlexibleIntIfPresent(forKey: .maxPartySize) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(weekday, forKey: .weekday)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(maxPartySize, forKey: .maxPartySize)
    }
}

// MARK: - Validation

enum AutoConfirmPolicyValidation {
    static let validWeekdayRange = 0...6
    static let validMaxPartySizeRange = 1...20

    static func validate(policy: AutoConfirmPolicy) -> [String] {
        var messages: [String] = []

        var seenRuleIDs: Set<String> = []
        for rule in policy.rules {
            messages.append(contentsOf: validate(rule: rule))

            let trimmedID = rule.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedID.isEmpty {
                messages.append("Each auto-confirm rule needs an id.")
            } else if seenRuleIDs.contains(trimmedID) {
                messages.append("Duplicate auto-confirm rule id: \(trimmedID).")
            } else {
                seenRuleIDs.insert(trimmedID)
            }
        }

        for date in policy.excludedDates {
            if !RestaurantAutomationTimeValidation.isValidDateKey(date) {
                messages.append("Excluded date must use YYYY-MM-DD format.")
            }
        }

        return messages
    }

    static func validate(rule: AutoConfirmRule) -> [String] {
        var messages: [String] = []

        if !validWeekdayRange.contains(rule.weekday) {
            messages.append("Rule \(rule.id): weekday must be 0–6.")
        }

        if !validMaxPartySizeRange.contains(rule.maxPartySize) {
            messages.append("Rule \(rule.id): max party size must be 1–20.")
        }

        if !RestaurantAutomationTimeValidation.isValidTime(rule.startTime) {
            messages.append("Rule \(rule.id): start time must use HH:mm or HH:mm:ss.")
        }

        if !RestaurantAutomationTimeValidation.isValidTime(rule.endTime) {
            messages.append("Rule \(rule.id): end time must use HH:mm or HH:mm:ss.")
        }

        if RestaurantAutomationTimeValidation.isValidTime(rule.startTime),
           RestaurantAutomationTimeValidation.isValidTime(rule.endTime),
           let startMinutes = RestaurantAutomationTimeValidation.minutes(from: rule.startTime),
           let endMinutes = RestaurantAutomationTimeValidation.minutes(from: rule.endTime),
           endMinutes <= startMinutes {
            messages.append("Rule \(rule.id): end time must be after start time.")
        }

        return messages
    }
}

enum RestaurantAutomationTimeValidation {
    private static let timePatterns = [
        #"^\d{2}:\d{2}$"#,
        #"^\d{2}:\d{2}:\d{2}$"#
    ]

    private static let dateKeyPattern = #"^\d{4}-\d{2}-\d{2}$"#

    static func isValidTime(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return timePatterns.contains { trimmed.range(of: $0, options: .regularExpression) != nil }
    }

    static func minutes(from value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidTime(trimmed) else { return nil }

        let normalized = trimmed.count >= 5 ? String(trimmed.prefix(5)) : trimmed
        let parts = normalized.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }

        return hour * 60 + minute
    }

    static func isValidDateKey(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: dateKeyPattern, options: .regularExpression) != nil else {
            return false
        }
        return ReservationFormatters.reservationDateKey.date(from: trimmed) != nil
    }
}

// MARK: - Dry Run

struct AutoConfirmCandidateResponse: Codable, Equatable {
    let success: Bool
    let date: String
    let data: [AutoConfirmCandidate]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        data = try container.decodeIfPresent([AutoConfirmCandidate].self, forKey: .data) ?? []
    }
}

struct AutoConfirmCandidate: Codable, Equatable, Identifiable {
    var id: Int { reservationId }

    let reservationId: Int
    let reservationTime: String?
    let partySize: Int
    let status: String
    let sourceType: String
    let eligible: Bool
    let matchingRuleId: String?
    let matchingRuleMaxPartySize: Int?
    let blockedReasons: [String]

    enum CodingKeys: String, CodingKey {
        case reservationId
        case reservationTime
        case partySize
        case status
        case sourceType
        case eligible
        case matchingRuleId
        case matchingRuleMaxPartySize
        case blockedReasons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reservationId = try container.decodeFlexibleIntIfPresent(forKey: .reservationId) ?? 0
        reservationTime = try container.decodeIfPresent(String.self, forKey: .reservationTime)
        partySize = try container.decodeFlexibleIntIfPresent(forKey: .partySize) ?? 0
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType) ?? ""
        eligible = try container.decodeFlexibleBoolIfPresent(forKey: .eligible) ?? false
        matchingRuleId = try container.decodeIfPresent(String.self, forKey: .matchingRuleId)
        matchingRuleMaxPartySize = try container.decodeFlexibleIntIfPresent(forKey: .matchingRuleMaxPartySize)
        blockedReasons = try container.decodeIfPresent([String].self, forKey: .blockedReasons) ?? []
    }
}

enum AutoConfirmBlockedReasonLabels {
    static func displayText(for reason: String) -> String {
        switch reason.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "auto_confirm_disabled":
            return "Auto-confirm is off"
        case "no_matching_auto_confirm_rule":
            return "Outside enabled auto-confirm time"
        case "excluded_date":
            return "Date excluded"
        case "not_form_source":
            return "Not from website form"
        case "not_new_status":
            return "Not a new reservation"
        case "hidden_or_superseded":
            return "Hidden or superseded"
        case "party_too_large_for_rule":
            return "Party too large for this rule"
        case "no_email":
            return "No guest email"
        case "duplicate_or_correction":
            return "Possible duplicate/correction"
        case "suspicious_contact":
            return "Contact info needs review"
        case "has_staff_notes":
            return "Has staff notes"
        case "has_guest_notes":
            return "Has guest notes"
        case "provider_not_configured":
            return "Email provider not configured"
        case "confirmation_already_sent":
            return "Confirmation already sent"
        case "terminal_status":
            return "Reservation is already terminal"
        case "email_daily_limit_reached":
            return "Daily email limit reached"
        case "email_monthly_limit_reached":
            return "Monthly email limit reached"
        default:
            return reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Email Usage

struct EmailUsageWindow: Codable, Equatable {
    let used: Int
    let limit: Int
    let remaining: Int

    enum CodingKeys: String, CodingKey {
        case used
        case limit
        case remaining
    }

    init(used: Int, limit: Int, remaining: Int) {
        self.used = used
        self.limit = limit
        self.remaining = remaining
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        used = try container.decodeFlexibleIntIfPresent(forKey: .used) ?? 0
        limit = try container.decodeFlexibleIntIfPresent(forKey: .limit) ?? 0
        remaining = try container.decodeFlexibleIntIfPresent(forKey: .remaining) ?? 0
    }
}

struct EmailUsageSummary: Codable, Equatable {
    let daily: EmailUsageWindow?
    let monthly: EmailUsageWindow?

    init(daily: EmailUsageWindow?, monthly: EmailUsageWindow?) {
        self.daily = daily
        self.monthly = monthly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        daily = try container.decodeIfPresent(EmailUsageWindow.self, forKey: .daily)
        monthly = try container.decodeIfPresent(EmailUsageWindow.self, forKey: .monthly)
    }
}

struct ResolvedEmailUsage: Equatable {
    let daily: EmailUsageWindow?
    let monthly: EmailUsageWindow?

    var hasUsageData: Bool {
        daily != nil || monthly != nil
    }

    var isDailyLimitReached: Bool {
        guard let daily else { return false }
        return daily.remaining <= 0
    }

    var dailyDisplayText: String? {
        guard let daily else { return nil }
        return "Resend today: \(daily.used) / \(daily.limit) used"
    }

    var monthlyDisplayText: String? {
        guard let monthly else { return nil }
        return "Resend this month: \(monthly.used) / \(monthly.limit) used"
    }

    static func resolving(
        setup: RestaurantSetup,
        status: ReservationReminderStatusResponse?
    ) -> ResolvedEmailUsage {
        let source = status?.emailUsage ?? setup.emailUsage
        return ResolvedEmailUsage(
            daily: resolvedWindow(source?.daily, fallbackLimit: setup.emailDailyLimit),
            monthly: resolvedWindow(source?.monthly, fallbackLimit: setup.emailMonthlyLimit)
        )
    }

    private static func resolvedWindow(
        _ window: EmailUsageWindow?,
        fallbackLimit: Int
    ) -> EmailUsageWindow? {
        guard let window else { return nil }
        let limit = window.limit > 0 ? window.limit : fallbackLimit
        let remaining = window.limit > 0
            ? window.remaining
            : max(limit - window.used, 0)
        return EmailUsageWindow(used: window.used, limit: limit, remaining: remaining)
    }
}
