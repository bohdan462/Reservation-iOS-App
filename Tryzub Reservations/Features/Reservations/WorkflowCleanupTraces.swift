//
//  WorkflowCleanupTraces.swift
//  Tryzub Reservations
//
//  DEBUG-only traces for production workflow cleanup paths.
//

import Foundation

enum ConfirmFlowTrace {
    static func log(reservationID: Int, phase: String, fields: [String: String] = [:]) {
        #if DEBUG
        var parts = [
            "[CONFIRM_FLOW_TRACE]",
            "reservation=\(reservationID)",
            "phase=\(phase)"
        ]
        for key in fields.keys.sorted() {
            if let value = fields[key] {
                parts.append("\(key)=\(value)")
            }
        }
        print(parts.joined(separator: " "))
        #endif
    }
}

enum WorkflowCleanupTrace {
    static func log(_ name: String, fields: [String: String] = [:]) {
        #if DEBUG
        var parts = ["[\(name)]"]
        for key in fields.keys.sorted() {
            if let value = fields[key] {
                parts.append("\(key)=\(value)")
            }
        }
        print(parts.joined(separator: " "))
        #endif
    }
}
