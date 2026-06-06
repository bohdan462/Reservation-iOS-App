//
//  Tryzub_ReservationsApp.swift
//  Tryzub Reservations
//
//  Created by Bohdan Tkachenko on 5/13/26.
//

import SwiftUI
import SwiftData

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
            if let credentials = credentialStore.credentials {
                if let role = roleStore.selectedRole {
                    ReservationsListView(environment: makeEnvironment(credentials: credentials, role: role))
                        .id(role)
                        .environmentObject(roleStore)
                } else {
                    RoleSelectionView(roleStore: roleStore)
                }
            } else {
                CredentialsSetupView(credentialStore: credentialStore)
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
                baseURL: URL(string: "https://tryzubchicago.com/wp-json/tryzub/v1")!,
                username: credentials.username,
                applicationPassword: credentials.applicationPassword
            ),
            role: role
        )
    }
}

private struct CredentialsSetupView: View {
    @ObservedObject var credentialStore: AppCredentialStore

    @State private var username = ""
    @State private var applicationPassword = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Connect this device to the private Tryzub WordPress API.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = credentialStore.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section("WordPress Application Password") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Application Password", text: $applicationPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Save Credentials") {
                        credentialStore.save(
                            username: username,
                            applicationPassword: applicationPassword
                        )
                    }
                    .disabled(
                        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || applicationPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                } footer: {
                    Text("Before TestFlight or  pilot, rotate the exposed WordPress Application Password and enter the new one here.")
                }
            }
            .navigationTitle("API Credentials")
        }
    }
}
