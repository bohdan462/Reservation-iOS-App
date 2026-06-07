//
//  AppRoleStore.swift
//  Tryzub Reservations
//

import Combine
import Foundation

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
