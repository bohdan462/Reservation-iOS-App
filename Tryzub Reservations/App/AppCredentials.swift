//
//  AppCredentials.swift
//  Tryzub Reservations
//

import Foundation
import Combine
import Security
import CryptoKit

struct AppCredentials: Codable, Equatable {
    let username: String
    let applicationPassword: String

    var isComplete: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !applicationPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum AppAuthTrace {
    static func credentialSelected(
        role: AppUserRole,
        hasUsername: Bool,
        hasPassword: Bool,
        keychainKey: String
    ) {
        #if DEBUG
        print(
            "[IOS_AUTH_TRACE] phase=credential_selected role=\(role.rawValue) hasUsername=\(hasUsername) hasPassword=\(hasPassword) keychainKey=\(keychainKey)"
        )
        #endif
    }

    static func request(
        route: String,
        role: AppUserRole?,
        username: String?,
        authHeaderPresent: Bool
    ) {
        #if DEBUG
        let roleLabel = role?.rawValue ?? "unknown"
        let usernameLabel = username.map(safeUsernameLabel) ?? "none"
        print(
            "[IOS_AUTH_TRACE] phase=request route=\(route) role=\(roleLabel) username=\(usernameLabel) authHeaderPresent=\(authHeaderPresent)"
        )
        #endif
    }

    static func validationResult(role: AppUserRole, status: Int?, result: String) {
        #if DEBUG
        let statusLabel = status.map(String.init) ?? "none"
        print(
            "[IOS_AUTH_TRACE] phase=validation_result role=\(role.rawValue) status=\(statusLabel) result=\(result)"
        )
        #endif
    }

    static func fallbackBlocked(reason: String) {
        #if DEBUG
        print("[IOS_AUTH_TRACE] phase=fallback_blocked reason=\(reason)")
        #endif
    }

    private static func safeUsernameLabel(_ username: String) -> String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "empty" }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        let prefix = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(trimmed.prefix(3))…#\(prefix)"
    }
}

@MainActor
final class AppCredentialStore: ObservableObject {
    @Published private(set) var credentials: AppCredentials?
    @Published var errorMessage: String?

    private let keychain = AppCredentialKeychain()
    private var activeRole: AppUserRole?

    init() {
        if let raw = UserDefaults.standard.string(forKey: "app.selectedRole"),
           let role = AppUserRole(rawValue: raw),
           AppRoleStore.selectableRoles.contains(role) {
            reload(for: role)
        }
    }

    func reload(for role: AppUserRole?) {
        activeRole = role
        guard let role else {
            credentials = nil
            return
        }

        keychain.migrateLegacyCredentialIfNeeded(for: role)
        let loaded = Self.environmentCredentials(for: role) ?? keychain.load(for: role)
        credentials = loaded
        AppAuthTrace.credentialSelected(
            role: role,
            hasUsername: loaded?.username.isEmpty == false,
            hasPassword: loaded?.applicationPassword.isEmpty == false,
            keychainKey: keychain.accountKey(for: role)
        )
    }

    @discardableResult
    func save(username: String, applicationPassword: String, for role: AppUserRole) -> Bool {
        let credentials = AppCredentials(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            applicationPassword: applicationPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard credentials.isComplete else {
            errorMessage = "WordPress username and application password are required."
            return false
        }

        do {
            try keychain.save(credentials, for: role)
            keychain.deleteLegacy()
            activeRole = role
            self.credentials = credentials
            errorMessage = nil
            AppAuthTrace.credentialSelected(
                role: role,
                hasUsername: true,
                hasPassword: true,
                keychainKey: keychain.accountKey(for: role)
            )
            return true
        } catch {
            errorMessage = "Could not save credentials to Keychain."
            return false
        }
    }

    func reset(for role: AppUserRole? = nil) {
        if let role {
            keychain.delete(for: role)
            if activeRole == role {
                credentials = nil
            }
            return
        }

        for role in AppRoleStore.selectableRoles {
            keychain.delete(for: role)
        }
        credentials = nil
        activeRole = nil
    }

    private static func environmentCredentials(for role: AppUserRole) -> AppCredentials? {
        #if DEBUG
        guard role == .developer else { return nil }
        #else
        return nil
        #endif

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
    private let legacyAccount = "application-password"

    func accountKey(for role: AppUserRole) -> String {
        "application-password.\(role.rawValue)"
    }

    func load(for role: AppUserRole) -> AppCredentials? {
        load(account: accountKey(for: role))
    }

    func save(_ credentials: AppCredentials, for role: AppUserRole) throws {
        delete(for: role)

        let data = try JSONEncoder().encode(credentials)
        var query = baseQuery(account: accountKey(for: role))
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    func delete(for role: AppUserRole) {
        SecItemDelete(baseQuery(account: accountKey(for: role)) as CFDictionary)
    }

    func migrateLegacyCredentialIfNeeded(for role: AppUserRole) {
        guard role == .developer,
              load(for: role) == nil,
              let legacy = load(account: legacyAccount) else {
            return
        }

        do {
            try save(legacy, for: role)
            deleteLegacy()
        } catch {
            #if DEBUG
            print("[IOS_AUTH_TRACE] phase=fallback_blocked reason=legacy_keychain_migration_failed")
            #endif
        }
    }

    func deleteLegacy() {
        SecItemDelete(baseQuery(account: legacyAccount) as CFDictionary)
    }

    private func load(account: String) -> AppCredentials? {
        var query = baseQuery(account: account)
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

    private func baseQuery(account: String) -> [String: Any] {
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
