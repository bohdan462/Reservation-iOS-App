//
//  APIClient.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import Foundation
import OSLog

// MARK: - Request Reasons

enum ReservationAPIRequestReason: String {
    case unspecified
    case ping
    case startupToday = "startup_today"
    case manualToday = "manual_today"
    case autoToday = "auto_today"
    case autoSkipCooldown = "auto_skip_cooldown"
    case failureCount = "failure_count"
    case importFailuresFull = "import_failures_full"
    case scheduleWindow = "schedule_window"
    case scheduleAllPage = "schedule_all_page"
    case reviewQueues = "review_queues"
    case mutationPatch = "mutation_patch"
    case mutationConfirm = "mutation_confirm"
    case mutationCreate = "mutation_create"
    case hiddenReservations = "hidden_reservations"
    case restaurantSetup = "restaurant_setup"
    case restaurantSetupPatch = "restaurant_setup_patch"
    case restaurantHours = "restaurant_hours"
    case restaurantHoursPatch = "restaurant_hours_patch"
    case restaurantDayAvailability = "restaurant_day_availability"
    case restaurantDayAvailabilityPatch = "restaurant_day_availability_patch"
    case reservationSlots = "reservation_slots"
    case restaurantBlockedSlots = "restaurant_blocked_slots"
    case restaurantBlockedSlotsCreate = "restaurant_blocked_slots_create"
    case restaurantBlockedSlotsDelete = "restaurant_blocked_slots_delete"
    case reservationAnalyticsSummary = "reservation_analytics_summary"
    case reconcileByID = "reconcile_by_id"
    case manualSkipBusy = "manual_skip_busy"
    case manualSkipCooldown = "manual_skip_cooldown"
    case scopeSkipInFlight = "scope_skip_in_flight"
    case autoSkipBusy = "auto_skip_busy"
    case autoSkipInactive = "auto_skip_inactive"
}

// MARK: - Sanitized Request Logging

