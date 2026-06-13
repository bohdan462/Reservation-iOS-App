//
//  TryzubSiriShortcutsProvider.swift
//  Tryzub Reservations
//

import AppIntents

struct TryzubSiriShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetTryzubHostSummaryIntent(),
            phrases: [
                "Get \(.applicationName) host summary",
                "Check \(.applicationName) reservations",
                "What's happening at \(.applicationName) today",
                "Show \(.applicationName) host board"
            ],
            shortTitle: "Host Summary",
            systemImageName: "list.bullet.clipboard"
        )
    }
}
