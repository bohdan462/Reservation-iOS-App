//
//  StartupCacheLoadingView.swift
//  Tryzub Reservations
//
//  Entrance loading screen when the app is not ready to show cached UI.
//

import SwiftUI

struct StartupCacheLoadingView: View {
    let presentation: StartupProgressPresentation
    let showsFailure: Bool
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsDelayedMessage = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            StartupLoadingBackdrop()

            VStack(spacing: 22) {
                Spacer()

                VStack(spacing: 14) {
                    ZStack {
                        if !reduceMotion, !showsFailure {
                            Circle()
                                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                                .frame(width: 54, height: 54)
                                .scaleEffect(pulse ? 1.18 : 0.92)
                                .opacity(pulse ? 0 : 0.55)
                        }

                        if showsFailure {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            HostPulseIcon(isActive: true, size: 14)
                        }
                    }
                    .frame(height: 56)

                    VStack(spacing: 6) {
                        Text("Tryzub")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.9))

                        Text(presentation.headline)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if let subtitle = presentation.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .startupGlassCard()

                if !showsFailure {
                    startupStepList
                }

                if showsFailure {
                    Text(StartupProgressPresenter.staffNoCacheFailureMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Button("Try again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                } else {
                    TryzubSubtleLoadingDot(diameter: 8)

                    if showsDelayedMessage {
                        Text("Still connecting…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion, !showsFailure else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .task {
            guard !showsFailure else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            showsDelayedMessage = true
        }
    }

    @ViewBuilder
    private var startupStepList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleSteps, id: \.self) { step in
                HStack(spacing: 10) {
                    stepIcon(for: step)
                    Text(step.title)
                        .font(.caption.weight(stepStatus(for: step) == .active ? .semibold : .medium))
                        .foregroundStyle(stepForeground(for: step))
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 360)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var visibleSteps: [StartupProgressStep] {
        [.checkingSavedData, .checkingService, .loadingTodayOperations]
    }

    private func stepStatus(for step: StartupProgressStep) -> StartupProgressStepStatus {
        presentation.stepStatus[step] ?? (step < presentation.activeStep ? .done : .pending)
    }

    @ViewBuilder
    private func stepIcon(for step: StartupProgressStep) -> some View {
        switch stepStatus(for: step) {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(TryzubColors.success)
        case .active:
            TryzubSubtleLoadingDot(diameter: 7)
        case .pending:
            Image(systemName: step.systemImage)
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
    }

    private func stepForeground(for step: StartupProgressStep) -> Color {
        switch stepStatus(for: step) {
        case .done:
            return .secondary
        case .active:
            return .primary.opacity(0.86)
        case .pending:
            return Color.secondary.opacity(0.55)
        }
    }
}

private struct StartupLoadingBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    Color(.systemGroupedBackground).opacity(0.92),
                    Color.accentColor.opacity(0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(y: -180)
        }
        .ignoresSafeArea()
    }
}

private extension View {
    @ViewBuilder
    func startupGlassCard() -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}
