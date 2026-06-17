//
//  AutoConfirmDryRunDiagnosticsSection.swift
//  Tryzub Reservations
//

import SwiftUI

struct AutoConfirmDryRunDiagnosticsSection: View {
    let environment: AppEnvironment

    var body: some View {
        Section {
            AutoConfirmDryRunPreviewSection(
                apiClient: environment.apiClient,
                buttonTitle: "Run auto-confirm dry-run"
            )
        } header: {
            Text("Auto-Confirm Dry Run")
        } footer: {
            Text("Read-only GET /auto-confirm/candidates. Does not confirm reservations or send email.")
        }
    }
}
