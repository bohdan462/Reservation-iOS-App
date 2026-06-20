//
//  HostBoardReminderSection.swift
//  Tryzub Reservations
//

import SwiftUI

struct HostReminderPanelContext {
    let status: ReservationReminderStatusResponse?
    let notice: String?
    let isSending: Bool
    let showProof: Bool
    let hasEligibleReminders: Bool
    let manualSendEnabled: Bool
    let backendManualBatchEnabled: Bool
    let automaticRemindersEnabled: Bool
    let reminderLeadHours: Int
    let emailUsage: ResolvedEmailUsage
    let dailyEmailLimitReached: Bool
    let canSendBatchReminders: Bool
    let summary: HostReminderStaffSummary

    var shortStateLine: String {
        if isSending {
            return "Sending reminders"
        }
        if dailyEmailLimitReached {
            return "Daily limit reached"
        }
        let eligible = status?.summary.eligible ?? 0
        if canSendBatchReminders, eligible > 0 {
            return "\(eligible) due"
        }
        if let failed = status?.summary.failed, failed > 0 {
            return "\(failed) need check"
        }
        if summary.severity == .ok {
            return "Handled today"
        }
        if eligible == 0 {
            return "No reminders due"
        }
        return summary.message
    }

    var stateTint: Color {
        switch summary.severity {
        case .ok:
            return TryzubColors.primaryText
        case .attention:
            return TryzubColors.warning
        case .blocked:
            return TryzubColors.mutedText
        case .info:
            return TryzubColors.mutedText
        }
    }
}

struct HostReminderBatchCard: View {
    let status: ReservationReminderStatusResponse?
    let notice: String?
    let isSending: Bool
    let showProof: Bool
    let hasEligibleReminders: Bool
    let manualSendEnabled: Bool
    let backendManualBatchEnabled: Bool
    let automaticRemindersEnabled: Bool
    let reminderLeadHours: Int
    let emailUsage: ResolvedEmailUsage
    let dailyEmailLimitReached: Bool
    let canSendBatchReminders: Bool
    let onSend: () -> Void

    private var summary: HostReminderStaffSummary {
        HostReminderStaffSummary.build(
            status: status,
            automaticRemindersEnabled: automaticRemindersEnabled,
            manualSendEnabled: manualSendEnabled,
            backendManualBatchEnabled: backendManualBatchEnabled,
            reminderLeadHours: reminderLeadHours,
            dailyEmailLimitReached: dailyEmailLimitReached,
            canSendBatchReminders: canSendBatchReminders,
            isLoading: showProof && status == nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(summary.title, systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(summary.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let secondary = summary.secondary {
                Text(secondary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if canSendBatchReminders {
                Button {
                    onSend()
                } label: {
                    Label(summary.actionLabel ?? "Send reminders", systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isSending)
            } else if let actionLabel = summary.actionLabel {
                Text(actionLabel)
                    .frame(maxWidth: .infinity)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
                    .padding(.vertical, 10)
            }

            if let notice, !notice.isEmpty {
                Text(notice)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .hostBoardGlassPanel(cornerRadius: 12)
    }
}

struct HostReminderStaffSummary {
    enum Severity {
        case ok
        case attention
        case blocked
        case info
    }

    let title: String
    let message: String
    let secondary: String?
    let actionLabel: String?
    let severity: Severity

    static func build(
        status: ReservationReminderStatusResponse?,
        automaticRemindersEnabled: Bool,
        manualSendEnabled: Bool,
        backendManualBatchEnabled: Bool,
        reminderLeadHours: Int,
        dailyEmailLimitReached: Bool,
        canSendBatchReminders: Bool,
        isLoading: Bool
    ) -> HostReminderStaffSummary {
        let title = "Guest reminders"

        if isLoading {
            return HostReminderStaffSummary(
                title: title,
                message: "Checking whether guests still need reminders.",
                secondary: nil,
                actionLabel: nil,
                severity: .info
            )
        }

        if !automaticRemindersEnabled {
            return HostReminderStaffSummary(
                title: title,
                message: "Automatic reminders are off.",
                secondary: nil,
                actionLabel: canSendBatchReminders ? "Send reminders" : nil,
                severity: canSendBatchReminders ? .attention : .info
            )
        }

        if dailyEmailLimitReached {
            return HostReminderStaffSummary(
                title: title,
                message: "Reminder sending is paused for today.",
                secondary: "The daily email limit has been reached.",
                actionLabel: nil,
                severity: .blocked
            )
        }

        if manualSendEnabled && !backendManualBatchEnabled {
            return HostReminderStaffSummary(
                title: title,
                message: "Guest reminders are controlled from Restaurant Settings.",
                secondary: "Manual batch sending is off for this restaurant.",
                actionLabel: nil,
                severity: .info
            )
        }

        let eligible = status?.summary.eligible ?? 0
        if canSendBatchReminders, eligible > 0 {
            return HostReminderStaffSummary(
                title: title,
                message: "\(eligible) \(eligible == 1 ? "reminder can" : "reminders can") be sent now.",
                secondary: "Send reminders before the dinner rush.",
                actionLabel: "Send reminders",
                severity: .attention
            )
        }

        if let status {
            let skipped = status.summary.skipped
            let failed = status.summary.failed
            if failed > 0 {
                return HostReminderStaffSummary(
                    title: title,
                    message: "\(failed) \(failed == 1 ? "reminder needs" : "reminders need") a staff check.",
                    secondary: nil,
                    actionLabel: nil,
                    severity: .attention
                )
            }
            if skipped > 0 {
                return HostReminderStaffSummary(
                    title: title,
                    message: "No reminders can be sent right now.",
                    secondary: nil,
                    actionLabel: backendManualBatchEnabled ? "No reminders due" : nil,
                    severity: .info
                )
            }
            return HostReminderStaffSummary(
                title: title,
                message: "Guest reminders are handled for today.",
                secondary: "No one needs a reminder right now.",
                actionLabel: backendManualBatchEnabled ? "No reminders due" : nil,
                severity: .ok
            )
        }

        return HostReminderStaffSummary(
            title: title,
            message: "Guest reminders are handled for today.",
            secondary: "No one needs a reminder right now.",
            actionLabel: backendManualBatchEnabled ? "No reminders due" : nil,
            severity: .ok
        )
    }

}
