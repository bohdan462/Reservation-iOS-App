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

    var body: some Scene {
        WindowGroup {
            if let credentials = credentialStore.credentials {
                ReservationsListView(
                    environment: AppEnvironment(
                        apiClient: ReservationsAPIClient(
                            baseURL: URL(string: "https://tryzubchicago.com/wp-json/tryzub/v1")!,
                            username: credentials.username,
                            applicationPassword: credentials.applicationPassword
                        ),
                        role: .developer
                    )
                )
            } else {
                CredentialsSetupView(credentialStore: credentialStore)
            }
        }
        .modelContainer(for: ReservationRecord.self)
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
