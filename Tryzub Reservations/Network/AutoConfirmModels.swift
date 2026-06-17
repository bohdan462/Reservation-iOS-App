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

    init(rules: [AutoConfirmRule], excludedDates: [String]) {
        self.rules = rules
        self.excludedDates = excludedDates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rules = try container.decodeIfPresent([AutoConfirmRule].self, forKey: .rules) ?? []
        excludedDates = try container.decodeIfPresent([String].self, forKey: .excludedDates) ?? []
    }
}

struct AutoConfirmRule: Codable, Equatable, Identifiable {
    let id: String
    let enabled: Bool
    let weekday: Int
    let startTime: String
    let endTime: String
    let maxPartySize: Int

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

    init(used: Int, limit: Int, remaining: Int) {
        self.used = used
        self.limit = limit
        self.remaining = remaining
    }

    /// Normalizes optional backend fields into a coherent usage window, or nil when usage is unknown.
    static func normalized(from raw: EmailUsageRawWindow?, fallbackLimit: Int) -> EmailUsageWindow? {
        guard let raw else { return nil }

        let resolvedUsed = raw.resolvedUsedCount
        let hasUsed = resolvedUsed != nil
        let hasRemaining = raw.remaining != nil
        let hasLimit = raw.limit != nil && (raw.limit ?? 0) > 0

        guard hasUsed || hasRemaining || hasLimit else { return nil }

        let limitValue = (raw.limit ?? 0) > 0 ? (raw.limit ?? 0) : fallbackLimit
        guard limitValue > 0 else { return nil }

        if hasRemaining, let remaining = raw.remaining {
            let clampedRemaining = min(max(remaining, 0), limitValue)
            var usedValue = max(resolvedUsed ?? 0, 0)

            if !hasUsed && usedValue == 0 {
                if clampedRemaining < limitValue {
                    usedValue = limitValue - clampedRemaining
                } else if clampedRemaining == 0 {
                    usedValue = limitValue
                }
            }

            return EmailUsageWindow(
                used: min(usedValue, limitValue),
                limit: limitValue,
                remaining: clampedRemaining
            )
        }

        if hasUsed, let resolvedUsed {
            let usedValue = min(max(resolvedUsed, 0), limitValue)
            return EmailUsageWindow(
                used: usedValue,
                limit: limitValue,
                remaining: max(limitValue - usedValue, 0)
            )
        }

        return nil
    }
}

struct EmailUsageRawWindow: Codable, Equatable {
    let used: Int?
    let limit: Int?
    let remaining: Int?

    enum CodingKeys: String, CodingKey {
        case used
        case sent
        case limit
        case remaining
    }

    init(used: Int?, limit: Int?, remaining: Int?) {
        self.used = used
        self.limit = limit
        self.remaining = remaining
    }

    /// Prefers explicit `used`, then backend `sent`, for display as "used".
    var resolvedUsedCount: Int? {
        used
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let explicitUsed = try container.decodeFlexibleIntIfPresent(forKey: .used)
        let sent = try container.decodeFlexibleIntIfPresent(forKey: .sent)
        used = explicitUsed ?? sent
        limit = try container.decodeFlexibleIntIfPresent(forKey: .limit)
        remaining = try container.decodeFlexibleIntIfPresent(forKey: .remaining)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(used, forKey: .used)
        try container.encodeIfPresent(limit, forKey: .limit)
        try container.encodeIfPresent(remaining, forKey: .remaining)
    }
}

struct EmailUsageSummary: Codable, Equatable {
    let dailyRaw: EmailUsageRawWindow?
    let monthlyRaw: EmailUsageRawWindow?

    enum CodingKeys: String, CodingKey {
        case daily
        case monthly
    }

