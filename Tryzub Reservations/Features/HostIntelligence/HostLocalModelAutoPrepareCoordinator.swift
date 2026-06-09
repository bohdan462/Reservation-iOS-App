//
//  HostLocalModelAutoPrepareCoordinator.swift
//  Tryzub Reservations
//
//  One-time bundled model copy into Application Support after a safe post-launch delay.
//  File copy only — never loads llama runtime or generates briefings.
//

import Combine
import Foundation

@MainActor
final class HostLocalModelAutoPrepareCoordinator: ObservableObject {
  static let shared = HostLocalModelAutoPrepareCoordinator()

  @Published private(set) var phase: HostOnDeviceSupportPhase = .idle
  @Published private(set) var technicalFailureDetail: String?

  private let completedDefaultsKey = "tryzub.hostLocalModel.autoPrepare.completed.v1"
  private let stabilizationDelay: TimeInterval = 25
  private let guardPollInterval: TimeInterval = 2
  private let maxGuardPollAttempts = 90
  private let readyDisplayDuration: TimeInterval = 8

  private var prepareTask: Task<Void, Never>?
  private weak var reservationsController: ReservationsController?

  private init() {
    reconcileCompletionFromInstalledModel()
  }

  var isPrepareInFlight: Bool {
    prepareTask != nil
      || phase == .waitingForSafeMoment
      || phase.isPreparing
  }

  var hasCompletedAutoPrepare: Bool {
    UserDefaults.standard.bool(forKey: completedDefaultsKey)
  }

  func scheduleWhenReady(controller: ReservationsController) {
    reservationsController = controller
    reconcileCompletionFromInstalledModel()

    guard shouldAttemptAutoPrepare else {
      if phase != .idle, !phase.showsMoreSection {
        phase = .idle
      }
      return
    }

    guard prepareTask == nil else { return }

    prepareTask = Task { @MainActor in
      defer { self.prepareTask = nil }
      await self.runAutoPrepareIfNeeded()
    }
  }

  func markCompleted() {
    UserDefaults.standard.set(true, forKey: completedDefaultsKey)
  }

  func cancelInFlightWork() {
    prepareTask?.cancel()
    prepareTask = nil
    switch phase {
    case .waitingForSafeMoment, .preparing:
      phase = .idle
    default:
      break
    }
  }

  // MARK: - Private

  private var shouldAttemptAutoPrepare: Bool {
    guard HostLocalModelFileLocator.bundledModelURL() != nil else { return false }
    guard HostLocalModelFileLocator.applicationSupportModelURL() == nil else { return false }
    guard !hasCompletedAutoPrepare else { return false }
    return true
  }

  private func reconcileCompletionFromInstalledModel() {
    if HostLocalModelFileLocator.applicationSupportModelURL() != nil {
      markCompleted()
      if case .preparing = phase { return }
      if case .waitingForSafeMoment = phase { return }
      if phase != .ready {
        phase = .idle
      }
    }
  }

  private func runAutoPrepareIfNeeded() async {
    guard shouldAttemptAutoPrepare else { return }
    guard let controller = reservationsController else { return }

    technicalFailureDetail = nil
    phase = .waitingForSafeMoment
    HostIntelligenceDiagnostics.skipLocalModel(reason: "on_device_support_waiting")

    if let releasedAt = controller.startupUIReleasedAt {
      let remaining = stabilizationDelay - Date().timeIntervalSince(releasedAt)
      if remaining > 0 {
        try? await Task.sleep(for: .seconds(remaining))
      }
    } else {
      try? await Task.sleep(for: .seconds(stabilizationDelay))
    }

    guard !Task.isCancelled else { return }

    for _ in 0..<maxGuardPollAttempts {
      guard !Task.isCancelled else { return }
      if canStartAutoPrepareNow(controller: controller) {
        break
      }
      try? await Task.sleep(for: .seconds(guardPollInterval))
    }

    guard canStartAutoPrepareNow(controller: controller) else {
      HostIntelligenceDiagnostics.skipLocalModel(reason: "on_device_support_guards_blocked")
      phase = .idle
      return
    }

    guard HostLocalModelFileLocator.applicationSupportModelURL() == nil else {
      markCompleted()
      phase = .idle
      return
    }

    phase = .preparing(progress: nil)
    HostIntelligenceDiagnostics.skipLocalModel(reason: "on_device_support_copy_started")

    do {
      _ = try await HostLocalModelInstaller.installBundledModel { [weak self] progress in
        Task { @MainActor in
          self?.phase = .preparing(progress: progress)
          #if DEBUG
          let percent = Int((progress * 100).rounded())
          print("[HOST_AI] on_device_support auto_prepare progress=\(percent)%")
          #endif
        }
      }
      markCompleted()
      phase = .ready
      #if DEBUG
      print("[HOST_AI] on_device_support auto_prepare completed")
      #endif
      try? await Task.sleep(for: .seconds(readyDisplayDuration))
      if case .ready = phase {
        phase = .idle
      }
    } catch {
      let staffMessage =
        "On-device support could not be prepared. Core reservation tools still work."
      technicalFailureDetail = error.localizedDescription
      phase = .failed(staffMessage: staffMessage)
      #if DEBUG
      print("[HOST_AI] on_device_support auto_prepare failed reason=\(error.localizedDescription)")
      #endif
    }
  }

  private func canStartAutoPrepareNow(controller: ReservationsController) -> Bool {
    guard controller.hasReleasedStartupUI else { return false }
    guard !controller.isStartupNetworkPassInFlight else { return false }
    guard !controller.isHistoryPrefetching else { return false }
    guard !HostLocalModelInferenceTracker.isActive else { return false }
    guard !HostLocalModelDiagnosticsCoordinator.shared.isManualOperationInFlight else { return false }

    if let releasedAt = controller.startupUIReleasedAt {
      guard Date().timeIntervalSince(releasedAt) >= stabilizationDelay else { return false }
    } else {
      return false
    }

    if let dateKey = controller.hostBoardSelectedDateKey,
       controller.isHostBoardDateNetworkBusy(dateKey) {
      return false
    }

    return true
  }
}

private extension HostOnDeviceSupportPhase {
  var isPreparing: Bool {
    if case .preparing = self { return true }
    return false
  }
}
