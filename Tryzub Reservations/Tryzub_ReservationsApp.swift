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
    private let environment = AppEnvironment(
        apiClient: ReservationsAPIClient(
            baseURL: URL(string: "https://tryzubchicago.com/wp-json/tryzub/v1")!,
            username: "bohdanmsolovey",
            applicationPassword: "oMPAPyF3Jk35BSThYV7ACSLy"
        ),
        role: .developer
    )

    var body: some Scene {
        WindowGroup {
            ReservationsListView(environment: environment)
        }
        .modelContainer(for: ReservationRecord.self)
    }
}
