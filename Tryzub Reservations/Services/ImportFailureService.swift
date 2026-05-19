//
//  ImportFailureService.swift
//  Tryzub Reservations
//

import Foundation

protocol ImportFailureServiceProtocol {
    func fetchImportFailures(page: Int, perPage: Int) async throws -> ImportFailuresResponse
}

final class ImportFailureService: ImportFailureServiceProtocol {
    private let client: any ReservationsAPIClientProtocol

    init(client: any ReservationsAPIClientProtocol) {
        self.client = client
    }

    func fetchImportFailures(page: Int = 1, perPage: Int = 50) async throws -> ImportFailuresResponse {
        try await client.fetchImportFailures(page: page, perPage: perPage)
    }
}
