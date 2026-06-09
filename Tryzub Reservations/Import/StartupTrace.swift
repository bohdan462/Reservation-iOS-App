//
//  StartupTrace.swift
//  Tryzub Reservations
//
//  DEBUG-only startup/bootstrap tracing. No PII, no row-level data.
//

import Foundation
import OSLog

enum StartupTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "StartupTrace"
    )

    static func makeInstanceID() -> String {
        String(UUID().uuidString.prefix(4)).uppercased()
    }

    static func makePassID() -> String {
        String(UUID().uuidString.prefix(6)).uppercased()
    }

    static func controllerCreated(id: String, source: String) {
        log(controller: id, event: "controller_created", fields: ["source": source])
    }

    static func productionShellAttached(controllerID: String) {
        log(controller: controllerID, event: "production_shell_attached", fields: [:])
    }

    static func syncServiceCreated(id: String, controllerID: String?) {
        var fields: [String: String] = [:]
        if let controllerID {
            fields["controller"] = controllerID
        }
        log(service: id, event: "sync_service_created", fields: fields)
    }

    static func sessionSync(controllerID: String?, warmup: Bool) {
        log(
            controller: controllerID ?? "none",
            event: "session_sync",
            fields: ["warmup": warmup ? "true" : "false"]
        )
    }

    static func lifecycle(
        controllerID: String,
        event: String,
        cacheHit: Bool? = nil,
        uiReleased: Bool? = nil,
        startupPassActive: Bool? = nil,
        presentationState: String? = nil
    ) {
        var fields: [String: String] = [:]
        if let cacheHit { fields["cacheHit"] = cacheHit ? "true" : "false" }
        if let uiReleased { fields["uiReleased"] = uiReleased ? "true" : "false" }
        if let startupPassActive { fields["startupPassActive"] = startupPassActive ? "true" : "false" }
        if let presentationState { fields["presentation"] = presentationState }
        log(controller: controllerID, event: event, fields: fields)
    }

    static func activeWindow(
        controllerID: String,
        trigger: String,
        scope: String,
        action: String,
        refreshID: String? = nil,
        startupPassID: String? = nil,
        uiReleased: Bool,
        startupPassActive: Bool,
        force: Bool? = nil,
        mode: String? = nil
    ) {
        var fields: [String: String] = [
            "trigger": trigger,
            "scope": scope,
            "action": action,
            "uiReleased": uiReleased ? "true" : "false",
            "startupPassActive": startupPassActive ? "true" : "false",
        ]
        if let refreshID { fields["refreshID"] = refreshID }
        if let startupPassID { fields["startupPassID"] = startupPassID }
        if let force { fields["force"] = force ? "true" : "false" }
        if let mode { fields["mode"] = mode }
        log(controller: controllerID, event: "active_window", fields: fields)
    }

    static func startupPass(
        controllerID: String,
        passID: String,
        phase: String,
        uiReleased: Bool
    ) {
        log(
            controller: controllerID,
            event: "startup_pass",
            fields: [
                "passID": passID,
                "phase": phase,
                "uiReleased": uiReleased ? "true" : "false",
            ]
        )
    }

    static func directAPI(
        caller: String,
        reason: String,
        controllerID: String? = nil
    ) {
        var fields: [String: String] = [
            "caller": caller,
            "reason": reason,
        ]
        if let controllerID {
            fields["controller"] = controllerID
        }
        emit(fields: fields, prefix: "direct_api")
    }

    // MARK: - Private

    private static func log(controller id: String, event: String, fields: [String: String]) {
        var merged = fields
        merged["controller"] = id
        merged["event"] = event
        emit(fields: merged, prefix: "trace")
    }

    private static func log(service id: String, event: String, fields: [String: String]) {
        var merged = fields
        merged["syncService"] = id
        merged["event"] = event
        emit(fields: merged, prefix: "trace")
    }

    private static func emit(fields: [String: String], prefix: String) {
        guard isEnabled else { return }
        let body = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(sanitize($0.value))" }
            .joined(separator: " ")
        logger.debug("[STARTUP_TRACE] \(prefix, privacy: .public) \(body, privacy: .public)")
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
