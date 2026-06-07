//
//  ReservationFloatingTabBar.swift
//  Tryzub Reservations
//

import Foundation

enum ReservationsAppTab: Hashable, CaseIterable, Identifiable {
    case host
    case bookings
    case guests
    case more

    var id: Self { self }

    var title: String {
        switch self {
        case .host:
            return "Host"
        case .bookings:
            return "Bookings"
        case .guests:
            return "Guests"
        case .more:
            return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .host:
            return "house"
        case .bookings:
            return "calendar"
        case .guests:
            return "person.2"
        case .more:
            return "ellipsis"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .host:
            return "house.fill"
        case .bookings:
            return "calendar"
        case .guests:
            return "person.2.fill"
        case .more:
            return "ellipsis"
        }
    }
}
