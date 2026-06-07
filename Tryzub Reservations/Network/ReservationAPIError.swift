//
//  ReservationAPIError.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import Foundation

struct ReservationAPIDiagnostics: Equatable {
    let method: String
    let pathAndQuery: String
    let statusCode: Int?
    let responseBodySnippet: String?
    let decodingError: String?

    init(
        method: String,
        pathAndQuery: String,
        statusCode: Int? = nil,
        responseBodySnippet: String? = nil,
        decodingError: String? = nil
    ) {
        self.method = method
        self.pathAndQuery = pathAndQuery
        self.statusCode = statusCode
        self.responseBodySnippet = responseBodySnippet
        self.decodingError = decodingError
    }

    static func make(
        request: URLRequest,
        response: HTTPURLResponse?,
        data: Data?,
        decodingError: Error? = nil
    ) -> ReservationAPIDiagnostics {
        ReservationAPIDiagnostics(
            method: request.httpMethod ?? "GET",
            pathAndQuery: sanitizedPathAndQuery(for: request.url),
            statusCode: response?.statusCode,
            responseBodySnippet: sanitizedBodySnippet(from: data),
            decodingError: decodingError.map { String($0.localizedDescription) }
        )
    }

    func withDecodingError(_ error: Error) -> ReservationAPIDiagnostics {
        ReservationAPIDiagnostics(
            method: method,
            pathAndQuery: pathAndQuery,
            statusCode: statusCode,
            responseBodySnippet: responseBodySnippet,
            decodingError: error.localizedDescription
        )
    }

    var developerSummary: String {
        var parts = ["\(method) \(pathAndQuery)"]
        if let statusCode {
            parts.append("HTTP \(statusCode)")
        }
        if let responseBodySnippet, !responseBodySnippet.isEmpty {
            parts.append("body=\(responseBodySnippet)")
        }
        if let decodingError, !decodingError.isEmpty {
            parts.append("decode=\(decodingError)")
        }
        return parts.joined(separator: " | ")
    }

    private static func sanitizedPathAndQuery(for url: URL?) -> String {
        guard let url else { return "<unknown>" }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.path
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
            if item.name.lowercased().contains("token") {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            return item
        }

        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return "\(components.path)\(query)"
    }

    private static func sanitizedBodySnippet(from data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }

        let raw = String(data: data.prefix(900), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return "<non-text body>" }

        // Developer-only diagnostics. Emails and phone-like digit runs are redacted
        // so guest PII does not land in the request log.
        var redacted = raw.replacingOccurrences(
            of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            with: "[email]",
            options: [.regularExpression, .caseInsensitive]
        )

        redacted = redacted.replacingOccurrences(
            of: #"\+?\d[\d\s().-]{6,}\d"#,
            with: "[phone]",
            options: [.regularExpression]
        )

        redacted = redacted.replacingOccurrences(
            of: #""(guest_name|guestName|guest_notes|guestNotes|staff_notes|staffNotes|name)"\s*:\s*"[^"]*""#,
            with: #""$1":"[redacted]""#,
            options: [.regularExpression]
        )

        redacted = redacted.replacingOccurrences(
            of: #""(token|raw_token|manage_token|manageToken)"\s*:\s*"[^"]*""#,
            with: #""$1":"[redacted]""#,
            options: [.regularExpression]
        )

        redacted = redacted.replacingOccurrences(
            of: #""(body_snapshot|bodySnapshot)"\s*:\s*"[^"]*""#,
            with: #""$1":"[redacted]""#,
            options: [.regularExpression]
        )

        redacted = redacted.replacingOccurrences(
            of: #"token=[^"'\s&<]+"#,
            with: "token=[redacted]",
            options: [.regularExpression]
        )

        redacted = redacted.replacingOccurrences(
            of: #""(url)"\s*:\s*"[^"]*manage-reservation[^"]*""#,
            with: #""$1":"[redacted]""#,
            options: [.regularExpression]
        )

        if redacted.count <= 600 {
            return redacted
        }

        return String(redacted.prefix(600)) + "…"
    }
}

