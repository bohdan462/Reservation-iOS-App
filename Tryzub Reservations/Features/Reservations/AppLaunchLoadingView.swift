//
//  AppLaunchLoadingView.swift
//  Tryzub Reservations
//

import SwiftUI

struct AppLaunchLoadingView: View {
    @State private var messageIndex = 0
    @State private var messageTask: Task<Void, Never>?

    private let messages = [
        "Connecting to API…",
        "Setting up…",
        "Organizing today's service board…"
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    Color(.secondarySystemGroupedBackground).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 28) {
                    Text("Tryzub")
                        .font(.caption.weight(.semibold))
                        .tracking(3.2)
                        .textCase(.uppercase)
                        .foregroundStyle(TryzubColors.mutedText)

                    LaunchOrbitalLoader()

                    Text(messages[messageIndex])
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 22)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.45), value: messageIndex)
                        .padding(.horizontal, 28)
                }

                Spacer()

                LaunchStepIndicator(activeIndex: min(messageIndex, messages.count - 1), total: messages.count)
                    .padding(.bottom, 44)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading")
        .accessibilityValue(messages[messageIndex])
        .onAppear {
            startMessageRotation()
        }
        .onDisappear {
            messageTask?.cancel()
            messageTask = nil
        }
    }

    private func startMessageRotation() {
        messageTask?.cancel()
        messageTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    messageIndex = (messageIndex + 1) % messages.count
                }
            }
        }
    }
}

private struct LaunchOrbitalLoader: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let phase = time * 0.85 + Double(index) * (2 * .pi / 3)
                    let wobble = sin(time * 1.15 + Double(index) * 0.8) * 5
                    let radius = 30 + wobble

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.20, green: 0.48, blue: 0.30).opacity(0.95 - Double(index) * 0.18),
                                    Color(red: 0.20, green: 0.48, blue: 0.30).opacity(0.25)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 8
                            )
                        )
                        .frame(width: 11, height: 11)
                        .offset(
                            x: cos(phase) * radius,
                            y: sin(phase) * (radius * 0.68)
                        )
                }

                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    .frame(width: 74, height: 52)

                Circle()
                    .fill(Color(red: 0.20, green: 0.48, blue: 0.30).opacity(0.10 + sin(time * 1.6) * 0.04))
                    .frame(
                        width: 18 + sin(time * 1.6) * 4,
                        height: 18 + sin(time * 1.6) * 4
                    )
            }
            .frame(width: 96, height: 72)
        }
    }
}

private struct LaunchStepIndicator: View {
    let activeIndex: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= activeIndex ? Color(red: 0.20, green: 0.48, blue: 0.30).opacity(0.75) : Color.primary.opacity(0.10))
                    .frame(width: index == activeIndex ? 18 : 6, height: 4)
                    .animation(.easeInOut(duration: 0.35), value: activeIndex)
            }
        }
        .accessibilityHidden(true)
    }
}
