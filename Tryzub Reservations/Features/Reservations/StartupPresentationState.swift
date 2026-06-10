//
//  StartupPresentationState.swift
//  Tryzub Reservations
//
//  Presentation-only startup entrance state for cache-first launch.
//

import Foundation

enum StartupPresentationState: Equatable {
    case checkingCache
    case loadingSavedReservations
    case emptyCacheLoadingNetwork
    case showingCachedDataRefreshing
    case ready
    case failedNoCache(String)
}

enum StartupCacheLoadingMode: Equatable {
    case checkingSavedData
    case loadingSavedReservations
    case loadingFromNetwork
}

// MARK: - Calm startup progress (presentation only)

enum StartupProgressStep: Int, CaseIterable, Comparable, Equatable {
    case checkingSavedData
    case showingSavedData
    case checkingService
    case loadingTodayOperations
    case ready

    static func < (lhs: StartupProgressStep, rhs: StartupProgressStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .checkingSavedData:
            return "Checking saved data"
        case .showingSavedData:
            return "Showing saved reservations"
        case .checkingService:
            return "Checking Tryzub service"
        case .loadingTodayOperations:
            return "Loading today's operations"
        case .ready:
            return "Ready"
        }
    }

    var systemImage: String {
        switch self {
        case .checkingSavedData:
            return "internaldrive"
        case .showingSavedData:
            return "calendar"
        case .checkingService:
            return "network"
        case .loadingTodayOperations:
            return "sun.max"
        case .ready:
            return "checkmark.circle"
        }
    }
}

enum StartupProgressStepStatus: Equatable {
    case pending
    case active
    case done
}

struct StartupProgressPresentation: Equatable {
    let activeStep: StartupProgressStep
    let stepStatus: [StartupProgressStep: StartupProgressStepStatus]
    let headline: String
    let subtitle: String?

    static let preparing = StartupProgressPresentation(
        activeStep: .checkingSavedData,
        stepStatus: [:],
        headline: "Preparing reservations…",
        subtitle: "Checking saved data…"
    )
}

enum StartupProgressPresenter {
  static let staffNoCacheFailureMessage =
    "Could not load reservations. Check the connection and try again."

    static func fullScreen(
        presentationState: StartupPresentationState,
        backgroundWork: StartupBackgroundWorkState
    ) -> StartupProgressPresentation {
        switch presentationState {
        case .checkingCache:
            return StartupProgressPresentation(
                activeStep: .checkingSavedData,
                stepStatus: statuses(active: .checkingSavedData, completedBefore: .checkingSavedData),
                headline: "Preparing reservations…",
                subtitle: "Checking saved data…"
            )

        case .loadingSavedReservations:
            return StartupProgressPresentation(
                activeStep: .showingSavedData,
                stepStatus: statuses(active: .showingSavedData, completedBefore: .showingSavedData),
                headline: "Preparing reservations…",
                subtitle: "Showing saved reservations…"
            )

        case .emptyCacheLoadingNetwork:
            let activeStep = activeNetworkStep(for: backgroundWork)
            return StartupProgressPresentation(
                activeStep: activeStep,
                stepStatus: statuses(active: activeStep, completedBefore: activeStep),
                headline: networkHeadline(for: backgroundWork),
                subtitle: networkSubtitle(for: backgroundWork)
            )

        case .failedNoCache:
            return StartupProgressPresentation(
                activeStep: .checkingService,
                stepStatus: statuses(active: .checkingService, completedBefore: .checkingService),
                headline: staffNoCacheFailureMessage,
                subtitle: nil
            )

        case .showingCachedDataRefreshing, .ready:
            return StartupProgressPresentation(
                activeStep: .ready,
                stepStatus: statuses(active: .ready, completedBefore: .ready),
                headline: "Ready",
                subtitle: nil
            )
        }
    }

    private static func activeNetworkStep(
        for backgroundWork: StartupBackgroundWorkState
    ) -> StartupProgressStep {
        switch backgroundWork {
        case .loadingTodayOperations:
            return .loadingTodayOperations
        case .checkingFreshness, .updatingServiceSetup, .checkingSavedData:
            return .checkingService
        case .idle, .ready:
            return .checkingService
        }
    }

    private static func networkHeadline(for backgroundWork: StartupBackgroundWorkState) -> String {
        switch backgroundWork {
        case .loadingTodayOperations:
            return "Loading today's board…"
        case .updatingServiceSetup:
            return "Connecting to Tryzub service…"
        case .checkingFreshness, .checkingSavedData:
            return "Connecting to Tryzub service…"
        case .idle, .ready:
            return "Preparing reservations…"
        }
    }

    private static func networkSubtitle(for backgroundWork: StartupBackgroundWorkState) -> String? {
        switch backgroundWork {
        case .loadingTodayOperations:
            return "Loading today's operations…"
        case .updatingServiceSetup:
            return "Checking Tryzub service…"
        case .checkingFreshness:
            return "Checking Tryzub service…"
        case .checkingSavedData:
            return "Checking saved data…"
        case .idle, .ready:
            return nil
        }
    }

    private static func statuses(
        active: StartupProgressStep,
        completedBefore: StartupProgressStep
    ) -> [StartupProgressStep: StartupProgressStepStatus] {
        var result: [StartupProgressStep: StartupProgressStepStatus] = [:]
        for step in StartupProgressStep.allCases {
            if step < completedBefore {
                result[step] = .done
            } else if step == active {
                result[step] = .active
            } else {
                result[step] = .pending
            }
        }
        return result
    }
}
