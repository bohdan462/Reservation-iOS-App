//
//  APIClient.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import Foundation

protocol ReservationsAPIClientProtocol: AnyObject {
    func fetchReservations(
        page: Int,
        perPage: Int,
        date: String?,
        from: String?,
        to: String?,
        status: ReservationStatus?,
        search: String?
    ) async throws -> ReservationsResponse

    func fetchAllReservations(
        perPage: Int,
        date: String?,
        from: String?,
        to: String?,
        status: ReservationStatus?,
        search: String?
    ) async throws -> [ReservationDTO]

    func fetchReservation(id: Int) async throws -> ReservationDTO
    func updateReservation(id: Int, request: ReservationUpdateRequest) async throws -> ReservationDTO
    func createReservation(_ createRequest: ReservationCreateRequest) async throws -> ReservationDTO
    func confirmReservation(id: Int) async throws -> ReservationConfirmResponse
    func fetchImportFailures(page: Int, perPage: Int) async throws -> ImportFailuresResponse
}

//Build URL
//
//Add auth header
//
//Call URLSession
//
//Validate status code
//
//Decode JSON
//
//Return ReservationsResponse

final class ReservationsAPIClient: ReservationsAPIClientProtocol {
    private let baseURL: URL
    private let username: String
    private let applicationPassword: String
    private let session: URLSession

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
    
    init(baseURL: URL,
         username: String,
         applicationPassword: String,
         session: URLSession = ReservationsAPIClient.defaultSession) {
        
        self.baseURL = baseURL
        self.username = username
        self.applicationPassword = applicationPassword
        self.session = session
    }
    
    func fetchReservations(
        page: Int = 1,
        perPage: Int = 20,
        date: String? = nil,
        from: String? = nil,
        to: String? = nil,
        status: ReservationStatus? = nil,
        search: String? = nil
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
        let data = try await perform(request, retryCount: 1)
        
        do {
            return try decoder.decode(ReservationsResponse.self, from: data)
        }
        catch {
            throw ReservationAPIError.decodingFailure(error)
        }
    }

    func fetchAllReservations(
        perPage: Int = 100,
        date: String? = nil,
        from: String? = nil,
        to: String? = nil,
        status: ReservationStatus? = nil,
        search: String? = nil
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
                search: search
            )

            allReservations.append(contentsOf: response.data)
            totalPages = max(response.totalPages, 1)
            currentPage += 1
        } while currentPage <= totalPages

        return allReservations
    }

    func fetchReservation(id: Int) async throws -> ReservationDTO {
        let url = managedReservationsURL().appendingPathComponent(String(id))
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, retryCount: 1)

        do {
            return try decoder.decode(ReservationFetchResponse.self, from: data).data
        } catch {
            throw ReservationAPIError.decodingFailure(error)
        }
    }

    func updateReservation(id: Int, request updateRequest: ReservationUpdateRequest) async throws -> ReservationDTO {
        let url = managedReservationsURL().appendingPathComponent(String(id))

        let request = try makeJSONRequest(url: url, method: "PATCH", body: updateRequest)
        let data = try await perform(request)

        do {
            return try decoder.decode(ReservationUpdateResponse.self, from: data).data
        } catch {
            throw ReservationAPIError.decodingFailure(error)
        }
    }

    func createReservation(_ createRequest: ReservationCreateRequest) async throws -> ReservationDTO {
        let request = try makeJSONRequest(
            url: managedReservationsURL(),
            method: "POST",
            body: createRequest
        )
        let data = try await perform(request)

        do {
            return try decoder.decode(ReservationCreateResponse.self, from: data).data
        } catch {
            throw ReservationAPIError.decodingFailure(error)
        }
    }

    func confirmReservation(id: Int) async throws -> ReservationConfirmResponse {
        let url = managedReservationsURL()
            .appendingPathComponent(String(id))
            .appendingPathComponent("confirm")
        let request = makeRequest(url: url, method: "POST")
        let data = try await perform(request)

        do {
            return try decoder.decode(ReservationConfirmResponse.self, from: data)
        } catch {
            throw ReservationAPIError.decodingFailure(error)
        }
    }

    func fetchImportFailures(page: Int = 1, perPage: Int = 50) async throws -> ImportFailuresResponse {
        let url = try makeURL(
            path: "managed-reservations/import-failures",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
        )
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request, retryCount: 1)

        do {
            return try decoder.decode(ImportFailuresResponse.self, from: data)
        } catch {
            throw ReservationAPIError.decodingFailure(error)
        }
    }

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

    private func perform(_ request: URLRequest, retryCount: Int = 0) async throws -> Data {
        var attempt = 0
        var lastNetworkError: URLError?

        while attempt <= retryCount {
            do {
                let (data, response) = try await session.data(for: request)
                try validate(response: response, data: data)
                return data
            } catch let error as URLError {
                lastNetworkError = error

                guard error.isTransientNetworkError, attempt < retryCount else {
                    throw ReservationAPIError.networkFailure(error)
                }

                attempt += 1

                do {
                    try await Task.sleep(for: .milliseconds(450 * attempt))
                } catch {
                    throw ReservationAPIError.networkFailure(lastNetworkError ?? URLError(.cancelled))
                }
            }
        }

        throw ReservationAPIError.networkFailure(lastNetworkError ?? URLError(.unknown))
    }

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

private struct WordPressAPIError: Decodable {
    let code: String
    let message: String
}

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
