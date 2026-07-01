//
//  HostBoardReservationRow.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

struct HostBoardReservationRow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var floorPlanStore: FloorPlanStore

    let reservation: ReservationRecord
    var referenceNow = Date()
    let environment: AppEnvironment
    let onAction: (ReservationHostAction, ReservationRecord) -> Void
    let onOpenReservation: (ReservationRecord) -> Void

    @State private var tableAssignmentReservation: ReservationRecord?
    @State private var seatPromptReservation: ReservationRecord?
    @State private var seatAfterTableAssignment = false

    var body: some View {
        // Reuses the same compact reservation cell used by Schedule and Review.
        ReservationRowView(
            reservation: reservation,
            showsDate: false,
            context: rowContext,
            contextNote: seatedDurationText,
            seatedDurationDotStyle: seatedDurationDotStyle,
            capabilities: controller.capabilities,
            onTableTap: controller.capabilities.canEditReservationDetails && !controller.isNetworkDegraded
                ? { tableAssignmentReservation = reservation }
                : nil,
            displayStyle: .hostBoard,
            showsAutoConfirmedAdornment: showsAutoConfirmedAdornment
        ) {
            ReservationActionButtons(
                reservation: reservation,
                capabilities: controller.capabilities,
                compact: true,
                includeSecondary: false,
                compactMinHeight: 40,
                hostBoardGlassActions: true,
                isBusy: controller.isActionInProgress(for: reservation) || controller.isNetworkDegraded,
                onAction: { action in
                    handle(action)
                },
                onSeatRequiresTableChoice: {
                    seatPromptReservation = reservation
                }
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ReservationHaptics.selection()
            onOpenReservation(reservation)
        }
        .onLongPressGesture {
            ReservationHaptics.lightImpact()
        }
        .contextMenu {
            Button {
                onOpenReservation(reservation)
            } label: {
                Label("Details", systemImage: "info.circle")
            }

            ForEach(actionPolicy.contextMenuActions) { action in
                Button(role: action.role) {
                    handle(action)
                } label: {
                    Label(action.fullTitle, systemImage: action.systemImage)
                }
            }
        }
        .reservationSeatTableChoice(
            seatPromptReservation: $seatPromptReservation,
            onAssignTable: { reservation in
                seatAfterTableAssignment = true
                tableAssignmentReservation = reservation
            },
            onSeatWithoutTable: { reservation in
                onAction(.seat, reservation)
            }
        )
        .sheet(item: $tableAssignmentReservation) { reservation in
            TableAssignmentSheet(reservation: reservation) { tableName in
                await TableAssignmentCoordinator.assign(
                    reservationID: reservation.remoteID,
                    tableName: tableName,
                    floorPlanStore: floorPlanStore,
                    controller: controller,
                    context: modelContext
                )
                if seatAfterTableAssignment {
                    seatAfterTableAssignment = false
                    await controller.updateStatus(
                        reservation: reservation,
                        status: .seated,
                        context: modelContext
                    )
                    ReservationHaptics.success()
                }
            }
        }
    }

    private var actionPolicy: ReservationHostActionPolicy {
        ReservationHostActionPolicy(reservation: reservation, capabilities: controller.capabilities)
    }

    private var rowContext: ReservationRowContext {
        if reservation.statusValue == .seated {
            return .todaySeated
        }
        return .todayUpcoming
    }

    private var seatedDurationText: String? {
        controller.seatedDurationText(for: reservation, now: referenceNow)
    }

    private var seatedDurationDotStyle: TryzubStaffStatusDotStyle? {
        guard rowContext == .todaySeated else { return nil }
        return controller.seatedDurationDotStyle(for: reservation, now: referenceNow)
    }

    private var showsAutoConfirmedAdornment: Bool {
        reservation.isAutoConfirmedByBackend
    }

    private func handle(_ action: ReservationHostAction) {
        if action == .assignTable {
            tableAssignmentReservation = reservation
        } else {
            onAction(action, reservation)
        }
    }
}
