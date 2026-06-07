//
//  Tryzub_ReservationsApp.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import SwiftUI
import SwiftData

private let tryzubAPIBaseURL = URL(string: "https://tryzubchicago.com/wp-json/tryzub/v1")!

@main
struct Tryzub_ReservationsApp: App {
    @StateObject private var credentialStore = AppCredentialStore()
    @StateObject private var roleStore = AppRoleStore()

    var body: some Scene {
        WindowGroup {
            AppRootView(
                credentialStore: credentialStore,
                roleStore: roleStore
            )
        }
        .modelContainer(for: ReservationRecord.self)
    }
}

private struct AppRootView: View {
    @ObservedObject var credentialStore: AppCredentialStore
    @ObservedObject var roleStore: AppRoleStore

    var body: some View {
        Group {
            if let credentials = credentialStore.credentials,
               let role = roleStore.selectedRole {
                ReservationsListView(
                    environment: makeEnvironment(credentials: credentials, role: role),
                    onLogout: logout
                )
                .id("\(role.rawValue)-\(credentials.username)")
                .environmentObject(roleStore)
            } else {
                AppLoginView(
                    credentialStore: credentialStore,
                    roleStore: roleStore
                )
            }
        }
        .onChange(of: credentialStore.credentials) { _, credentials in
            if credentials == nil {
                roleStore.clear()
            }
        }
    }

    private func makeEnvironment(credentials: AppCredentials, role: AppUserRole) -> AppEnvironment {
        AppEnvironment(
            apiClient: ReservationsAPIClient(
                baseURL: tryzubAPIBaseURL,
                username: credentials.username,
                applicationPassword: credentials.applicationPassword
            ),
            role: role,
            username: credentials.username
        )
    }

    private func logout() {
        roleStore.clear()
        credentialStore.reset()
    }
}

private struct AppLoginView: View {
    @ObservedObject var credentialStore: AppCredentialStore
    @ObservedObject var roleStore: AppRoleStore

    @State private var role: AppUserRole = .manager
    @State private var username = ""
    @State private var applicationPassword = ""
    @State private var errorMessage: String?
    @State private var isSigningIn = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case username
        case password
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("Tryzub Reservations")
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)

                        Text("Use your app password.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 28)

                    VStack(spacing: 16) {
                        Picker("Role", selection: $role) {
                            Text("Manager").tag(AppUserRole.manager)
                            Text("Developer").tag(AppUserRole.developer)
                        }
                        .pickerStyle(.segmented)

                        VStack(spacing: 12) {
                            TextField("Username", text: $username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .username)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }
                                .tryzubLoginFieldStyle()

                            SecureField("Application Password", text: $applicationPassword)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit { signInIfPossible() }
                                .tryzubLoginFieldStyle()
                        }

                        if let message = errorMessage ?? credentialStore.errorMessage {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            signInIfPossible()
                        } label: {
                            HStack(spacing: 8) {
                                if isSigningIn {
                                    ProgressView()
                                }
                                Text(isSigningIn ? "Signing In" : "Sign In")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!canSubmit)
                    }
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                }
                .frame(maxWidth: 430)
                .padding(.horizontal, 22)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPassword: String {
        applicationPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !isSigningIn && !trimmedUsername.isEmpty && !trimmedPassword.isEmpty
    }

    private func signInIfPossible() {
        guard canSubmit else { return }
        Task { await signIn() }
    }

    private func signIn() async {
        isSigningIn = true
        errorMessage = nil
        credentialStore.errorMessage = nil
        defer { isSigningIn = false }

        do {
            try validateRoleChoice()
            let client = ReservationsAPIClient(
                baseURL: tryzubAPIBaseURL,
                username: trimmedUsername,
                applicationPassword: trimmedPassword
            )
            _ = try await client.fetchRestaurantSetup(reason: .login)

            let saved = credentialStore.save(
                username: trimmedUsername,
                applicationPassword: trimmedPassword
            )
            if !saved {
                errorMessage = credentialStore.errorMessage ?? "Sign in failed. Check your username and app password."
                return
            }
            roleStore.select(role)
        } catch {
            errorMessage = loginMessage(for: error)
        }
    }

    private func validateRoleChoice() throws {
        guard role == .developer,
              trimmedUsername.caseInsensitiveCompare("manager.tryzub") == .orderedSame else {
            return
        }
        throw LoginValidationError.roleMismatch
    }

    private func loginMessage(for error: Error) -> String {
        if error is LoginValidationError {
            return "Sign in failed. Check your username and app password."
        }
        if error.isOfflineLike || error.isLoginConnectionFailure {
            return "Could not connect. Try again."
        }
        if error.isLoginAccessFailure {
            return "Sign in failed. Check your username and app password."
        }
        return "Sign in failed. Check your username and app password."
    }
}

private enum LoginValidationError: Error {
    case roleMismatch
}

private extension View {
    func tryzubLoginFieldStyle() -> some View {
        padding(.horizontal, 13)
            .frame(minHeight: 48)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
    }
}

private extension Error {
    var isLoginConnectionFailure: Bool {
        if let urlError = self as? URLError {
            return urlError.code == .timedOut
                || urlError.code == .cannotConnectToHost
                || urlError.code == .cannotFindHost
                || urlError.code == .dnsLookupFailed
        }
        if let apiError = self as? ReservationAPIError,
           case .networkFailure(let urlError) = apiError {
            return urlError.code == .timedOut
                || urlError.code == .cannotConnectToHost
                || urlError.code == .cannotFindHost
                || urlError.code == .dnsLookupFailed
        }
        return false
    }

    var isLoginAccessFailure: Bool {
        guard let apiError = self as? ReservationAPIError else { return false }
        switch apiError {
        case .unauthorized:
            return true
        case .wordpressError(_, _, let statusCode, _),
             .serverError(let statusCode, _):
            return statusCode == 401 || statusCode == 403
        case .invalidURL, .invalidResponse, .cancelled, .networkFailure, .decodingFailure, .missingCredentials:
            return false
        }
    }
}
