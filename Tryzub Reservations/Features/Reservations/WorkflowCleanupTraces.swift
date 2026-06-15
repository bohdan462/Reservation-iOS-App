//
//  WorkflowCleanupTraces.swift
//  Tryzub Reservations
//
//  DEBUG-only traces for production workflow cleanup paths.
//

import Foundation

private let enableVerboseDateFilterTrace = false

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

enum DateBoundaryTrace {
    static func isLikelyAfterClose(selectedDate: Date, now: Date = Date()) -> Bool {
        guard selectedDate.reservationDateString() == now.reservationDateString() else { return false }
        let hour = Calendar.current.component(.hour, from: now)
        return hour >= 22
    }

    static func boundary(
        source: String,
        selectedDate: String,
        serviceDate: String,
        afterClose: Bool,
        autoAdvanced: Bool,
        decision: String,
        reason: String
    ) {
        #if DEBUG
        let timestamp = ReservationFormatters.serverDateMinute.string(from: Date())
        print(
            "[DATE_BOUNDARY_TRACE] now=\(timestamp) selectedDate=\(selectedDate) serviceDate=\(serviceDate) afterClose=\(afterClose) autoAdvanced=\(autoAdvanced)"
        )
        print(
            "[DATE_BOUNDARY_TRACE] source=\(source) decision=\(decision) reason=\(reason)"
        )
        #endif
    }

    static func selectedDateFilter(
        selectedDate: String,
        recordDate: String,
        reservationID: Int,
        included: Bool,
        reason: String
    ) {
        #if DEBUG
        guard enableVerboseDateFilterTrace else { return }
        print(
            "[SELECTED_DATE_FILTER_TRACE] selectedDate=\(selectedDate) recordDate=\(recordDate) reservation=\(reservationID) included=\(included) reason=\(reason)"
        )
        #endif
    }

    static func afterClose(
        selectedDate: String,
        afterClose: Bool,
        todayRows: Int,
        tomorrowRowsFilteredOut: Int
    ) {
        #if DEBUG
        print(
            "[AFTER_CLOSE_TRACE] selectedDate=\(selectedDate) afterClose=\(afterClose) todayRows=\(todayRows) tomorrowRowsFilteredOut=\(tomorrowRowsFilteredOut)"
        )
        #endif
    }
}
