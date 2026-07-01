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

struct HostReminderStatsSheet: View {
    let context: HostReminderPanelContext?
    let onSend: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var summary: ReservationReminderSummaryDTO? {
        context?.status?.summary
    }

    private var leadTimeText: String {
        guard let hours = context?.reminderLeadHours else { return "Not loaded" }
        return "\(hours) \(hours == 1 ? "hour" : "hours") before service"
    }

    private var automationText: String {
        guard let context else { return "Not loaded" }
        return context.automaticRemindersEnabled ? "Automatic reminders on" : "Automatic reminders off"
    }

    private var manualText: String {
        guard let context else { return "Not loaded" }
        if context.canSendBatchReminders {
            return "Manual send available now"
        }
        if context.backendManualBatchEnabled {
            return "Manual send enabled"
        }
        return "Manual send off"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headerCard

                    VStack(alignment: .leading, spacing: 8) {
                        reminderStatRow(
                            title: "Accepted",
                            value: summary?.sent ?? 0,
                            systemImage: "paperplane.fill",
                            tint: TryzubColors.info,
                            detail: "Reminder attempts accepted during the latest backend check."
                        )
                        reminderStatRow(
                            title: "Handled",
                            value: summary?.alreadySent ?? 0,
                            systemImage: "checkmark.circle.fill",
                            tint: TryzubColors.success,
                            detail: "Guests who already had a reminder on record."
                        )
                        reminderStatRow(
                            title: "Due",
                            value: summary?.eligible ?? 0,
                            systemImage: "clock.fill",
                            tint: TryzubColors.warning,
                            detail: "Guests eligible for a manual reminder send right now."
                        )
                        reminderStatRow(
                            title: "Skipped",
                            value: summary?.skipped ?? 0,
                            systemImage: "forward.end.fill",
                            tint: TryzubColors.mutedText,
                            detail: "Checked but not eligible, usually because timing or contact rules block it."
                        )
                        reminderStatRow(
                            title: "Failed",
                            value: summary?.failed ?? 0,
                            systemImage: "exclamationmark.triangle.fill",
                            tint: (summary?.failed ?? 0) > 0 ? TryzubColors.warning : TryzubColors.mutedText,
                            detail: "Needs staff attention before the guest can be considered reminded."
                        )
                    }
                    .padding(10)
                    .hostBoardGlassPanel(cornerRadius: 14, strokeOpacity: 0.10)

                    VStack(alignment: .leading, spacing: 8) {
                        reminderInfoRow(title: "Automation", value: automationText, systemImage: "bolt.circle.fill")
                        reminderInfoRow(title: "Manual batch", value: manualText, systemImage: "paperplane.circle.fill")
                        reminderInfoRow(title: "Lead time", value: leadTimeText, systemImage: "timer")
                        if let daily = context?.emailUsage.dailyValueText {
                            reminderInfoRow(title: "Daily email", value: daily, systemImage: "envelope.badge")
                        }
                    }
                    .padding(10)
                    .hostBoardGlassPanel(cornerRadius: 14, strokeOpacity: 0.10)

                    if let notice = context?.notice, !notice.isEmpty {
                        Text(notice)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TryzubColors.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .hostBoardGlassPanel(cornerRadius: 14, strokeOpacity: 0.08)
                    }
                }
                .padding(16)
            }
            .background(TryzubColors.screenBackground.ignoresSafeArea())
            .navigationTitle("Reminder stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.title3.weight(.semibold))
                .foregroundStyle(context?.stateTint ?? TryzubColors.mutedText)
                .frame(width: 38, height: 38)
                .hostBoardGlassChip(cornerRadius: 19, isSelected: false, strokeOpacity: 0.12)

            VStack(alignment: .leading, spacing: 3) {
                Text(context?.summary.title ?? "Guest reminders")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(TryzubColors.primaryText)
                    .lineLimit(1)

                Text(context?.summary.message ?? "Reminder status is not loaded for this date.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if context?.canSendBatchReminders == true {
                Button {
                    onSend()
                    dismiss()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .hostBoardGlassChip(
                            cornerRadius: 19,
                            isSelected: false,
                            strokeOpacity: 0.14
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(TryzubColors.primaryControl)
                .disabled(context?.isSending == true)
                .accessibilityLabel("Send due reminders")
            } else if context?.isSending == true {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(12)
        .hostBoardGlassPanel(cornerRadius: 16, strokeOpacity: 0.12)
    }

    private func reminderStatRow(
        title: String,
        value: Int,
        systemImage: String,
        tint: Color,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .hostBoardGlassChip(cornerRadius: 14, isSelected: false, strokeOpacity: 0.10)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(value)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(value == 0 ? TryzubColors.mutedText : TryzubColors.primaryText)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TryzubColors.primaryText)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(TryzubColors.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .hostBoardGlassSurface(cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }

    private func reminderInfoRow(title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TryzubColors.mutedText)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TryzubColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
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
                    message: "\(failed) \(failed == 1 ? "reminder needs" : "reminders need") attention.",
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
