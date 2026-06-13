//
//  ReservationActivityInvalidation.swift
//  Tryzub Reservations
//
//  Local invalidation after successful mutations. iOS never writes activity.
//

import Foundation
import OSLog

enum ReservationActivityInvalidation {
    static let notification = Notification.Name("ReservationActivityInvalidation.reservationChanged")

    enum UserInfoKey {
        static let reservationID = "reservationID"
        static let date = "date"
        static let mutationActivity = "mutationActivity"
    }

    static func post(
        reservationID: Int,
        date: String?,
        mutationActivity: MutationActivityResultDTO? = nil
    ) {
        var info: [String: Any] = [UserInfoKey.reservationID: reservationID]
        if let date { info[UserInfoKey.date] = date }
        if let mutationActivity { info[UserInfoKey.mutationActivity] = mutationActivity }

        NotificationCenter.default.post(name: notification, object: nil, userInfo: info)

        if let mutationActivity {
            ReservationActivityMutationTrace.emit(
                reservationID: reservationID,
                mutationActivity: mutationActivity
            )
        }
    }
}

enum ReservationActivityMutationTrace {
    #if DEBUG
    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "ReservationActivity"
    )
    #endif

    static func emit(reservationID: Int, mutationActivity: MutationActivityResultDTO) {
        let created = mutationActivity.created == true
        let types = (mutationActivity.eventTypes ?? []).joined(separator: ",")
        #if DEBUG
        logger.debug(
            "[ACTIVITY_MUTATION_TRACE] reservation=\(reservationID, privacy: .public) backendActivityCreated=\(created, privacy: .public) eventTypes=\(types, privacy: .public)"
        )
        #endif
    }
}
