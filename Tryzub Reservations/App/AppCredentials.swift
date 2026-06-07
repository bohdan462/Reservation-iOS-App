//
//  AppCredentials.swift
//  Tryzub Reservations
//

import Foundation
import Combine
import Security

struct AppCredentials: Codable, Equatable {
    let username: String
    let applicationPassword: String

    var isComplete: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !applicationPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
final class AppCredentialStore: ObservableObject {
    @Published private(set) var credentials: AppCredentials?
    @Published var errorMessage: String?

    private let keychain = AppCredentialKeychain()

    init() {
        credentials = Self.environmentCredentials() ?? keychain.load()
    }

    @discardableResult
    func save(username: String, applicationPassword: String) -> Bool {
        let credentials = AppCredentials(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            applicationPassword: applicationPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard credentials.isComplete else {
            errorMessage = "WordPress username and application password are required."
            return false
        }

        do {
            try keychain.save(credentials)
            self.credentials = credentials
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not save credentials to Keychain."
            return false
        }
    }

    func reset() {
        keychain.delete()
        credentials = nil
    }

    private static func environmentCredentials() -> AppCredentials? {
        let environment = ProcessInfo.processInfo.environment
        guard let username = environment["TRYZUB_API_USERNAME"],
              let password = environment["TRYZUB_API_PASSWORD"] else {
            return nil
        }

        let credentials = AppCredentials(username: username, applicationPassword: password)
        return credentials.isComplete ? credentials : nil
    }
}

private struct AppCredentialKeychain {
    private let service = "com.tryzub.reservations.wordpress"
    private let account = "application-password"

    func load() -> AppCredentials? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(AppCredentials.self, from: data)
    }

    func save(_ credentials: AppCredentials) throws {
        delete()

        let data = try JSONEncoder().encode(credentials)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private enum KeychainError: Error {
        case unhandledStatus(OSStatus)
    }
}