    init(dailyRaw: EmailUsageRawWindow?, monthlyRaw: EmailUsageRawWindow?) {
        self.dailyRaw = dailyRaw
        self.monthlyRaw = monthlyRaw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dailyRaw = try container.decodeIfPresent(EmailUsageRawWindow.self, forKey: .daily)
        monthlyRaw = try container.decodeIfPresent(EmailUsageRawWindow.self, forKey: .monthly)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(dailyRaw, forKey: .daily)
        try container.encodeIfPresent(monthlyRaw, forKey: .monthly)
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

    var dailyValueText: String? {
        guard let daily else { return nil }
        return "\(daily.used) / \(daily.limit) used · \(daily.remaining) left"
    }

    var monthlyValueText: String? {
        guard let monthly else { return nil }
        return "\(monthly.used) / \(monthly.limit) used · \(monthly.remaining) left"
    }

    var dailyDisplayText: String? {
        guard let dailyValueText else { return nil }
        return "Resend today: \(dailyValueText)"
    }

    var monthlyDisplayText: String? {
        guard let monthlyValueText else { return nil }
        return "Resend this month: \(monthlyValueText)"
    }

    static func resolving(
        setup: RestaurantSetup,
        status: ReservationReminderStatusResponse?
    ) -> ResolvedEmailUsage {
        let source = status?.emailUsage ?? setup.emailUsage
        return ResolvedEmailUsage(
            daily: EmailUsageWindow.normalized(
                from: source?.dailyRaw,
                fallbackLimit: setup.emailDailyLimit
            ),
            monthly: EmailUsageWindow.normalized(
                from: source?.monthlyRaw,
                fallbackLimit: setup.emailMonthlyLimit
            )
        )
    }
}

// MARK: - Codable Verification

enum AutoConfirmModelCodableVerification {
    static func makeAPIJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func makeAPIJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    @discardableResult
    static func runAll() -> [String] {
        var errors: [String] = []
        errors.append(contentsOf: verifyAutoConfirmPolicyRoundTrip())
        errors.append(contentsOf: verifyEmailUsageSentDecode())

        #if DEBUG
        if errors.isEmpty {
            print("[AutoConfirmCodableVerify] passed")
        } else {
            print("[AutoConfirmCodableVerify] failed: \(errors.joined(separator: "; "))")
        }
        #endif

        return errors
    }

    static func verifyAutoConfirmPolicyRoundTrip() -> [String] {
        var errors: [String] = []
        let json = """
        {
          "rules": [
            {
              "id": "test_tue_1700_1800",
              "enabled": true,
              "weekday": 1,
              "start_time": "17:00:00",
              "end_time": "18:00:00",
              "max_party_size": 4
            }
          ],
          "excluded_dates": []
        }
        """

        do {
            let decoded = try makeAPIJSONDecoder().decode(
                AutoConfirmPolicy.self,
                from: Data(json.utf8)
            )

            guard decoded.rules.count == 1 else {
                errors.append("expected 1 decoded rule, got \(decoded.rules.count)")
                return errors
            }

            let rule = decoded.rules[0]
            if rule.startTime != "17:00:00" {
                errors.append("startTime expected 17:00:00, got \(rule.startTime)")
            }
            if rule.endTime != "18:00:00" {
                errors.append("endTime expected 18:00:00, got \(rule.endTime)")
            }
            if rule.maxPartySize != 4 {
                errors.append("maxPartySize expected 4, got \(rule.maxPartySize)")
            }

            let encoded = try makeAPIJSONEncoder().encode(decoded)
            guard let encodedString = String(data: encoded, encoding: .utf8) else {
                errors.append("encoded policy was not UTF-8")
                return errors
            }

            for requiredKey in ["start_time", "end_time", "max_party_size", "excluded_dates"] {
                if !encodedString.contains(requiredKey) {
                    errors.append("encoded policy missing \(requiredKey)")
                }
            }

            for leakedKey in ["startTime", "endTime", "maxPartySize", "excludedDates"] {
                if encodedString.contains(leakedKey) {
                    errors.append("encoded policy leaked camelCase key \(leakedKey)")
                }
            }
        } catch {
            errors.append("auto-confirm round trip failed: \(error.localizedDescription)")
        }

        return errors
    }

    static func verifyEmailUsageSentDecode() -> [String] {
        var errors: [String] = []
        let json = """
        {
          "sent": 7,
          "limit": 100,
          "remaining": 93
        }
        """

        do {
            let decoded = try makeAPIJSONDecoder().decode(
                EmailUsageRawWindow.self,
                from: Data(json.utf8)
            )

            if decoded.used != 7 {
                errors.append("sent decode expected used=7, got \(decoded.used.map(String.init) ?? "nil")")
            }

            guard let normalized = EmailUsageWindow.normalized(from: decoded, fallbackLimit: 100) else {
                errors.append("email usage normalization returned nil")
                return errors
            }

            if normalized.used != 7 {
                errors.append("normalized used expected 7, got \(normalized.used)")
            }
            if normalized.remaining != 93 {
                errors.append("normalized remaining expected 93, got \(normalized.remaining)")
            }
        } catch {
            errors.append("email usage sent decode failed: \(error.localizedDescription)")
        }

        return errors
    }
}

#if DEBUG
private let _autoConfirmModelCodableVerificationRunOnce: [String] = AutoConfirmModelCodableVerification.runAll()
#endif
