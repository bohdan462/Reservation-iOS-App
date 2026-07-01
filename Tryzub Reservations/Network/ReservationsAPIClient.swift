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
    case login
    case ping
    case startupToday = "startup_today"
    case manualToday = "manual_today"
    case activeWindow = "active_window"
    case activeWindowDelta = "active_window_delta"
    case autoToday = "auto_today"
    case autoTodayDelta = "auto_today_delta"
    case siriHostSummary = "siri_host_summary"
    case autoSkipCooldown = "auto_skip_cooldown"
    case failureCount = "failure_count"
    case importFailuresFull = "import_failures_full"
    case cancelledReservations = "cancelled_reservations"
    case cancelledReservationsPage = "cancelled_reservations_page"
    case scheduleWindow = "schedule_window"
    case scheduleAllPage = "schedule_all_page"
    case scheduleDate = "schedule_date"
    case reviewQueues = "review_queues"
    case mutationPatch = "mutation_patch"
    case mutationConfirm = "mutation_confirm"
    case resendConfirmation = "resend_confirmation"
    case confirmByPhone = "confirm_by_phone"
    case reminderBatch = "reminder_batch"
    case reminderStatus = "reminder_status"
    case autoConfirmCandidates = "auto_confirm_candidates"
    case mutationCreate = "mutation_create"
    case guestManageLink = "guest_manage_link"
    case manualEmailLog = "manual_email_log"
    case hardDelete = "hard_delete"
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
    case businessIntelligenceSummary = "business_intelligence_summary"
    case guestIntelligence = "guest_intelligence"
    case guestProfileLookup = "guest_profile_lookup"
    case intelligenceSystemStatus = "intelligence_system_status"
    case reconcileByID = "reconcile_by_id"
    case floorPlan = "floor_plan"
    case restaurantTables = "restaurant_tables"
    case restaurantTablesPut = "restaurant_tables_put"
    case reservationTablesPatch = "reservation_tables_patch"
    case reservationActivity = "reservation_activity"
    case activityFeed = "activity_feed"
    case reservationAttachments = "reservation_attachments"
    case reservationAttachmentUpload = "reservation_attachment_upload"
    case reservationAttachmentPatch = "reservation_attachment_patch"
    case reservationAttachmentDelete = "reservation_attachment_delete"
    case reservationAttachmentContent = "reservation_attachment_content"
    case manualSkipBusy = "manual_skip_busy"
    case manualSkipCooldown = "manual_skip_cooldown"
    case scopeSkipInFlight = "scope_skip_in_flight"
    case scopeSkipFresh = "scope_skip_fresh"
    case scheduleAllBlocked = "schedule_all_page_blocked"
    case autoSkipBusy = "auto_skip_busy"
    case autoSkipInactive = "auto_skip_inactive"

    var suppressesResponseBodyLogging: Bool {
        switch self {
        case .businessIntelligenceSummary,
             .guestIntelligence,
             .guestProfileLookup,
             .intelligenceSystemStatus,
             .reservationAttachmentContent:
            return true
        default:
            return false
        }
    }
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
        startedAt: Date,
        responseBodySnippet: String? = nil
    ) {
        append(
            outcome: .succeeded,
            request: request,
            reason: reason,
            statusCode: statusCode,
            duration: duration(since: startedAt),
            responseBodySnippet: responseBodySnippet
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
            let name = item.name.lowercased()
            if name == "search" || name == "phone" || name == "email" || name == "q" {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            if name.contains("token") {
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

protocol ReservationsAPIClientProtocol: AnyObject, Sendable {
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
        updatedSince: String?,
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
    func resendConfirmation(id: Int, reason: ReservationAPIRequestReason) async throws -> ReservationDTO
    func confirmReservationByPhone(id: Int, reason: ReservationAPIRequestReason) async throws -> ReservationDTO
    func sendDueReminders(date: String?, reason: ReservationAPIRequestReason) async throws -> ReservationReminderBatchResponse
    func fetchReminderStatus(date: String, reason: ReservationAPIRequestReason) async throws -> ReservationReminderStatusResponse
    func fetchAutoConfirmCandidates(date: Date, reason: ReservationAPIRequestReason) async throws -> AutoConfirmCandidateResponse
    func createGuestManageLink(id: Int, reason: ReservationAPIRequestReason) async throws -> ReservationGuestManageLinkDTO
    func logManualEmail(reservationID: Int, request: ReservationManualEmailLogRequest, reason: ReservationAPIRequestReason) async throws -> ReservationManualEmailLogDTO
    func hardDeleteReservation(id: Int, reason: ReservationAPIRequestReason) async throws -> ReservationDeleteResponse
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
    func fetchBusinessIntelligenceSummary(
        from: String,
        to: String,
        reason: ReservationAPIRequestReason
    ) async throws -> BusinessIntelligenceSummaryDTO
    func fetchGuestIntelligence(
        date: String,
        reason: ReservationAPIRequestReason
    ) async throws -> GuestIntelligenceDayResponseDTO
    func fetchGuestIntelligenceProfile(
        reservationID: Int,
        reason: ReservationAPIRequestReason
    ) async throws -> GuestIntelligenceProfilePackDTO
    func fetchGuestProfiles(
        query: String?,
        filter: String?,
        sort: String?,
        page: Int,
        perPage: Int,
        updatedSince: String?
    ) async throws -> GuestProfileListResponseDTO
    func fetchGuestProfileLookup(
        phone: String?,
        email: String?,
        query: String?,
        limit: Int
    ) async throws -> GuestProfileLookupResponseDTO
    func fetchGuestProfile(guestKey: String) async throws -> GuestProfileDTO
    func fetchGuestProfile(byReservationID reservationID: Int) async throws -> GuestProfileDTO
    func fetchIntelligenceSystemStatus(
        from: String,
        to: String,
        reason: ReservationAPIRequestReason
    ) async throws -> IntelligenceSystemStatusDTO
    func fetchImportFailures(page: Int, perPage: Int, reason: ReservationAPIRequestReason) async throws -> ImportFailuresResponse
    func fetchRestaurantTables(reason: ReservationAPIRequestReason) async throws -> [RestaurantTableDTO]
    func putRestaurantTables(_ tables: [RestaurantTableDTO], reason: ReservationAPIRequestReason) async throws -> [RestaurantTableDTO]
    func fetchFloorPlan(date: String, reason: ReservationAPIRequestReason) async throws -> FloorPlanResponseDTO
    func patchReservationTables(
        reservationID: Int,
        request: PatchReservationTablesRequest,
        reason: ReservationAPIRequestReason
    ) async throws -> FloorPlanPatchResponseDTO
    func fetchReservationActivity(
        reservationID: Int,
        page: Int,
        perPage: Int,
        reason: ReservationAPIRequestReason
    ) async throws -> ReservationActivityResponseDTO
    func fetchActivityFeed(
        date: Date,
        page: Int,
        perPage: Int,
        reason: ReservationAPIRequestReason
    ) async throws -> ReservationActivityFeedResponseDTO
    func fetchActivityFeed(
        from: Date,
        to: Date,
        page: Int,
        perPage: Int,
        reason: ReservationAPIRequestReason
    ) async throws -> ReservationActivityFeedResponseDTO
    func listReservationAttachments(reservationID: Int) async throws -> ReservationAttachmentListResponseDTO
    func uploadReservationAttachment(
        reservationID: Int,
        jpegData: Data,
        originalFilename: String,
        label: AttachmentLabel,
        caption: String?
    ) async throws -> ReservationAttachmentDTO
    func updateReservationAttachment(
        reservationID: Int,
        attachmentID: Int,
        label: AttachmentLabel,
        caption: String?
    ) async throws -> ReservationAttachmentDTO
    func deleteReservationAttachment(
        reservationID: Int,
        attachmentID: Int
    ) async throws
    func downloadReservationAttachmentContent(
        reservationID: Int,
        attachmentID: Int
    ) async throws -> Data
}

// MARK: - Default Protocol Convenience

extension ReservationsAPIClientProtocol {
    func fetchGuestProfiles(
        query: String?,
        filter: String?,
        sort: String?,
        page: Int,
        perPage: Int
    ) async throws -> GuestProfileListResponseDTO {
        try await fetchGuestProfiles(
            query: query,
            filter: filter,
            sort: sort,
            page: page,
            perPage: perPage,
            updatedSince: nil
        )
    }

    func fetchReservations(
        page: Int,
        perPage: Int,
        date: String?,
        from: String?,
        to: String?,
        status: ReservationStatus?,
        search: String?,
        includeHidden: Bool = false,
        updatedSince: String? = nil,
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
            updatedSince: updatedSince,
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

    func fetchReservationActivity(
        reservationID: Int,
        page: Int = 1,
        perPage: Int = 25
    ) async throws -> ReservationActivityResponseDTO {
        try await fetchReservationActivity(
            reservationID: reservationID,
            page: page,
            perPage: perPage,
            reason: .reservationActivity
        )
    }

    func fetchActivityFeed(
        date: Date,
        page: Int = 1,
        perPage: Int = 50
    ) async throws -> ReservationActivityFeedResponseDTO {
        try await fetchActivityFeed(
            date: date,
            page: page,
            perPage: perPage,
            reason: .activityFeed
        )
    }

    func fetchActivityFeed(
        from: Date,
        to: Date,
        page: Int = 1,
        perPage: Int = 50
    ) async throws -> ReservationActivityFeedResponseDTO {
        try await fetchActivityFeed(
            from: from,
            to: to,
            page: page,
            perPage: perPage,
            reason: .activityFeed
        )
    }
}

// MARK: - WordPress Reservations API Client

final class ReservationsAPIClient: ReservationsAPIClientProtocol {
    // MARK: - Dependencies

    private let baseURL: URL
    private let username: String
    private let applicationPassword: String
    private let authRole: AppUserRole?
    private let session: URLSession
    private let requestSerializer = ReservationAPIRequestSerializer()

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
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: configuration)
    }()

    private static let longRunningIntelligenceSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 75
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: configuration)
    }()

    // MARK: - Initialization

    init(baseURL: URL,
         username: String,
         applicationPassword: String,
         role: AppUserRole? = nil,
         session: URLSession = ReservationsAPIClient.defaultSession) {
        
        self.baseURL = baseURL
        self.username = username
        self.applicationPassword = applicationPassword
        self.authRole = role
        self.session = session
    }

    // MARK: - Health

    // Intent: Verifies public API reachability without protected credentials.
    // Network: GET /ping.
    func ping(reason: ReservationAPIRequestReason = .ping) async throws -> PingResponseDTO {
        let url = try apiURL(path: "ping")
        let request = makeRequest(url: url, method: "GET", requiresAuth: false)
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
        updatedSince: String? = nil,
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
        if let updatedSince = updatedSince?.trimmingCharacters(in: .whitespacesAndNewlines),
           !updatedSince.isEmpty {
            queryItems.append(URLQueryItem(name: "updated_since", value: updatedSince))
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
                updatedSince: nil,
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

        let response = try decode(ReservationUpdateResponse.self, from: data, request: request)
        traceOptionalMutationActivity(reservationID: id, activity: response.activity)
        return response.data
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

        let response = try decode(ReservationCreateResponse.self, from: data, request: request)
        traceOptionalMutationActivity(reservationID: response.data.id, activity: response.activity)
        return response.data
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

        let response = try decode(ReservationConfirmResponse.self, from: data, request: request)
        traceOptionalMutationActivity(reservationID: id, activity: response.activity)
        return response
    }

    // Intent: Resends a failed/suppressed/complained confirmation after staff correction.
    // Network: POST /managed-reservations/{id}/resend-confirmation.
    func resendConfirmation(
        id: Int,
        reason: ReservationAPIRequestReason = .resendConfirmation
    ) async throws -> ReservationDTO {
        let url = try apiURL(path: "managed-reservations/\(id)/resend-confirmation")
        let request = makeRequest(url: url, method: "POST")
        let data = try await perform(request, reason: reason)

        let response = try decode(ReservationCorrectionResponse.self, from: data, request: request)
        guard response.success else {
            throw ReservationAPIError.wordpressError(
                code: "tryzub_resend_confirmation_failed",
                message: response.emailError ?? response.message ?? "Could not resend confirmation.",
                statusCode: 200,
                diagnostics: ReservationAPIDiagnostics.make(request: request, response: nil, data: data)
            )
        }
        return response.data
    }

    // Intent: Records staff phone confirmation without marking email delivered.
    // Network: POST /managed-reservations/{id}/confirm-by-phone.
    func confirmReservationByPhone(
        id: Int,
        reason: ReservationAPIRequestReason = .confirmByPhone
    ) async throws -> ReservationDTO {
        let url = try apiURL(path: "managed-reservations/\(id)/confirm-by-phone")
        let request = makeRequest(url: url, method: "POST")
        let data = try await perform(request, reason: reason)

        let response = try decode(ReservationCorrectionResponse.self, from: data, request: request)
        guard response.success else {
            throw ReservationAPIError.wordpressError(
                code: "tryzub_confirm_by_phone_failed",
                message: response.message ?? "Could not confirm by phone.",
                statusCode: 200,
                diagnostics: ReservationAPIDiagnostics.make(request: request, response: nil, data: data)
            )
        }
        return response.data
    }

    // Intent: Asks the backend to send the due reminder batch once for a selected date.
    // Network: POST /managed-reservations/send-due-reminders?date=YYYY-MM-DD.
    func sendDueReminders(
        date: String?,
        reason: ReservationAPIRequestReason = .reminderBatch
    ) async throws -> ReservationReminderBatchResponse {
        var queryItems: [URLQueryItem] = []
        if let date = date?.trimmingCharacters(in: .whitespacesAndNewlines),
           !date.isEmpty {
            queryItems.append(URLQueryItem(name: "date", value: date))
        }

        let url = try makeURL(
            path: "managed-reservations/send-due-reminders",
            queryItems: queryItems
        )
        let request = makeRequest(url: url, method: "POST")
        let data = try await perform(request, reason: reason)

        return try decode(ReservationReminderBatchResponse.self, from: data, request: request)
    }

    // Intent: Reads reminder proof/status for a date without sending anything.
    // Network: GET /managed-reservations/reminder-status?date=YYYY-MM-DD.
    func fetchReminderStatus(
        date: String,
        reason: ReservationAPIRequestReason = .reminderStatus
    ) async throws -> ReservationReminderStatusResponse {
        let url = try makeURL(
            path: "managed-reservations/reminder-status",
            queryItems: [URLQueryItem(name: "date", value: date)]
        )
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: reason)

        return try decode(ReservationReminderStatusResponse.self, from: data, request: request)
    }

    // Intent: Read-only auto-confirm dry-run candidates for a service date.
    // Network: GET /auto-confirm/candidates?date=YYYY-MM-DD.
    func fetchAutoConfirmCandidates(
        date: Date,
        reason: ReservationAPIRequestReason = .autoConfirmCandidates
    ) async throws -> AutoConfirmCandidateResponse {
        let dateKey = date.reservationDateString()
        let url = try makeURL(
            path: "auto-confirm/candidates",
            queryItems: [URLQueryItem(name: "date", value: dateKey)]
        )
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: reason)

        return try decodeAutoConfirmCandidates(from: data, request: request)
    }

    // Intent: Generates a guest self-service URL for manual Gmail/Mail workflows.
    // Network: POST /managed-reservations/{id}/guest-manage-link.
    func createGuestManageLink(
        id: Int,
        reason: ReservationAPIRequestReason = .guestManageLink
    ) async throws -> ReservationGuestManageLinkDTO {
        let url = try apiURL(path: "managed-reservations/\(id)/guest-manage-link")
        let request = makeRequest(url: url, method: "POST")
        let data = try await perform(request, reason: reason)

        return try decode(ReservationGuestManageLinkResponse.self, from: data, request: request).data
    }

    // Intent: Records staff Gmail/Mail activity for the manual MVP flow.
    // Network: POST /managed-reservations/{id}/manual-email-log.
    // Email: Does not send email and does not change reservation status.
    func logManualEmail(
        reservationID: Int,
        request logRequest: ReservationManualEmailLogRequest,
        reason: ReservationAPIRequestReason = .manualEmailLog
    ) async throws -> ReservationManualEmailLogDTO {
        let url = try apiURL(path: "managed-reservations/\(reservationID)/manual-email-log")
        let request = try makeJSONRequest(url: url, method: "POST", body: logRequest)
        let data = try await perform(request, reason: reason)

        return try decode(ReservationManualEmailLogResponse.self, from: data, request: request).data
    }

    // Intent: Developer/admin cleanup for test rows only. Staff flows must soft-hide.
    // Network: DELETE /managed-reservations/{id}?force=1.
    func hardDeleteReservation(
        id: Int,
        reason: ReservationAPIRequestReason = .hardDelete
    ) async throws -> ReservationDeleteResponse {
        let url = try makeURL(
            path: "managed-reservations/\(id)",
            queryItems: [URLQueryItem(name: "force", value: "1")]
        )
        let request = makeRequest(url: url, method: "DELETE")
        let data = try await perform(request, reason: reason)
        if data.isEmpty {
            return ReservationDeleteResponse(success: true, message: nil)
        }

        return try decode(ReservationDeleteResponse.self, from: data, request: request)
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

    // MARK: - Intelligence

    // Intent: Reads backend business intelligence aggregates (all source types).
    // Network: GET /business-intelligence/summary.
    func fetchBusinessIntelligenceSummary(
        from: String,
        to: String,
        reason: ReservationAPIRequestReason = .businessIntelligenceSummary
    ) async throws -> BusinessIntelligenceSummaryDTO {
        let url = try makeURL(
            path: "business-intelligence/summary",
            queryItems: [
                URLQueryItem(name: "from", value: from),
                URLQueryItem(name: "to", value: to)
            ]
        )
        var request = makeRequest(url: url, method: "GET")
        request.timeoutInterval = 60
        let data = try await perform(
            request,
            reason: reason,
            session: ReservationsAPIClient.longRunningIntelligenceSession
        )

        return try decodeBusinessIntelligenceSummary(from: data, request: request)
    }

    // Intent: Reads compact per-reservation guest intelligence for a service date.
    // Network: GET /guest-intelligence.
    func fetchGuestIntelligence(
        date: String,
        reason: ReservationAPIRequestReason = .guestIntelligence
    ) async throws -> GuestIntelligenceDayResponseDTO {
        let url = try makeURL(
            path: "guest-intelligence",
            queryItems: [URLQueryItem(name: "date", value: date)]
        )
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: reason)

        return try decodeGuestIntelligenceDay(from: data, request: request)
    }

    // Intent: Reads server-backed guest profile for one reservation when date summary is missing.
    // Network: GET /guest-intelligence/reservation/{id}.
    func fetchGuestIntelligenceProfile(
        reservationID: Int,
        reason: ReservationAPIRequestReason = .guestIntelligence
    ) async throws -> GuestIntelligenceProfilePackDTO {
        let url = try apiURL(path: "guest-intelligence/reservation/\(reservationID)")
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: reason)

        return try decodeGuestIntelligenceProfile(from: data, request: request)
    }

    // Intent: Reads precomputed backend guest profile aggregate list/search.
    // Network: GET /guest-profiles.
    func fetchGuestProfiles(
        query: String? = nil,
        filter: String? = nil,
        sort: String? = nil,
        page: Int = 1,
        perPage: Int = 25,
        updatedSince: String? = nil
    ) async throws -> GuestProfileListResponseDTO {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]

        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        if let filter = filter?.trimmingCharacters(in: .whitespacesAndNewlines), !filter.isEmpty {
            queryItems.append(URLQueryItem(name: "filter", value: filter))
        }
        if let sort = sort?.trimmingCharacters(in: .whitespacesAndNewlines), !sort.isEmpty {
            queryItems.append(URLQueryItem(name: "sort", value: sort))
        }
        if let updatedSince = updatedSince?.trimmingCharacters(in: .whitespacesAndNewlines), !updatedSince.isEmpty {
            queryItems.append(URLQueryItem(name: "updated_since", value: updatedSince))
        }

        let url = try makeURL(path: "guest-profiles", queryItems: queryItems)
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: .guestIntelligence)

        return try decode(GuestProfileListResponseDTO.self, from: data, request: request)
    }

    // Intent: Looks up compact guest profile candidates for staff intake/search.
    // Network: GET /guest-profiles/lookup.
    func fetchGuestProfileLookup(
        phone: String? = nil,
        email: String? = nil,
        query: String? = nil,
        limit: Int = 5
    ) async throws -> GuestProfileLookupResponseDTO {
        let normalizedPhone = phone
            .map(GuestLookupPhoneNormalizer.digits)
            .flatMap(normalizedLookupText)
        let normalizedEmail = email
            .flatMap(normalizedLookupText)
            .map { $0.lowercased() }
        let normalizedQuery = query.flatMap(normalizedLookupText)
        let clampedLimit = min(10, max(1, limit))
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(clampedLimit))
        ]

        if let normalizedPhone {
            queryItems.append(URLQueryItem(name: "phone", value: normalizedPhone))
        }
        if let normalizedEmail {
            queryItems.append(URLQueryItem(name: "email", value: normalizedEmail))
        }
        if let normalizedQuery {
            queryItems.append(URLQueryItem(name: "q", value: normalizedQuery))
        }

        guard queryItems.count > 1 else {
            throw ReservationAPIError.invalidURL
        }

        let url = try makeURL(path: "guest-profiles/lookup", queryItems: queryItems)
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: .guestProfileLookup)
        let response = try decode(GuestProfileLookupResponseDTO.self, from: data, request: request)
        if response.success == false {
            throw intelligenceEnvelopeFailure()
        }
        return response
    }

    // Intent: Reads one precomputed backend guest profile aggregate by internal key.
    // Network: GET /guest-profiles/{guestKey}.
    func fetchGuestProfile(guestKey: String) async throws -> GuestProfileDTO {
        let url = try apiURL(path: "guest-profiles/\(guestKey)")
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: .guestIntelligence)

        return try decodeGuestProfileDetail(from: data, request: request)
    }

    // Intent: Reads one precomputed backend guest profile aggregate for a reservation.
    // Network: GET /guest-profiles/by-reservation/{id}.
    func fetchGuestProfile(byReservationID reservationID: Int) async throws -> GuestProfileDTO {
        let url = try apiURL(path: "guest-profiles/by-reservation/\(reservationID)")
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: .guestIntelligence)

        return try decodeGuestProfileDetail(from: data, request: request)
    }

    // Intent: Reads intelligence pipeline health and contract checks for a date range.
    // Network: GET /intelligence/system-status.
    func fetchIntelligenceSystemStatus(
        from: String,
        to: String,
        reason: ReservationAPIRequestReason = .intelligenceSystemStatus
    ) async throws -> IntelligenceSystemStatusDTO {
        let url = try makeURL(
            path: "intelligence/system-status",
            queryItems: [
                URLQueryItem(name: "from", value: from),
                URLQueryItem(name: "to", value: to)
            ]
        )
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: reason)

        return try decodeIntelligenceSystemStatus(from: data, request: request)
    }

    // MARK: - Floor Plan

    // Intent: Reads persisted restaurant table layout metadata.
    // Network: GET /restaurant-tables.
    func fetchRestaurantTables(
        reason: ReservationAPIRequestReason = .restaurantTables
    ) async throws -> [RestaurantTableDTO] {
        let url = try apiURL(path: "restaurant-tables")
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: reason)
        let response = try decode(RestaurantTablesResponseDTO.self, from: data, request: request)
        return response.data
    }

    // Intent: Partial upsert of restaurant table layout rows by table_key.
    // Network: PUT /restaurant-tables.
    func putRestaurantTables(
        _ tables: [RestaurantTableDTO],
        reason: ReservationAPIRequestReason = .restaurantTablesPut
    ) async throws -> [RestaurantTableDTO] {
        let url = try apiURL(path: "restaurant-tables")
        let request = try makeJSONRequest(
            url: url,
            method: "PUT",
            body: RestaurantTablesPutRequestDTO(tables: tables)
        )
        let data = try await perform(request, reason: reason)
        let response = try decode(RestaurantTablesResponseDTO.self, from: data, request: request)
        return response.data
    }

    // Intent: Reads floor-plan tables, assignments, and reservations for one service date.
    // Network: GET /floor-plan?date=YYYY-MM-DD.
    func fetchFloorPlan(
        date: String,
        reason: ReservationAPIRequestReason = .floorPlan
    ) async throws -> FloorPlanResponseDTO {
        let url = try makeURL(
            path: "floor-plan",
            queryItems: [URLQueryItem(name: "date", value: date)]
        )
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, reason: reason)
        return try decode(FloorPlanResponseDTO.self, from: data, request: request)
    }

    // Intent: Replaces table assignment for one managed reservation atomically.
    // Network: PATCH /managed-reservations/{id}/tables.
    func patchReservationTables(
        reservationID: Int,
        request patchRequest: PatchReservationTablesRequest,
        reason: ReservationAPIRequestReason = .reservationTablesPatch
    ) async throws -> FloorPlanPatchResponseDTO {
        let url = try apiURL(path: "managed-reservations/\(reservationID)/tables")
        let request = try makeJSONRequest(url: url, method: "PATCH", body: patchRequest)
        let (data, httpResponse) = try await performReturningHTTPResponse(request, reason: reason)

        if httpResponse.statusCode == 409 {
            throw decodeTableAssignmentConflict(from: data, request: request, httpResponse: httpResponse)
        }

        try validate(
            response: httpResponse,
            data: data,
            request: request,
            reason: reason
        )
        let response = try decode(FloorPlanPatchResponseDTO.self, from: data, request: request)
        traceOptionalMutationActivity(reservationID: reservationID, activity: response.activity)
        return response
    }

    // MARK: - Activity History

    // Intent: Staff reads backend-owned mutation history for one reservation.
    // Network: GET /managed-reservations/{id}/activity.
    func fetchReservationActivity(
        reservationID: Int,
        page: Int = 1,
        perPage: Int = 25,
        reason: ReservationAPIRequestReason = .reservationActivity
    ) async throws -> ReservationActivityResponseDTO {
        let url = try makeURL(
            path: "managed-reservations/\(reservationID)/activity",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
        )
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, retryCount: 0, reason: reason)
        return try decode(ReservationActivityResponseDTO.self, from: data, request: request)
    }

    // Intent: Staff reads service-day activity feed.
    // Network: GET /activity?date=YYYY-MM-DD.
    func fetchActivityFeed(
        date: Date,
        page: Int = 1,
        perPage: Int = 50,
        reason: ReservationAPIRequestReason = .activityFeed
    ) async throws -> ReservationActivityFeedResponseDTO {
        let dateKey = date.reservationDateString()
        let url = try makeURL(
            path: "activity",
            queryItems: [
                URLQueryItem(name: "date", value: dateKey),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
        )
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, retryCount: 0, reason: reason)
        return try decode(ReservationActivityFeedResponseDTO.self, from: data, request: request)
    }

    // Intent: Staff reads activity feed for a date range.
    // Network: GET /activity?from=YYYY-MM-DD&to=YYYY-MM-DD.
    func fetchActivityFeed(
        from: Date,
        to: Date,
        page: Int = 1,
        perPage: Int = 50,
        reason: ReservationAPIRequestReason = .activityFeed
    ) async throws -> ReservationActivityFeedResponseDTO {
        let url = try makeURL(
            path: "activity",
            queryItems: [
                URLQueryItem(name: "from", value: from.reservationDateString()),
                URLQueryItem(name: "to", value: to.reservationDateString()),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
        )
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, retryCount: 0, reason: reason)
        return try decode(ReservationActivityFeedResponseDTO.self, from: data, request: request)
    }

    // MARK: - Reservation Attachments

    // Intent: Reads private staff-only image attachment metadata for one reservation.
    // Network: GET /managed-reservations/{id}/attachments.
    func listReservationAttachments(reservationID: Int) async throws -> ReservationAttachmentListResponseDTO {
        let url = try apiURL(path: "managed-reservations/\(reservationID)/attachments")
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, retryCount: 0, reason: .reservationAttachments)
        return try decode(ReservationAttachmentListResponseDTO.self, from: data, request: request)
    }

    // Intent: Uploads one compressed JPEG to private backend attachment storage.
    // Network: POST /managed-reservations/{id}/attachments multipart/form-data.
    func uploadReservationAttachment(
        reservationID: Int,
        jpegData: Data,
        originalFilename: String,
        label: AttachmentLabel,
        caption: String?
    ) async throws -> ReservationAttachmentDTO {
        let url = try apiURL(path: "managed-reservations/\(reservationID)/attachments")
        let request = makeMultipartAttachmentUploadRequest(
            url: url,
            reservationID: reservationID,
            jpegData: jpegData,
            originalFilename: originalFilename,
            label: label,
            caption: caption
        )
        let data = try await perform(request, reason: .reservationAttachmentUpload)
        return try decodeAttachmentMutationResponse(from: data, request: request)
    }

    // Intent: Updates private backend attachment metadata only, never image bytes.
    // Network: PATCH /managed-reservations/{id}/attachments/{attachment_id}.
    func updateReservationAttachment(
        reservationID: Int,
        attachmentID: Int,
        label: AttachmentLabel,
        caption: String?
    ) async throws -> ReservationAttachmentDTO {
        let url = try apiURL(path: "managed-reservations/\(reservationID)/attachments/\(attachmentID)")
        let request = try makeJSONRequest(
            url: url,
            method: "PATCH",
            body: ReservationAttachmentUpdateRequest(
                label: label.backendValue,
                caption: caption
            )
        )
        let data = try await perform(request, reason: .reservationAttachmentPatch)
        return try decodeAttachmentMutationResponse(from: data, request: request)
    }

    // Intent: Soft-deletes one private backend attachment.
    // Network: DELETE /managed-reservations/{id}/attachments/{attachment_id}.
    func deleteReservationAttachment(
        reservationID: Int,
        attachmentID: Int
    ) async throws {
        let url = try apiURL(path: "managed-reservations/\(reservationID)/attachments/\(attachmentID)")
        let request = makeRequest(url: url, method: "DELETE")
        _ = try await perform(request, reason: .reservationAttachmentDelete)
    }

    // Intent: Downloads image bytes through the authenticated REST content route.
    // Network: GET /managed-reservations/{id}/attachments/{attachment_id}/content.
    func downloadReservationAttachmentContent(
        reservationID: Int,
        attachmentID: Int
    ) async throws -> Data {
        let url = try apiURL(path: "managed-reservations/\(reservationID)/attachments/\(attachmentID)/content")
        var request = makeRequest(url: url, method: "GET")
        request.setValue("image/jpeg,image/*,*/*", forHTTPHeaderField: "Accept")
        return try await perform(request, retryCount: 0, reason: .reservationAttachmentContent)
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

    private func normalizedLookupText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

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
        if #available(iOS 14.5, *) {
            // Prefer HTTP/2 over QUIC; GoDaddy often drops HTTP/3 mid-request (-1005).
            request.assumesHTTP3Capable = false
        }
        request.setValue("close", forHTTPHeaderField: "Connection")
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

    private func makeMultipartAttachmentUploadRequest(
        url: URL,
        reservationID: Int,
        jpegData: Data,
        originalFilename: String,
        label: AttachmentLabel,
        caption: String?
    ) -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = makeMultipartAttachmentBody(
            boundary: boundary,
            jpegData: jpegData,
            filename: sanitizedJPEGFilename(originalFilename, reservationID: reservationID),
            label: label.backendValue,
            caption: caption
        )
        return request
    }

    private func makeMultipartAttachmentBody(
        boundary: String,
        jpegData: Data,
        filename: String,
        label: String,
        caption: String?
    ) -> Data {
        var body = Data()
        body.appendMultipartField(name: "label", value: label, boundary: boundary)
        if let caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
            body.appendMultipartField(name: "caption", value: caption, boundary: boundary)
        }
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }

    private func sanitizedJPEGFilename(_ originalFilename: String, reservationID: Int) -> String {
        let fallback = "reservation-\(reservationID)-attachment.jpg"
        let candidate = originalFilename
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .last
            .map(String.init) ?? fallback
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitizedScalars = candidate.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        var sanitized = String(sanitizedScalars).trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        if sanitized.isEmpty {
            sanitized = fallback
        }
        if !sanitized.lowercased().hasSuffix(".jpg"),
           !sanitized.lowercased().hasSuffix(".jpeg") {
            sanitized += ".jpg"
        }
        return sanitized
    }

    private func decodeAttachmentMutationResponse(
        from data: Data,
        request: URLRequest
    ) throws -> ReservationAttachmentDTO {
        if let envelope = try? decoder.decode(ReservationAttachmentResponseDTO.self, from: data),
           let attachment = envelope.resolvedAttachment {
            return attachment
        }
        return try decode(ReservationAttachmentDTO.self, from: data, request: request)
    }

    private func decodeTableAssignmentConflict(
        from data: Data,
        request: URLRequest,
        httpResponse: HTTPURLResponse
    ) -> FloorPlanError {
        _ = ReservationAPIDiagnostics.make(
            request: request,
            response: httpResponse,
            data: data,
            includeResponseBody: true
        )

        if let conflictResponse = try? decoder.decode(
            TableAssignmentConflictResponseDTO.self,
            from: data
        ), !conflictResponse.conflicts.isEmpty {
            return .assignmentConflict(conflictResponse.conflicts)
        }

        if let message = (try? decoder.decode(TableAssignmentConflictResponseDTO.self, from: data))?.message?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return .serverMessage(message)
        }

        if let wordpress = try? decoder.decode(WordPressAPIError.self, from: data) {
            let message = wordpress.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                return .serverMessage(message)
            }
        }

        return .serverMessage(
            "This table assignment conflicts with another reservation. Refresh the floor plan and try again."
        )
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

    private func decodeBusinessIntelligenceSummary(
        from data: Data,
        request: URLRequest
    ) throws -> BusinessIntelligenceSummaryDTO {
        do {
            if let envelope = try? decoder.decode(BusinessIntelligenceSummaryResponse.self, from: data) {
                if envelope.success == false {
                    throw intelligenceEnvelopeFailure()
                }
                if let payload = envelope.data {
                    return payload
                }
            }

            return try decoder.decode(BusinessIntelligenceSummaryDTO.self, from: data)
        } catch let error as ReservationAPIError {
            throw error
        } catch {
            throw intelligenceDecodingFailure(error, data: data, request: request)
        }
    }

    private func decodeGuestIntelligenceProfile(
        from data: Data,
        request: URLRequest
    ) throws -> GuestIntelligenceProfilePackDTO {
        do {
            if let envelope = try? decoder.decode(GuestIntelligenceProfileAPIResponse.self, from: data) {
                if envelope.success == false {
                    throw intelligenceEnvelopeFailure()
                }
                if let pack = envelope.data {
                    return pack
                }
            }

            if let legacy = try? decoder.decode(GuestIntelligenceProfileLegacyAPIResponse.self, from: data) {
                if legacy.success == false {
                    throw intelligenceEnvelopeFailure()
                }
                if let summary = legacy.data {
                    return GuestIntelligenceProfilePackDTO.fromLegacySummary(summary)
                }
            }

            let summary = try decoder.decode(GuestIntelligenceSummaryDTO.self, from: data)
            return GuestIntelligenceProfilePackDTO.fromLegacySummary(summary)
        } catch let error as ReservationAPIError {
            throw error
        } catch {
            throw intelligenceDecodingFailure(error, data: data, request: request)
        }
    }

    private func decodeGuestIntelligenceDay(
        from data: Data,
        request: URLRequest
    ) throws -> GuestIntelligenceDayResponseDTO {
        do {
            if let envelope = try? decoder.decode(GuestIntelligenceDayAPIResponse.self, from: data) {
                if envelope.success == false {
                    throw intelligenceEnvelopeFailure()
                }
                if let payload = envelope.data {
                    return payload
                }
            }

            return try decoder.decode(GuestIntelligenceDayResponseDTO.self, from: data)
        } catch let error as ReservationAPIError {
            throw error
        } catch {
            throw intelligenceDecodingFailure(error, data: data, request: request)
        }
    }

    private func decodeGuestProfileDetail(
        from data: Data,
        request: URLRequest
    ) throws -> GuestProfileDTO {
        do {
            let envelope = try decoder.decode(GuestProfileDetailResponseDTO.self, from: data)
            if envelope.success == false {
                throw intelligenceEnvelopeFailure()
            }
            if let profile = envelope.data {
                return profile
            }

            let error = DecodingError.valueNotFound(
                GuestProfileDTO.self,
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Guest profile detail response did not include data."
                )
            )
            throw intelligenceDecodingFailure(error, data: data, request: request)
        } catch let error as ReservationAPIError {
            throw error
        } catch {
            throw intelligenceDecodingFailure(error, data: data, request: request)
        }
    }

    private func decodeIntelligenceSystemStatus(
        from data: Data,
        request: URLRequest
    ) throws -> IntelligenceSystemStatusDTO {
        do {
            if let envelope = try? decoder.decode(IntelligenceSystemStatusResponse.self, from: data) {
                if envelope.success == false {
                    throw intelligenceEnvelopeFailure()
                }
                if let payload = envelope.data {
                    return payload
                }
            }

            return try decoder.decode(IntelligenceSystemStatusDTO.self, from: data)
        } catch let error as ReservationAPIError {
            throw error
        } catch {
            throw intelligenceDecodingFailure(error, data: data, request: request)
        }
    }

    private func intelligenceEnvelopeFailure() -> ReservationAPIError {
        let error = NSError(
            domain: "TryzubIntelligenceAPI",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Intelligence response reported success=false."]
        )
        return .decodingFailure(error, diagnostics: nil)
    }

    private func intelligenceDecodingFailure(
        _ error: Error,
        data: Data,
        request: URLRequest
    ) -> ReservationAPIError {
        let diagnostics = ReservationAPIDiagnostics.make(
            request: request,
            response: nil,
            data: data,
            decodingError: error,
            includeResponseBody: false
        )
        return .decodingFailure(error, diagnostics: diagnostics)
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

    private func decodeAutoConfirmCandidates(
        from data: Data,
        request: URLRequest
    ) throws -> AutoConfirmCandidateResponse {
        do {
            return try decoder.decode(AutoConfirmCandidateResponse.self, from: data)
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

    private func performReturningHTTPResponse(
        _ request: URLRequest,
        retryCount: Int = 0,
        reason: ReservationAPIRequestReason = .unspecified,
        requiresAuth: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await execute(
            request,
            retryCount: retryCount,
            reason: reason,
            requiresAuth: requiresAuth
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReservationAPIError.invalidResponse(
                diagnostics: ReservationAPIDiagnostics.make(
                    request: request,
                    response: nil,
                    data: data,
                    includeResponseBody: !reason.suppressesResponseBodyLogging
                )
            )
        }
        return (data, httpResponse)
    }

    // Intent: Performs one API request with bounded retry for transient network errors.
    private func perform(
        _ request: URLRequest,
        retryCount: Int = 0,
        reason: ReservationAPIRequestReason = .unspecified,
        requiresAuth: Bool = true,
        session: URLSession? = nil
    ) async throws -> Data {
        let (data, response) = try await execute(
            request,
            retryCount: retryCount,
            reason: reason,
            requiresAuth: requiresAuth,
            session: session
        )
        try validate(response: response, data: data, request: request, reason: reason)
        return data
    }

    private func execute(
        _ request: URLRequest,
        retryCount: Int = 0,
        reason: ReservationAPIRequestReason = .unspecified,
        requiresAuth: Bool = true,
        session: URLSession? = nil
    ) async throws -> (Data, URLResponse) {
        if requiresAuth {
            try ensureProtectedCredentials()
            AppAuthTrace.request(
                route: request.url?.path ?? "<unknown>",
                role: authRole,
                username: username,
                authHeaderPresent: request.value(forHTTPHeaderField: "Authorization") != nil
            )
        }

        var attempt = 0
        var lastNetworkError: URLError?
        let startedAt = ReservationAPILogger.start(request: request, reason: reason)
        let effectiveRetryCount = request.httpMethod?.uppercased() == "GET"
            ? min(max(retryCount, 0), 1)
            : 0

        while attempt <= effectiveRetryCount {
            do {
                let (data, response) = try await requestSerializer.data(
                    for: request,
                    session: session ?? self.session
                )
                let includeResponseBody = !reason.suppressesResponseBodyLogging
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let diagnostics = ReservationAPIDiagnostics.make(
                    request: request,
                    response: response as? HTTPURLResponse,
                    data: data,
                    includeResponseBody: includeResponseBody
                )

                if (200...299).contains(statusCode) {
                    ReservationAPILogger.end(
                        request: request,
                        reason: reason,
                        statusCode: statusCode,
                        startedAt: startedAt,
                        responseBodySnippet: diagnostics.responseBodySnippet
                    )
                } else {
                    ReservationAPILogger.fail(
                        request: request,
                        reason: reason,
                        error: ReservationAPIError.serverError(
                            statusCode: statusCode,
                            diagnostics: diagnostics
                        ),
                        startedAt: startedAt
                    )
                }

                return (data, response)
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

    private func validate(
        response: URLResponse,
        data: Data,
        request: URLRequest,
        reason: ReservationAPIRequestReason
    ) throws {
        let includeResponseBody = !reason.suppressesResponseBodyLogging

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReservationAPIError.invalidResponse(
                diagnostics: ReservationAPIDiagnostics.make(
                    request: request,
                    response: nil,
                    data: data,
                    includeResponseBody: includeResponseBody
                )
            )
        }

        let diagnostics = ReservationAPIDiagnostics.make(
            request: request,
            response: httpResponse,
            data: data,
            includeResponseBody: includeResponseBody
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

    private func traceOptionalMutationActivity(
        reservationID: Int,
        activity: MutationActivityResultDTO?
    ) {
        guard let activity else { return }
        ReservationActivityMutationTrace.emit(
            reservationID: reservationID,
            mutationActivity: activity
        )
    }
}

// MARK: - WordPress Error Payload

private struct WordPressAPIError: Decodable {
    let code: String
    let message: String
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }
}

// MARK: - Request Serialization

// One in-flight request at a time to avoid QUIC connection storms on cold start.
    private actor ReservationAPIRequestSerializer {
        private var isRunning = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func data(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
            try Task.checkCancellation()
            await acquire()
            defer { release() }
            try Task.checkCancellation()
            try? await Task.sleep(for: .milliseconds(200))
            try Task.checkCancellation()
            return try await session.data(for: request)
        }

    private func acquire() async {
        if !isRunning {
            isRunning = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isRunning = false
        } else {
            waiters.removeFirst().resume()
        }
    }
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

extension ReservationsAPIClient: @unchecked Sendable {}
