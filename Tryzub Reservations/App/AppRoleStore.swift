//
//  AppRoleStore.swift
//  Tryzub Reservations
//

import Combine
import SwiftUI

@MainActor
final class AppRoleStore: ObservableObject {
    @Published private(set) var selectedRole: AppUserRole?

    private let defaultsKey = "app.selectedRole"

    static let selectableRoles: [AppUserRole] = [.manager, .developer]

    init() {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let role = AppUserRole(rawValue: raw),
           Self.selectableRoles.contains(role) {
            selectedRole = role
        }
    }

    func select(_ role: AppUserRole) {
        guard Self.selectableRoles.contains(role) else { return }
        selectedRole = role
        UserDefaults.standard.set(role.rawValue, forKey: defaultsKey)
    }

    func clear() {
        selectedRole = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

struct RoleSelectionView: View {
    @ObservedObject var roleStore: AppRoleStore

    @State private var pendingRole: AppUserRole = .manager

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose how this device should behave while you test the app. You can switch later in More.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("App Role") {
                    Picker("Role", selection: $pendingRole) {
                        ForEach(AppRoleStore.selectableRoles, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section {
                    RoleSelectionSummary(role: pendingRole)
                }

                Section {
                    Button("Continue") {
                        roleStore.select(pendingRole)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Select Role")
        }
    }
}

private struct RoleSelectionSummary: View {
    let role: AppUserRole

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(role.displayName)
                .font(.headline)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var summary: String {
        switch role {
        case .manager:
            return "Restaurant operations: confirm, settings, analytics, and hidden reservations. No API diagnostics or hard delete."
        case .developer:
            return "Everything manager can do, plus API diagnostics and permanent test-reservation cleanup."
        case .staff:
            return ""
        }
    }
}