enum ReservationAPILogger {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "APIDiagnostics"
    )

    static func start(request: URLRequest, reason: ReservationAPIRequestReason) -> Date {
        let startedAt = Date()
        append(
            outcome: .started,
            request: request,
            reason: reason,
            duration: nil
        )
        guard isEnabled else { return startedAt }

        emit("[API] START reason=\(reason.rawValue) method=\(request.httpMethod ?? "GET") \(sanitizedPathAndQuery(for: request.url))")
        return startedAt
    }

    static func end(
        request: URLRequest,
        reason: ReservationAPIRequestReason,
        statusCode: Int,
        startedAt: Date
    ) {
        append(
            outcome: .succeeded,
            request: request,
            reason: reason,
            statusCode: statusCode,
            duration: duration(since: startedAt)
        )
        guard isEnabled else { return }

        emit("[API] END reason=\(reason.rawValue) status=\(statusCode) duration=\(duration(since: startedAt)) \(sanitizedPathAndQuery(for: request.url))")
    }

    static func fail(
        request: URLRequest,
        reason: ReservationAPIRequestReason,
        error: Error,
        startedAt: Date
    ) {
        let diagnostics = (error as? ReservationAPIError)?.diagnostics
        append(
            outcome: .failed,
            request: request,
            reason: reason,
            error: errorLogValue(error),
            duration: duration(since: startedAt),
            responseBodySnippet: diagnostics?.responseBodySnippet,
            decodingError: diagnostics?.decodingError
        )
        guard isEnabled else { return }

        emit("[API] FAIL reason=\(reason.rawValue) error=\(errorLogValue(error)) duration=\(duration(since: startedAt)) \(sanitizedPathAndQuery(for: request.url))")
    }

    static func cancelled(
        request: URLRequest,
        reason: ReservationAPIRequestReason,
        startedAt: Date
    ) {
        append(
            outcome: .cancelled,
            request: request,
            reason: reason,
            error: "cancelled",
            duration: duration(since: startedAt)
        )
        guard isEnabled else { return }

        emit("[API] CANCELLED reason=\(reason.rawValue) duration=\(duration(since: startedAt)) \(sanitizedPathAndQuery(for: request.url))")
    }

    static func skip(reason: ReservationAPIRequestReason, message: String) {
        Task { @MainActor in
            APIRequestLogStore.shared.append(
                APIRequestLogEvent(
                    outcome: .skipped,
                    reason: reason,
                    message: message
                )
            )
        }
        guard isEnabled else { return }

        emit("[API] SKIP reason=\(reason.rawValue) \(message)")
    }

    static func retry(
        request: URLRequest,
        reason: ReservationAPIRequestReason,
        error: URLError,
        attempt: Int,
        delayMilliseconds: Int
    ) {
        guard isEnabled else { return }

        emit("[API] RETRY reason=\(reason.rawValue) attempt=\(attempt) error=\(error.errorCode) delayMs=\(delayMilliseconds) \(sanitizedPathAndQuery(for: request.url))")
    }

    private static func append(
        outcome: APIRequestLogOutcome,
        request: URLRequest,
        reason: ReservationAPIRequestReason,
        statusCode: Int? = nil,
        error: String? = nil,
        duration: String? = nil,
        responseBodySnippet: String? = nil,
        decodingError: String? = nil
    ) {
        let method = request.httpMethod ?? "GET"
        let pathAndQuery = sanitizedPathAndQuery(for: request.url)

        Task { @MainActor in
            APIRequestLogStore.shared.append(
                APIRequestLogEvent(
                    outcome: outcome,
                    reason: reason,
                    method: method,
                    pathAndQuery: pathAndQuery,
                    statusCode: statusCode,
                    error: error,
                    duration: duration,
                    responseBodySnippet: responseBodySnippet,
                    decodingError: decodingError
                )
            )
        }
    }

    // Intent: Debug request paths without credentials or guest search text.
    // Search query is redacted; Authorization header is never logged.
    private static func sanitizedPathAndQuery(for url: URL?) -> String {
        guard let url else { return "path=<unknown>" }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "path=\(url.path)"
        }

        components.scheme = nil
        components.host = nil
        components.port = nil
        components.user = nil
        components.password = nil

        components.queryItems = components.queryItems?.map { item in
            if item.name.lowercased() == "search" {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            return item
        }

        return "path=\(components.path) query=\(components.percentEncodedQuery ?? "")"
    }

    private static func duration(since startedAt: Date) -> String {
        String(format: "%.2fs", Date().timeIntervalSince(startedAt))
    }

    private static func emit(_ message: String) {
    
        print(message)
    }

    private static func errorLogValue(_ error: Error) -> String {
        if let apiError = error as? ReservationAPIError {
            return apiError.logValue
        }

        if let urlError = error as? URLError {
            return "\(urlError.errorCode)"
        }

        return String(describing: error)
    }
}

// MARK: - API Client Contract

protocol ReservationsAPIClientProtocol: AnyObject {
    var debugBaseURLDescription: String { get }
    var hasConfiguredCredentials: Bool { get }

    func ping(reason: ReservationAPIRequestReason) async throws -> PingResponseDTO
    func fetchReservations(
        page: Int,
        perPage: Int,
        date: String?,
        from: String?,
        to: String?,
        status: ReservationStatus?,
        search: String?,
        includeHidden: Bool,
        retryCount: Int,
        reason: ReservationAPIRequestReason
    ) async throws -> ReservationsResponse

    func fetchAllReservations(
        perPage: Int,
        date: String?,
        from: String?,
        to: String?,
        status: ReservationStatus?,
        search: String?,
        includeHidden: Bool,
        reason: ReservationAPIRequestReason
    ) async throws -> [ReservationDTO]

