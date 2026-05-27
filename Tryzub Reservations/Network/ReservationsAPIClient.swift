//
//  APIClient.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import Foundation

// MARK: - Request Reasons

enum ReservationAPIRequestReason: String {
    case unspecified
    case startupToday = "startup_today"
    case manualToday = "manual_today"
    case autoToday = "auto_today"
    case autoSkipCooldown = "auto_skip_cooldown"
    case failureCount = "failure_count"
    case importFailuresFull = "import_failures_full"
    case scheduleWindow = "schedule_window"
    case reviewQueues = "review_queues"
    case mutationPatch = "mutation_patch"
    case mutationConfirm = "mutation_confirm"
    case mutationCreate = "mutation_create"
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

    static func start(request: URLRequest, reason: ReservationAPIRequestReason) -> Date {
        let startedAt = Date()
        append(
            outcome: .started,
            request: request,
            reason: reason,
            duration: nil
        )
        guard isEnabled else { return startedAt }

        print("[API] START Reason ===>\(reason.rawValue) /br Method ===>\(request.httpMethod ?? "GET") \(sanitizedPathAndQuery(for: request.url))")
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

        print("[API] END reason=\(reason.rawValue) status=\(statusCode) duration=\(duration(since: startedAt)) \(sanitizedPathAndQuery(for: request.url))")
    }

    static func fail(
        request: URLRequest,
        reason: ReservationAPIRequestReason,
        error: Error,
        startedAt: Date
    ) {
        append(
            outcome: .failed,
            request: request,
            reason: reason,
            error: errorLogValue(error),
            duration: duration(since: startedAt)
        )
        guard isEnabled else { return }

        print("[API] FAIL reason=\(reason.rawValue) error=\(errorLogValue(error)) duration=\(duration(since: startedAt)) \(sanitizedPathAndQuery(for: request.url))")
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

        print("[API] CANCELLED reason=\(reason.rawValue) duration=\(duration(since: startedAt)) \(sanitizedPathAndQuery(for: request.url))")
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

        print("[API] SKIP reason=\(reason.rawValue) \(message)")
    }

