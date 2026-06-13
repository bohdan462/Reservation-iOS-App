//
//  HostFloorTableSource.swift
//  Tryzub Reservations
//
//  Explicit floor-table provenance for Host / Service Intelligence.
//  Backend floor plan is canonical; local HostTableConfigStore is advisory fallback only.
//

import Foundation

enum HostFloorTableSource: Equatable {
    case pendingBackend
    case backend
    case notConfigured
    case unavailable
    case legacyFallback

    /// Stable token for proof traces ([HOST_AI_FACTS_TRACE], [TABLE_CAPACITY_TRACE]).
    var traceLabel: String {
        switch self {
        case .pendingBackend: return "pendingBackend"
        case .backend: return "backend"
        case .notConfigured: return "notConfigured"
        case .unavailable: return "unavailable"
        case .legacyFallback: return "legacyFallback"
        }
    }

    /// Table-fit, capacity-conflict, and booking-load seat math require canonical backend layout.
    var supportsTableIntelligence: Bool {
        switch self {
        case .backend, .legacyFallback:
            return true
        case .pendingBackend, .notConfigured, .unavailable:
            return false
        }
    }

    var usesCanonicalBackendLayout: Bool {
        self == .backend
    }
}

enum HostFloorSourceSupport {

    static func briefingFacts(for source: HostFloorTableSource) -> [HostBriefingFact] {
        switch source {
        case .notConfigured:
            return [
                HostBriefingFact(
                    id: "floor-not-configured",
                    severity: .info,
                    category: .sync,
                    title: "Floor plan not set up yet",
                    detail: "Set up tables in the Floor tab.",
                    evidence: ["floorSource=notConfigured"],
                    relatedReservationIDs: [],
                    suggestedActionTitle: nil
                )
            ]
        case .unavailable:
            return [
                HostBriefingFact(
                    id: "floor-unavailable",
                    severity: .info,
                    category: .sync,
                    title: "Floor plan could not load",
                    detail: "Table layout is temporarily unavailable.",
                    evidence: ["floorSource=unavailable"],
                    relatedReservationIDs: [],
                    suggestedActionTitle: nil
                )
            ]
        case .legacyFallback:
            return [
                HostBriefingFact(
                    id: "floor-legacy-fallback",
                    severity: .info,
                    category: .sync,
                    title: "Advisory table setup",
                    detail: "Local table setup is being used as a fallback.",
                    evidence: ["floorSource=legacyFallback", "advisory=true"],
                    relatedReservationIDs: [],
                    suggestedActionTitle: nil
                )
            ]
        case .pendingBackend, .backend:
            return []
        }
    }

    static func resolveEngineTables(
        source: HostFloorTableSource,
        backendTables: [RestaurantTableDTO],
        advisoryTables: [RestaurantTableConfig]
    ) -> (backendFloorTables: [RestaurantTableDTO], tableConfigs: [RestaurantTableConfig]) {
        switch source {
        case .backend:
            return (backendTables, [])
        case .legacyFallback:
            return ([], advisoryTables)
        case .pendingBackend, .notConfigured, .unavailable:
            return ([], [])
        }
    }
}