    func fetchReservation(id: Int, retryCount: Int, reason: ReservationAPIRequestReason) async throws -> ReservationDTO
    func updateReservation(id: Int, request: ReservationUpdateRequest, reason: ReservationAPIRequestReason) async throws -> ReservationDTO
    func createReservation(_ createRequest: ReservationCreateRequest, reason: ReservationAPIRequestReason) async throws -> ReservationDTO
    func confirmReservation(id: Int, reason: ReservationAPIRequestReason) async throws -> ReservationConfirmResponse
    func fetchRestaurantSetup(reason: ReservationAPIRequestReason) async throws -> RestaurantSetupDTO
    func updateRestaurantSetup(_ request: RestaurantSetupUpdateRequest, reason: ReservationAPIRequestReason) async throws -> RestaurantSetupDTO
    func fetchRestaurantHours(from: String?, to: String?, reason: ReservationAPIRequestReason) async throws -> RestaurantHoursDTO
    func updateRestaurantHours(_ request: WeeklyHoursUpdateRequest, reason: ReservationAPIRequestReason) async throws -> RestaurantHoursDTO
    func fetchRestaurantDayAvailability(date: String, reason: ReservationAPIRequestReason) async throws -> RestaurantDayAvailabilityDTO
    func updateRestaurantDayAvailability(date: String, request: RestaurantDayAvailabilityUpdateRequest, reason: ReservationAPIRequestReason) async throws -> RestaurantDayAvailabilityDTO
    func fetchReservationSlots(date: String, reason: ReservationAPIRequestReason) async throws -> ReservationSlotsResponseDTO
    func fetchRestaurantBlockedSlots(date: String, reason: ReservationAPIRequestReason) async throws -> RestaurantBlockedSlotsResponseDTO
    func createRestaurantBlockedSlots(date: String, slots: [String], reason: String?, requestReason: ReservationAPIRequestReason) async throws -> RestaurantBlockedSlotsResponseDTO
    func deleteRestaurantBlockedSlots(date: String, slots: [String], reason: ReservationAPIRequestReason) async throws -> RestaurantBlockedSlotsResponseDTO
    func deleteAllRestaurantBlockedSlots(date: String, reason: ReservationAPIRequestReason) async throws -> RestaurantBlockedSlotsResponseDTO
    func fetchReservationAnalyticsSummary(from: String?, to: String?, reason: ReservationAPIRequestReason) async throws -> ReservationAnalyticsSummaryDTO
    func fetchImportFailures(page: Int, perPage: Int, reason: ReservationAPIRequestReason) async throws -> ImportFailuresResponse
}

// MARK: - Default Protocol Convenience

extension ReservationsAPIClientProtocol {
    func fetchReservations(
        page: Int,
        perPage: Int,
        date: String?,
        from: String?,
        to: String?,
        status: ReservationStatus?,
        search: String?,
        includeHidden: Bool = false,
        reason: ReservationAPIRequestReason = .unspecified
    ) async throws -> ReservationsResponse {
        try await fetchReservations(
            page: page,
            perPage: perPage,
            date: date,
            from: from,
            to: to,
            status: status,
            search: search,
            includeHidden: includeHidden,
            retryCount: 0,
            reason: reason
        )
    }

    func fetchReservation(id: Int) async throws -> ReservationDTO {
        try await fetchReservation(id: id, retryCount: 0, reason: .unspecified)
    }

    func createRestaurantBlockedSlots(date: String, slots: [String], reason: String?) async throws -> RestaurantBlockedSlotsResponseDTO {
        try await createRestaurantBlockedSlots(
            date: date,
            slots: slots,
            reason: reason,
            requestReason: .restaurantBlockedSlotsCreate
        )
    }
}

// MARK: - WordPress Reservations API Client

final class ReservationsAPIClient: ReservationsAPIClientProtocol {
    // MARK: - Dependencies

    private let baseURL: URL
    private let username: String
    private let applicationPassword: String
    private let session: URLSession

    var debugBaseURLDescription: String {
        baseURL.absoluteString
    }

    var hasConfiguredCredentials: Bool {
        !username.isEmpty && !applicationPassword.isEmpty
    }