enum ReservationAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse(diagnostics: ReservationAPIDiagnostics?)
    case unauthorized(diagnostics: ReservationAPIDiagnostics?)
    case cancelled
    case networkFailure(URLError)
    case serverError(statusCode: Int, diagnostics: ReservationAPIDiagnostics?)
    case wordpressError(code: String, message: String, statusCode: Int, diagnostics: ReservationAPIDiagnostics?)
    case decodingFailure(Error, diagnostics: ReservationAPIDiagnostics?)
    case missingCredentials

    var diagnostics: ReservationAPIDiagnostics? {
        switch self {
        case .invalidResponse(let diagnostics),
             .unauthorized(let diagnostics),
             .serverError(_, let diagnostics),
             .wordpressError(_, _, _, let diagnostics),
             .decodingFailure(_, let diagnostics):
            return diagnostics
        case .invalidURL, .cancelled, .networkFailure, .missingCredentials:
            return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The reservation API URL is invalid."
        case .invalidResponse:
            return "The reservation API returned an invalid response."
        case .unauthorized:
            return "WordPress credentials were rejected. Check the username and application password."
        case .cancelled:
            return "The reservation API request was cancelled."
        case .missingCredentials:
            return "WordPress credentials are missing. Add an application password before calling protected endpoints."
        case .networkFailure(let error):
            switch error.code {
            case .notConnectedToInternet:
                return "No internet connection. Check Wi-Fi or cellular data and try again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Could not reach tryzubchicago.com. Check the API URL and network connection."
            case .timedOut:
                return "The reservation API timed out. Pull to refresh again."
            default:
                return "Network error: \(error.localizedDescription)"
            }
        case .serverError(let statusCode, let diagnostics):
            if statusCode == 404 {
                if let path = diagnostics?.pathAndQuery {
                    return "The reservation API route was not found (\(path))."
                }
                return "The reservation API route was not found (HTTP 404)."
            }
            return "The reservation API returned HTTP \(statusCode)."
        case .wordpressError(_, let message, _, _):
            return message
        case .decodingFailure:
            return "Could not read the reservation response. The server returned an unexpected shape."
        }
    }

    var developerDetail: String? {
        diagnostics?.developerSummary
    }

    var logValue: String {
        switch self {
        case .invalidURL:
            return "invalid_url"
        case .invalidResponse:
            return "invalid_response"
        case .unauthorized:
            return "unauthorized"
        case .cancelled:
            return "cancelled"
        case .missingCredentials:
            return "missing_credentials"
        case .networkFailure(let error):
            return "\(error.errorCode)"
        case .serverError(let statusCode, _):
            return "http_\(statusCode)"
        case .wordpressError(let code, _, let statusCode, _):
            return "wordpress_\(code)_http_\(statusCode)"
        case .decodingFailure:
            return "decoding_failure"
        }
    }
}

extension Error {
    var reservationAPIDiagnostics: ReservationAPIDiagnostics? {
        (self as? ReservationAPIError)?.diagnostics
    }

    var reservationAPIDeveloperDetail: String? {
        (self as? ReservationAPIError)?.developerDetail
    }

    var isCancellationLike: Bool {
        if self is CancellationError {
            return true
        }

        if let reservationError = self as? ReservationAPIError,
           case .cancelled = reservationError {
            return true
        }

        if let urlError = self as? URLError {
            return urlError.code == .cancelled
        }

        if let reservationError = self as? ReservationAPIError,
           case .networkFailure(let urlError) = reservationError {
            return urlError.code == .cancelled
        }

        return false
    }

    var mayHaveReachedReservationServer: Bool {
        guard let reservationError = self as? ReservationAPIError,
              case ReservationAPIError.networkFailure(let urlError) = reservationError else {
            return false
        }

        switch urlError.code {
        case .networkConnectionLost,
             .timedOut,
             .cannotParseResponse,
             .badServerResponse:
            return true
        default:
            return false
        }
    }

    var isOfflineLike: Bool {
        let urlError: URLError?
        if let direct = self as? URLError {
            urlError = direct
        } else if let reservationError = self as? ReservationAPIError,
                  case .networkFailure(let wrapped) = reservationError {
            urlError = wrapped
        } else {
            urlError = nil
        }

        switch urlError?.code {
        case .some(.notConnectedToInternet),
             .some(.networkConnectionLost),
             .some(.cannotFindHost),
             .some(.cannotConnectToHost),
             .some(.dnsLookupFailed),
             .some(.internationalRoamingOff),
             .some(.dataNotAllowed):
            return true
        default:
            return false
        }
    }
}
