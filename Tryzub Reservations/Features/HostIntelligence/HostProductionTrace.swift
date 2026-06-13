//
//  HostProductionTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only production traces for Host Intelligence wording, clusters, and routes.
//  Never log prompts, notes, phone numbers, email addresses, or guest names.
//

import Foundation
import OSLog

enum HostProductionTrace {
    #if DEBUG
    private static let isEnabled = true
    #else
    private static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "HostProduction"
    )

    /// Emits a one-line summary of which model files are present at startup or on demand.
    /// Used by the developer diagnostics panel and Instruments.
    /// Format: [MODEL_BUNDLE_STATUS] 3Bbundled=yes/no 3BinAppSupport=yes/no 3BinferenceReady=yes/no 0_5Bbundled=yes/no bestProfile=better_local_3b|small_fast_local|template
    static func modelBundleStatus() {
        guard isEnabled else { return }
        let is3BBundled = HostLocalModelFileLocator.is3BBundled
        let is3BInAppSupport = HostLocalModelFileLocator.is3BInApplicationSupport
        let is3BReady = HostLocalModelFileLocator.inferenceModelURL(profile: .betterLocal3B) != nil
        let isSmallBundled = HostLocalModelFileLocator.bundledModelURL(profile: .smallFastLocal) != nil
        let best = HostLocalModelFileLocator.bestAvailableProfile()
        logger.debug(
            "[MODEL_BUNDLE_STATUS] 3Bbundled=\(is3BBundled ? "yes" : "no", privacy: .public) 3BinAppSupport=\(is3BInAppSupport ? "yes" : "no", privacy: .public) 3BinferenceReady=\(is3BReady ? "yes" : "no", privacy: .public) 0_5Bbundled=\(isSmallBundled ? "yes" : "no", privacy: .public) bestProfile=\(best.traceName, privacy: .public)"
        )
    }

    static func localModelProfile(
        requested: LocalWordingModelProfile,
        resolved: LocalWordingModelProfile,
        reason: String
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[LOCAL_MODEL_PROFILE_TRACE] requested=\(requested.traceName, privacy: .public) resolved=\(resolved.traceName, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    static func localModelLoad(
        profile: LocalWordingModelProfile,
        status: String,
        durationMs: Int
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[LOCAL_MODEL_LOAD_TRACE] profile=\(profile.traceName, privacy: .public) status=\(status, privacy: .public) durationMs=\(durationMs, privacy: .public)"
        )
    }

    static func localModelGeneration(
        surface: String,
        profile: LocalWordingModelProfile,
        status: String,
        durationMs: Int
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[LOCAL_MODEL_GENERATION_TRACE] surface=\(surface, privacy: .public) profile=\(profile.traceName, privacy: .public) status=\(status, privacy: .public) durationMs=\(durationMs, privacy: .public)"
        )
    }

    static func hostActionCluster(
        date: String,
        reservationCount: Int,
        clusterCount: Int,
        signalCounts: [HostReservationSignal: Int],
        duplicateFlatActionsCollapsed: Int
    ) {
        guard isEnabled else { return }
        let signals = signalCounts
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue):\($0.value)" }
            .joined(separator: ",")
        logger.debug(
            "[HOST_ACTION_CLUSTER_TRACE] date=\(date, privacy: .public) reservations=\(reservationCount, privacy: .public) clusters=\(clusterCount, privacy: .public) signals=\(signals, privacy: .public) duplicateFlatActionsCollapsed=\(duplicateFlatActionsCollapsed, privacy: .public)"
        )
    }

    static func hostActionRoute(
        action: HostQuickAction,
        result: String
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[HOST_ACTION_ROUTE_TRACE] action=\(action.traceName, privacy: .public) remoteID=\(action.remoteID, privacy: .public) result=\(result, privacy: .public)"
        )
    }

    static func hostManagerSummary(
        source: String,
        clusterCount: Int,
        headlineLength: Int,
        whyLength: Int,
        checkLength: Int,
        sentenceCount: Int = 0,
        richContext: Bool = false,
        pressureLevel: String? = nil,
        peakWindow: String? = nil,
        blocked: String? = nil
    ) {
        guard isEnabled else { return }
        let peak = peakWindow ?? "none"
        let level = pressureLevel ?? "none"
        let blockedReason = blocked ?? "none"
        logger.debug(
            "[HOST_MANAGER_SUMMARY_TRACE] source=\(source, privacy: .public) clusters=\(clusterCount, privacy: .public) headlineLength=\(headlineLength, privacy: .public) whyLength=\(whyLength, privacy: .public) checkLength=\(checkLength, privacy: .public) sentenceCount=\(sentenceCount, privacy: .public) richContext=\(richContext ? "true" : "false", privacy: .public) pressureLevel=\(level, privacy: .public) peakWindow=\(peak, privacy: .public) blocked=\(blockedReason, privacy: .public)"
        )
    }

    static func guestDraftContext(
        remoteID: Int,
        kind: GuestMessageDraftKind,
        occasion: GuestMessageOccasionFlag,
        source: String
    ) {
        guard isEnabled else { return }
        logger.debug(
            "[GUEST_DRAFT_CONTEXT_TRACE] remoteID=\(remoteID, privacy: .public) kind=\(kind.rawValue, privacy: .public) occasion=\(occasion.rawValue, privacy: .public) source=\(source, privacy: .public)"
        )
    }
}