    private static func append(
        outcome: APIRequestLogOutcome,
        request: URLRequest,
        reason: ReservationAPIRequestReason,
        statusCode: Int? = nil,
        error: String? = nil,
        duration: String? = nil
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
                    duration: duration
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

    func fetchReservations(
        page: Int,
        perPage: Int,
        date: String?,
        from: String?,
        to: String?,
        status: ReservationStatus?,
        search: String?,
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
        reason: ReservationAPIRequestReason
    ) async throws -> [ReservationDTO]

    func fetchReservation(id: Int, retryCount: Int, reason: ReservationAPIRequestReason) async throws -> ReservationDTO
    func updateReservation(id: Int, request: ReservationUpdateRequest, reason: ReservationAPIRequestReason) async throws -> ReservationDTO
    func createReservation(_ createRequest: ReservationCreateRequest, reason: ReservationAPIRequestReason) async throws -> ReservationDTO
    func confirmReservation(id: Int, reason: ReservationAPIRequestReason) async throws -> ReservationConfirmResponse
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
            retryCount: 0,
            reason: reason
        )
    }

    func fetchReservation(id: Int) async throws -> ReservationDTO {
        try await fetchReservation(id: id, retryCount: 0, reason: .unspecified)
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
    
//    private static let defaultSession: URLSession = {
//        let configuration = URLSessionConfiguration.default
//        configuration.waitsForConnectivity = false
//        configuration.timeoutIntervalForRequest = 8
//        configuration.timeoutIntervalForResource = 12
//        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
//        configuration.httpMaximumConnectionsPerHost = 2
//        return URLSession(configuration: configuration)
//    }()

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

    // MARK: - Fetch Reservation Lists

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
        retryCount: Int = 0,
        reason: ReservationAPIRequestReason = .unspecified
    ) async throws -> ReservationsResponse {
        
        var components = URLComponents(url: managedReservationsURL(), resolvingAgainstBaseURL: false)
        
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
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            throw ReservationAPIError.invalidURL
        }
        
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, retryCount: retryCount, reason: reason)
        
        do {
            return try decoder.decode(ReservationsResponse.self, from: data)
        }
        catch {
            throw ReservationAPIError.decodingFailure(error)
        }
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
                reason: reason
            )

            allReservations.append(contentsOf: response.data)
            totalPages = max(response.totalPages, 1)
            currentPage += 1
        } while currentPage <= totalPages

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
        let url = managedReservationsURL().appendingPathComponent(String(id))
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, retryCount: retryCount, reason: reason)

        do {
            return try decoder.decode(ReservationFetchResponse.self, from: data).data
        } catch {
            throw ReservationAPIError.decodingFailure(error)
        }
    }

    // MARK: - Reservation Mutations

    // Intent: Server-first reservation edit, including confirm-without-email via status=confirmed.
    // Network: PATCH /managed-reservations/{id}.
    func updateReservation(
        id: Int,
        request updateRequest: ReservationUpdateRequest,
        reason: ReservationAPIRequestReason = .mutationPatch
    ) async throws -> ReservationDTO {
        let url = managedReservationsURL().appendingPathComponent(String(id))

        let request = try makeJSONRequest(url: url, method: "PATCH", body: updateRequest)
        let data = try await perform(request, reason: reason)

        do {
            return try decoder.decode(ReservationUpdateResponse.self, from: data).data
        } catch {
            throw ReservationAPIError.decodingFailure(error)
        }
    }

    // Intent: Staff creates a manual/call-in reservation.
    // Network: POST /managed-reservations.
    func createReservation(
        _ createRequest: ReservationCreateRequest,
        reason: ReservationAPIRequestReason = .mutationCreate
    ) async throws -> ReservationDTO {
        let request = try makeJSONRequest(
            url: managedReservationsURL(),
            method: "POST",
            body: createRequest
        )
        let data = try await perform(request, reason: reason)

        do {
            return try decoder.decode(ReservationCreateResponse.self, from: data).data
        } catch {
            throw ReservationAPIError.decodingFailure(error)
        }
    }

    // MARK: - Confirm With Email

    // Intent: Confirms reservation and asks backend to send/record confirmation email.
    // Network: POST /managed-reservations/{id}/confirm.
    // Rename note: This method name should mention email in a later cleanup.
    func confirmReservation(
        id: Int,
        reason: ReservationAPIRequestReason = .mutationConfirm
    ) async throws -> ReservationConfirmResponse {
        let url = managedReservationsURL()
            .appendingPathComponent(String(id))
            .appendingPathComponent("confirm")
        let request = makeRequest(url: url, method: "POST")
        let data = try await perform(request, reason: reason)

        do {
            return try decoder.decode(ReservationConfirmResponse.self, from: data)
        } catch {
            throw ReservationAPIError.decodingFailure(error)
        }
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

        do {
            return try decoder.decode(ImportFailuresResponse.self, from: data)
        } catch {
            throw ReservationAPIError.decodingFailure(error)
        }
    }

    // MARK: - Request Building

    private func managedReservationsURL() -> URL {
        baseURL.appendingPathComponent("managed-reservations")
    }

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw ReservationAPIError.invalidURL
        }

        return url
    }

    // Authorization header is attached here and never passed to sanitized logging output.
    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(makeAuthHeader(), forHTTPHeaderField: "Authorization")
        return request
    }

    private func makeJSONRequest<T: Encodable>(url: URL, method: String, body: T) throws -> URLRequest {
        var request = makeRequest(url: url, method: method)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return request
    }
    
    private func makeAuthHeader() -> String {
        let loginString = "\(username):\(applicationPassword)"
        let loginData = loginString.data(using: .utf8)
        let base64LoginString = loginData?.base64EncodedString() ?? ""
        
        return "Basic \(base64LoginString)"
    }

    // MARK: - Network Execution

    // Intent: Performs one API request with bounded retry for transient network errors.
    private func perform(
        _ request: URLRequest,
        retryCount: Int = 0,
        reason: ReservationAPIRequestReason = .unspecified
    ) async throws -> Data {
        var attempt = 0
        var lastNetworkError: URLError?
        let startedAt = ReservationAPILogger.start(request: request, reason: reason)

        while attempt <= retryCount {
            do {
                let (data, response) = try await session.data(for: request)
                try validate(response: response, data: data)
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

                guard error.isTransientNetworkError, attempt < retryCount else {
                    let apiError = ReservationAPIError.networkFailure(error)
                    ReservationAPILogger.fail(request: request, reason: reason, error: apiError, startedAt: startedAt)
                    throw apiError
                }

                attempt += 1

                do {
                    try await Task.sleep(for: .milliseconds(450 * attempt))
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

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReservationAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw ReservationAPIError.unauthorized
        default:
            if let apiError = try? JSONDecoder().decode(WordPressAPIError.self, from: data) {
                throw ReservationAPIError.wordpressError(
                    code: apiError.code,
                    message: apiError.message,
                    statusCode: httpResponse.statusCode
                )
            }
            throw ReservationAPIError.serverError(statusCode: httpResponse.statusCode)
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
    var isTransientNetworkError: Bool {
        switch code {
        case .networkConnectionLost,
             .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}
