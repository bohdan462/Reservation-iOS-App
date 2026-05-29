//
//  AppNoticeOverlay.swift
//  Tryzub Reservations
//

import SwiftUI

struct AppNoticeOverlay: View {
    let notices: [AppNotice]
    let onDismiss: (AppNotice) -> Void
    let onClearAll: () -> Void

    @State private var showingDetails = false

    var body: some View {
        if let notice = notices.first {
            Button {
                showingDetails = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: notice.severity.symbolName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(notice.severity.tint)

                    Text(notice.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if notices.count > 1 {
                        Text("+\(notices.count - 1)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        onDismiss(notice)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss notice")
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .task(id: notice.id) {
                switch notice.severity {
                case .success, .info:
                    try? await Task.sleep(for: .seconds(3))
                case .warning, .error:
                    try? await Task.sleep(for: .seconds(5))
                }

                if notices.contains(notice) {
                    onDismiss(notice)
                }
            }
            .sheet(isPresented: $showingDetails) {
                AppNoticeListView(
                    notices: notices,
                    onDismiss: onDismiss,
                    onClearAll: onClearAll
                )
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.18), value: notices)
        }
    }
}

private struct AppNoticeListView: View {
    let notices: [AppNotice]
    let onDismiss: (AppNotice) -> Void
    let onClearAll: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if notices.isEmpty {
                    ContentUnavailableView(
                        "No Notices",
                        systemImage: "checkmark.circle",
                        description: Text("The app has no current warnings.")
                    )
                } else {
                    ForEach(notices) { notice in
                        NoticeDetailRow(notice: notice) {
                            onDismiss(notice)
                        }
                    }
                }
            }
            .navigationTitle("Notices")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") {
                        onClearAll()
                        dismiss()
                    }
                    .disabled(notices.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct NoticeDetailRow: View {
    let notice: AppNotice
    let onDismiss: (() -> Void)?

    init(notice: AppNotice, onDismiss: (() -> Void)? = nil) {
        self.notice = notice
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: notice.severity.symbolName)
                    .foregroundStyle(notice.severity.tint)
                Text(notice.title)
                    .font(.headline.weight(.medium))
                Spacer()
                Text(notice.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = notice.message, !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let developerDiagnostics = notice.developerDiagnostics, !developerDiagnostics.isEmpty {
                Text(developerDiagnostics)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Label(notice.source.rawValue, systemImage: "scope")
                if let requestReason = notice.requestReason {
                    Label(requestReason.rawValue, systemImage: "arrow.left.arrow.right")
                }
                if let errorCode = notice.errorCode {
                    Label(errorCode, systemImage: "number")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let onDismiss {
                Button("Dismiss", action: onDismiss)
                    .font(.caption.weight(.medium))
            }
        }
        .padding(.vertical, 4)
    }
}
