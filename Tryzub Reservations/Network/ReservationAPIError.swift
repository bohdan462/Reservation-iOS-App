//
//  ReservationAPIError.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import Foundation

enum ReservationAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case networkFailure(URLError)
    case serverError(statusCode: Int)
    case wordpressError(code: String, message: String, statusCode: Int)
    case decodingFailure(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The reservation API URL is invalid."
        case .invalidResponse:
            return "The reservation API returned an invalid response."
        case .unauthorized:
            return "The WordPress username or application password was rejected."
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
        case .serverError(let statusCode):
            return "The reservation API returned HTTP \(statusCode)."
        case .wordpressError(_, let message, _):
            return message
        case .decodingFailure(let error):
            return "Could not read the reservation response: \(error.localizedDescription)"
        }
    }

    var logValue: String {
        switch self {
        case .invalidURL:
            return "invalid_url"
        case .invalidResponse:
            return "invalid_response"
        case .unauthorized:
            return "unauthorized"
        case .networkFailure(let error):
            return "\(error.errorCode)"
        case .serverError(let statusCode):
            return "http_\(statusCode)"
        case .wordpressError(let code, _, let statusCode):
            return "wordpress_\(code)_http_\(statusCode)"
        case .decodingFailure:
            return "decoding_failure"
        }
    }
}

extension Error {
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
}