    // MARK: - Coding

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: configuration)
    }()

    // MARK: - Initialization

    init(baseURL: URL,
         username: String,
         applicationPassword: String,
         session: URLSession = ReservationsAPIClient.defaultSession) {
        
        self.baseURL = baseURL
        self.username = username
        self.applicationPassword = applicationPassword
        self.session = session
    }

    // MARK: - Health

    // Intent: Verifies public API reachability without protected credentials.
    // Network: GET /ping.
    func ping(reason: ReservationAPIRequestReason = .ping) async throws -> PingResponseDTO {
        let url = try apiURL(path: "ping")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await perform(request, retryCount: 0, reason: reason, requiresAuth: false)
        return try decode(PingResponseDTO.self, from: data, request: request)
    }

    // MARK: - Reservations

    // Intent: Reads managed reservations for today, schedule windows, review queues, or search.
    // Network: GET /managed-reservations with query filters.
    func fetchReservations(
        page: Int = 1,
        perPage: Int = 20,
        date: String? = nil,
        from: String? = nil,
        to: String? = nil,
        status: ReservationStatus? = nil,
        search: String? = nil,
        includeHidden: Bool = false,
        retryCount: Int = 0,
        reason: ReservationAPIRequestReason = .unspecified
    ) async throws -> ReservationsResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        if let date = date {
            queryItems.append(URLQueryItem(name: "date", value: date))
        }
        if let from = from {
            queryItems.append(URLQueryItem(name: "from", value: from))
        }
        if let to = to {
            queryItems.append(URLQueryItem(name: "to", value: to))
        }
        if let status = status {
            queryItems.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        if let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        if includeHidden {
            queryItems.append(URLQueryItem(name: "include_hidden", value: "1"))
        }

        let url = try makeURL(path: "managed-reservations", queryItems: queryItems)
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, retryCount: retryCount, reason: reason)

        let response = try decode(
            ReservationsResponse.self,
            from: data,
            request: request
        )
        ReservationSyncDiagnostics.apiListResponse(
            reason: reason,
            total: response.total,
            reservations: response.data,
            label: "fetchReservations(page=\(page))"
        )
        return response
    }

    // Intent: Paginates list reads so sync services can cache the full matching result.
    // Network: GET /managed-reservations across all pages.
    func fetchAllReservations(
        perPage: Int = 100,
        date: String? = nil,
        from: String? = nil,
        to: String? = nil,
        status: ReservationStatus? = nil,
        search: String? = nil,
        includeHidden: Bool = false,
        reason: ReservationAPIRequestReason = .unspecified
    ) async throws -> [ReservationDTO] {
        let cappedPerPage = min(max(perPage, 1), 100)
        var currentPage = 1
        var allReservations: [ReservationDTO] = []
        var totalPages = 1

        repeat {
            let response = try await fetchReservations(
                page: currentPage,
                perPage: cappedPerPage,
                date: date,
                from: from,
                to: to,
                status: status,
                search: search,
                includeHidden: includeHidden,
                reason: reason
            )

            allReservations.append(contentsOf: response.data)
            totalPages = max(response.totalPages, 1)
            currentPage += 1
        } while currentPage <= totalPages

        ReservationSyncDiagnostics.apiListResponse(
            reason: reason,
            total: nil,
            reservations: allReservations,
            label: "fetchAllReservations"
        )
        return allReservations
    }

    // MARK: - Fetch One Reservation

    // Intent: Reconciles one reservation after an uncertain mutation or diagnostics check.
    // Network: GET /managed-reservations/{id}.
    func fetchReservation(
        id: Int,
        retryCount: Int = 1,
        reason: ReservationAPIRequestReason = .unspecified
    ) async throws -> ReservationDTO {
        let url = try apiURL(path: "managed-reservations/\(id)")
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, retryCount: retryCount, reason: reason)

        return try decode(ReservationFetchResponse.self, from: data, request: request).data
    }

    // MARK: - Reservation Mutations

    // Intent: Server-first reservation edit, including confirm-without-email via status=confirmed.
    // Network: PATCH /managed-reservations/{id}.
    func updateReservation(
        id: Int,
        request updateRequest: ReservationUpdateRequest,
        reason: ReservationAPIRequestReason = .mutationPatch
    ) async throws -> ReservationDTO {
        let url = try apiURL(path: "managed-reservations/\(id)")

        let request = try makeJSONRequest(url: url, method: "PATCH", body: updateRequest)
        let data = try await perform(request, reason: reason)

        return try decode(ReservationUpdateResponse.self, from: data, request: request).data
    }

    // Intent: Staff creates a manual/call-in reservation.
    // Network: POST /managed-reservations.
    func createReservation(
        _ createRequest: ReservationCreateRequest,
        reason: ReservationAPIRequestReason = .mutationCreate
    ) async throws -> ReservationDTO {
        let url = try apiURL(path: "managed-reservations")
        let request = try makeJSONRequest(
            url: url,
            method: "POST",
            body: createRequest
        )
        let data = try await perform(request, reason: reason)

        return try decode(ReservationCreateResponse.self, from: data, request: request).data
    }

    // MARK: - Confirm With Email

    // Intent: Confirms reservation and asks backend to send/record confirmation email.
    // Network: POST /managed-reservations/{id}/confirm.
    // Rename note: This method name should mention email in a later cleanup.
    func confirmReservation(
        id: Int,
        reason: ReservationAPIRequestReason = .mutationConfirm
    ) async throws -> ReservationConfirmResponse {
        let url = try apiURL(path: "managed-reservations/\(id)/confirm")
        let request = makeRequest(url: url, method: "POST")
        let data = try await perform(request, reason: reason)

        return try decode(ReservationConfirmResponse.self, from: data, request: request)
    }

    // MARK: - Restaurant Setup

    // Intent: Reads the lightweight restaurant setup table used by manual-create defaults and settings.
    // Network: GET /restaurant-setup.
    func fetchRestaurantSetup(
        reason: ReservationAPIRequestReason = .restaurantSetup
    ) async throws -> RestaurantSetupDTO {
        let url = try apiURL(path: "restaurant-setup")
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: reason)

        return try decodeRestaurantSetup(from: data, request: request)
    }

    // Intent: Updates minimal manager-facing restaurant setup fields.
    // Network: PATCH /restaurant-setup.
    func updateRestaurantSetup(
        _ setupRequest: RestaurantSetupUpdateRequest,
        reason: ReservationAPIRequestReason = .restaurantSetupPatch
    ) async throws -> RestaurantSetupDTO {
        let url = try apiURL(path: "restaurant-setup")
        let request = try makeJSONRequest(
            url: url,
            method: "PATCH",
            body: setupRequest
        )
        let data = try await perform(request, reason: reason)

        return try decodeRestaurantSetup(from: data, request: request)
    }

    // MARK: - Restaurant Hours

    // Intent: Reads backend weekly/special hours for staff settings.
    // Network: GET /restaurant-hours.
    func fetchRestaurantHours(
        from: String? = nil,
        to: String? = nil,
        reason: ReservationAPIRequestReason = .restaurantHours
    ) async throws -> RestaurantHoursDTO {
        var queryItems: [URLQueryItem] = []
        if let from {
            queryItems.append(URLQueryItem(name: "from", value: from))
        }
        if let to {
            queryItems.append(URLQueryItem(name: "to", value: to))
        }

        let url = try makeURL(path: "restaurant-hours", queryItems: queryItems)
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: reason)

        return try decodeRestaurantHours(from: data, request: request)
    }

    // Intent: Saves manager-facing weekly hours.
    // Network: PATCH /restaurant-hours.
    func updateRestaurantHours(
        _ hoursRequest: WeeklyHoursUpdateRequest,
        reason: ReservationAPIRequestReason = .restaurantHoursPatch
    ) async throws -> RestaurantHoursDTO {
        let url = try apiURL(path: "restaurant-hours")
        let request = try makeJSONRequest(
            url: url,
            method: "PATCH",
            body: hoursRequest
        )
        let data = try await perform(request, reason: reason)

        return try decodeRestaurantHours(from: data, request: request)
    }

    // MARK: - Availability

    // Intent: Reads effective availability for one service date.
    // Network: GET /restaurant-day-availability?date=YYYY-MM-DD.
    func fetchRestaurantDayAvailability(
        date: String,
        reason: ReservationAPIRequestReason = .restaurantDayAvailability
    ) async throws -> RestaurantDayAvailabilityDTO {
        let url = try makeURL(
            path: "restaurant-day-availability",
            queryItems: [URLQueryItem(name: "date", value: date)]
        )
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: reason)

        return try decodeRestaurantDayAvailability(from: data, request: request)
    }

    // Intent: Saves a manual open/closed override for one date.
    // Network: PATCH /restaurant-day-availability?date=YYYY-MM-DD.
    func updateRestaurantDayAvailability(
        date: String,
        request availabilityRequest: RestaurantDayAvailabilityUpdateRequest,
        reason: ReservationAPIRequestReason = .restaurantDayAvailabilityPatch
    ) async throws -> RestaurantDayAvailabilityDTO {
        let url = try makeURL(
            path: "restaurant-day-availability",
            queryItems: [URLQueryItem(name: "date", value: date)]
        )
        let request = try makeJSONRequest(url: url, method: "PATCH", body: availabilityRequest)
        let data = try await perform(request, reason: reason)

        return try decodeRestaurantDayAvailability(from: data, request: request)
    }

    // MARK: - Slots

    // Intent: Previews backend-computed slots for one date.
    // Network: GET /reservation-slots?date=YYYY-MM-DD.
    func fetchReservationSlots(
        date: String,
        reason: ReservationAPIRequestReason = .reservationSlots
    ) async throws -> ReservationSlotsResponseDTO {
        let url = try makeURL(
            path: "reservation-slots",
            queryItems: [URLQueryItem(name: "date", value: date)]
        )
        let request = makeRequest(url: url, method: "GET", requiresAuth: false)
        let data = try await perform(request, reason: reason, requiresAuth: false)

        return try decode(ReservationSlotsResponseDTO.self, from: data, request: request)
    }

    // MARK: - Blocked Slots

    // Intent: Reads public-form slots that staff have blocked for one date.
    // Network: GET /restaurant-blocked-slots?date=YYYY-MM-DD.
    func fetchRestaurantBlockedSlots(
        date: String,
        reason: ReservationAPIRequestReason = .restaurantBlockedSlots
    ) async throws -> RestaurantBlockedSlotsResponseDTO {
        let url = try makeURL(
            path: "restaurant-blocked-slots",
            queryItems: [URLQueryItem(name: "date", value: date)]
        )
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: reason)

        return try decodeRestaurantBlockedSlots(from: data, fallbackDate: date, request: request)
    }

    // Intent: Removes specific generated public slots from one service date.
    // Network: POST /restaurant-blocked-slots.
    func createRestaurantBlockedSlots(
        date: String,
        slots: [String],
        reason blockReason: String?,
        requestReason: ReservationAPIRequestReason = .restaurantBlockedSlotsCreate
    ) async throws -> RestaurantBlockedSlotsResponseDTO {
        let url = try apiURL(path: "restaurant-blocked-slots")
        let request = try makeJSONRequest(
            url: url,
            method: "POST",
            body: RestaurantBlockedSlotsCreateRequest(
                date: date,
                slots: slots,
                reason: blockReason
            )
        )
        let data = try await perform(request, reason: requestReason)

        return try decodeRestaurantBlockedSlots(from: data, fallbackDate: date, request: request)
    }

    // Intent: Restores specific public slots for one service date.
    // Network: DELETE /restaurant-blocked-slots with JSON body.
    func deleteRestaurantBlockedSlots(
        date: String,
        slots: [String],
        reason: ReservationAPIRequestReason = .restaurantBlockedSlotsDelete
    ) async throws -> RestaurantBlockedSlotsResponseDTO {
        let url = try apiURL(path: "restaurant-blocked-slots")
        let request = try makeJSONRequest(
            url: url,
            method: "DELETE",
            body: RestaurantBlockedSlotsDeleteRequest(date: date, slots: slots)
        )
        let data = try await perform(request, reason: reason)

        return try decodeRestaurantBlockedSlots(from: data, fallbackDate: date, request: request)
    }

    // Intent: Clears every blocked public slot for one service date.
    // Network: DELETE /restaurant-blocked-slots?date=YYYY-MM-DD.
    func deleteAllRestaurantBlockedSlots(
        date: String,
        reason: ReservationAPIRequestReason = .restaurantBlockedSlotsDelete
    ) async throws -> RestaurantBlockedSlotsResponseDTO {
        let url = try makeURL(
            path: "restaurant-blocked-slots",
            queryItems: [URLQueryItem(name: "date", value: date)]
        )
        let request = makeRequest(url: url, method: "DELETE")
        let data = try await perform(request, reason: reason)

        return try decodeRestaurantBlockedSlots(from: data, fallbackDate: date, request: request)
    }

    // MARK: - Analytics

    // Intent: Reads backend aggregate metrics without downloading historical reservations.
    // Network: GET /reservation-analytics/summary.
    func fetchReservationAnalyticsSummary(
        from: String? = nil,
        to: String? = nil,
        reason: ReservationAPIRequestReason = .reservationAnalyticsSummary
    ) async throws -> ReservationAnalyticsSummaryDTO {
        var queryItems: [URLQueryItem] = []
        if let from {
            queryItems.append(URLQueryItem(name: "from", value: from))
        }
        if let to {
            queryItems.append(URLQueryItem(name: "to", value: to))
        }

        let url = try makeURL(path: "reservation-analytics/summary", queryItems: queryItems)
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: reason)

        return try decode(ReservationAnalyticsSummaryDTO.self, from: data, request: request)
    }

    // MARK: - Import Failure Diagnostics

    // Intent: Developer/manager reads failed public-form imports.
    // Network: GET /managed-reservations/import-failures.
    func fetchImportFailures(
        page: Int = 1,
        perPage: Int = 50,
        reason: ReservationAPIRequestReason = .importFailuresFull
    ) async throws -> ImportFailuresResponse {
        let url = try makeURL(
            path: "managed-reservations/import-failures",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
        )
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, retryCount: 0, reason: reason)

        return try decode(ImportFailuresResponse.self, from: data, request: request)
    }

    // MARK: - Request Helpers

    private func apiURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var url = baseURL
        for segment in trimmedPath.split(separator: "/") where !segment.isEmpty {
            url = url.appendingPathComponent(String(segment))
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ReservationAPIError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let finalURL = components.url else {
            throw ReservationAPIError.invalidURL
        }

        return finalURL
    }

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        try apiURL(path: path, queryItems: queryItems)
    }

    // Authorization header is attached here and never passed to sanitized logging output.
    private func makeRequest(url: URL, method: String, requiresAuth: Bool = true) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if requiresAuth {
            request.setValue(makeAuthHeader(), forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func makeJSONRequest<T: Encodable>(
        url: URL,
        method: String,
        body: T,
        requiresAuth: Bool = true
    ) throws -> URLRequest {
        var request = makeRequest(url: url, method: method, requiresAuth: requiresAuth)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        request: URLRequest
    ) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            let diagnostics = ReservationAPIDiagnostics.make(
                request: request,
                response: nil,
                data: data,
                decodingError: error
            )
            throw ReservationAPIError.decodingFailure(error, diagnostics: diagnostics)
        }
    }

    private func decodeRestaurantSetup(from data: Data, request: URLRequest) throws -> RestaurantSetupDTO {
        do {
            if let envelope = try? decoder.decode(RestaurantSetupResponse.self, from: data),
               let setup = envelope.data {
                return setup
            }

            return try decoder.decode(RestaurantSetupDTO.self, from: data)
        } catch {
            let diagnostics = ReservationAPIDiagnostics.make(
                request: request,
                response: nil,
                data: data,
                decodingError: error
            )
            throw ReservationAPIError.decodingFailure(error, diagnostics: diagnostics)
        }
    }

    private func decodeRestaurantHours(from data: Data, request: URLRequest) throws -> RestaurantHoursDTO {
        do {
            if let envelope = try? decoder.decode(RestaurantHoursResponse.self, from: data),
               let hours = envelope.data {
                return hours
            }

            return try decoder.decode(RestaurantHoursDTO.self, from: data)
        } catch {
            let diagnostics = ReservationAPIDiagnostics.make(
                request: request,
                response: nil,
                data: data,
                decodingError: error
            )
            throw ReservationAPIError.decodingFailure(error, diagnostics: diagnostics)
        }
    }

    private func decodeRestaurantDayAvailability(
        from data: Data,
        request: URLRequest
    ) throws -> RestaurantDayAvailabilityDTO {
        do {
            if let envelope = try? decoder.decode(RestaurantDayAvailabilityResponse.self, from: data),
               let availability = envelope.data {
                return availability
            }

            return try decoder.decode(RestaurantDayAvailabilityDTO.self, from: data)
        } catch {
            let diagnostics = ReservationAPIDiagnostics.make(
                request: request,
                response: nil,
                data: data,
                decodingError: error
            )
            throw ReservationAPIError.decodingFailure(error, diagnostics: diagnostics)
        }
    }

    private func decodeRestaurantBlockedSlots(
        from data: Data,
        fallbackDate: String,
        request: URLRequest
    ) throws -> RestaurantBlockedSlotsResponseDTO {
        do {
            if let envelope = try? decoder.decode(RestaurantBlockedSlotsResponse.self, from: data),
               let blockedSlots = envelope.data {
                return RestaurantBlockedSlotsResponseDTO(
                    success: envelope.success ?? true,
                    date: envelope.date ?? fallbackDate,
                    data: blockedSlots
                )
            }

            return try decoder.decode(RestaurantBlockedSlotsResponseDTO.self, from: data)
        } catch {
            let diagnostics = ReservationAPIDiagnostics.make(
                request: request,
                response: nil,
                data: data,
                decodingError: error
            )
            throw ReservationAPIError.decodingFailure(error, diagnostics: diagnostics)
        }
    }
    
    private func makeAuthHeader() -> String {
        let loginString = "\(username):\(applicationPassword)"
        let loginData = loginString.data(using: .utf8)
        let base64LoginString = loginData?.base64EncodedString() ?? ""
        
        return "Basic \(base64LoginString)"
    }

    private func ensureProtectedCredentials() throws {
        guard hasConfiguredCredentials else {
            throw ReservationAPIError.missingCredentials
        }
    }

    // MARK: - Network Execution

    // Intent: Performs one API request with bounded retry for transient network errors.
    private func perform(
        _ request: URLRequest,
        retryCount: Int = 0,
        reason: ReservationAPIRequestReason = .unspecified,
        requiresAuth: Bool = true
    ) async throws -> Data {
        if requiresAuth {
            try ensureProtectedCredentials()
        }

        var attempt = 0
        var lastNetworkError: URLError?
        let startedAt = ReservationAPILogger.start(request: request, reason: reason)
        let effectiveRetryCount = request.httpMethod?.uppercased() == "GET"
            ? max(retryCount, 1)
            : retryCount

        while attempt <= effectiveRetryCount {
            do {
                let (data, response) = try await session.data(for: request)
                try validate(response: response, data: data, request: request)
                ReservationAPILogger.end(
                    request: request,
                    reason: reason,
                    statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                    startedAt: startedAt
                )
                return data
            } catch is CancellationError {
                ReservationAPILogger.cancelled(request: request, reason: reason, startedAt: startedAt)
                throw ReservationAPIError.cancelled
            } catch let error as URLError {
                if error.code == .cancelled {
                    ReservationAPILogger.cancelled(request: request, reason: reason, startedAt: startedAt)
                    throw ReservationAPIError.cancelled
                }

                lastNetworkError = error

                guard error.isRetryableGETError,
                      attempt < effectiveRetryCount else {
                    let apiError = ReservationAPIError.networkFailure(error)
                    ReservationAPILogger.fail(request: request, reason: reason, error: apiError, startedAt: startedAt)
                    throw apiError
                }

                attempt += 1
                let delayMilliseconds = 650 * attempt
                ReservationAPILogger.retry(
                    request: request,
                    reason: reason,
                    error: error,
                    attempt: attempt,
                    delayMilliseconds: delayMilliseconds
                )

                do {
                    try await Task.sleep(for: .milliseconds(delayMilliseconds))
                } catch {
                    ReservationAPILogger.cancelled(request: request, reason: reason, startedAt: startedAt)
                    throw ReservationAPIError.cancelled
                }
            } catch {
                if error.isCancellationLike {
                    ReservationAPILogger.cancelled(request: request, reason: reason, startedAt: startedAt)
                    throw ReservationAPIError.cancelled
                }

                ReservationAPILogger.fail(request: request, reason: reason, error: error, startedAt: startedAt)
                throw error
            }
        }

        let apiError = ReservationAPIError.networkFailure(lastNetworkError ?? URLError(.unknown))
        ReservationAPILogger.fail(request: request, reason: reason, error: apiError, startedAt: startedAt)
        throw apiError
    }

    // MARK: - Response Validation

    private func validate(response: URLResponse, data: Data, request: URLRequest) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReservationAPIError.invalidResponse(
                diagnostics: ReservationAPIDiagnostics.make(
                    request: request,
                    response: nil,
                    data: data
                )
            )
        }

        let diagnostics = ReservationAPIDiagnostics.make(
            request: request,
            response: httpResponse,
            data: data
        )

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw ReservationAPIError.unauthorized(diagnostics: diagnostics)
        default:
            if let apiError = try? JSONDecoder().decode(WordPressAPIError.self, from: data) {
                throw ReservationAPIError.wordpressError(
                    code: apiError.code,
                    message: apiError.message,
                    statusCode: httpResponse.statusCode,
                    diagnostics: diagnostics
                )
            }
            throw ReservationAPIError.serverError(
                statusCode: httpResponse.statusCode,
                diagnostics: diagnostics
            )
        }
    }
}

// MARK: - WordPress Error Payload

private struct WordPressAPIError: Decodable {
    let code: String
    let message: String
}

// MARK: - Retry Classification

private extension URLError {
    var isRetryableGETError: Bool {
        switch code {
        case .networkConnectionLost,
             .timedOut:
            return true
        default:
            return false
        }
    }
}
