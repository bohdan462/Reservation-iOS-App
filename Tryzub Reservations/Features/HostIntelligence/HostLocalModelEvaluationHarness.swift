//
//  HostLocalModelEvaluationHarness.swift
//  Tryzub Reservations
//
//  In-memory local model evaluation for developer diagnostics only.
//

import Foundation

struct HostLocalModelEvaluationRun: Identifiable, Equatable {
  let id: UUID
  let label: String
  let packetFactCount: Int
  let serviceState: HostServiceState
  let pressureScore: Double
  let source: HostBriefingWriterSource
  let validationPassed: Bool
  let fallbackOccurred: Bool
  let failureReason: String?
  let semanticFailureReason: String?
  let promptTokenCount: Int?
  let outputCharacterCount: Int
  let duration: TimeInterval
  let candidatePreview: String?
  let repairedOutput: String?
  let acceptedOutput: String?
  let initialDecodeCode: Int32?
  let generationDecodeCode: Int32?
}

struct HostLocalModelEvaluationSummary: Equatable {
  let totalRuns: Int
  let passedRuns: Int
  let fallbackRuns: Int
  let semanticFailureRuns: Int
  let averageDuration: TimeInterval
  let mostCommonFailureReasons: [String]

  static func build(from runs: [HostLocalModelEvaluationRun]) -> HostLocalModelEvaluationSummary {
    guard !runs.isEmpty else {
      return HostLocalModelEvaluationSummary(
        totalRuns: 0,
        passedRuns: 0,
        fallbackRuns: 0,
        semanticFailureRuns: 0,
        averageDuration: 0,
        mostCommonFailureReasons: []
      )
    }

    let passed = runs.filter(\.validationPassed).count
    let fallback = runs.filter(\.fallbackOccurred).count
    let semantic = runs.filter { $0.semanticFailureReason != nil }.count
    let average = runs.map(\.duration).reduce(0, +) / Double(runs.count)

    let reasonCounts = runs
      .compactMap { $0.failureReason ?? $0.semanticFailureReason }
      .reduce(into: [String: Int]()) { counts, reason in
        counts[reason, default: 0] += 1
      }
    let commonReasons = reasonCounts
      .sorted {
        if $0.value == $1.value {
          return $0.key < $1.key
        }
        return $0.value > $1.value
      }
      .prefix(3)
      .map(\.key)

    return HostLocalModelEvaluationSummary(
      totalRuns: runs.count,
      passedRuns: passed,
      fallbackRuns: fallback,
      semanticFailureRuns: semantic,
      averageDuration: average,
      mostCommonFailureReasons: commonReasons
    )
  }
}

enum HostLocalModelEvaluationHarness {
  static func runOnce(
    label: String,
    packet: HostLLMPacket,
    fallbackText: String,
    settings: HostIntelligenceSettings
  ) async -> HostLocalModelEvaluationRun {
    let writer = LocalModelHostBriefingWriter()
    let clock = ContinuousClock()
    let start = clock.now

    let writerResult = await writer.writeBriefing(
      packet: packet,
      fallbackText: fallbackText
    )
    let duration = HostLocalModelEvaluationDuration.seconds(since: start, on: clock)

    let validation = HostBriefingWriterValidator.validationResult(
      writerResult.text,
      packet: packet,
      fallbackText: fallbackText
    )
    let runtimeDiagnostics = HostLlamaBriefingRuntimeDiagnostics.lastRun
    let writerDiagnostics = HostBriefingWriterDiagnostics.self
    let fallbackOccurred = writerResult.source == .failedFallback

    let acceptedOutput: String? = validation.isValid && writerResult.source == .localModel
      ? writerResult.text
      : nil

    return HostLocalModelEvaluationRun(
      id: UUID(),
      label: label,
      packetFactCount: packet.topFacts.count,
      serviceState: packet.serviceState,
      pressureScore: packet.pressureScore,
      source: writerResult.source,
      validationPassed: validation.isValid,
      fallbackOccurred: fallbackOccurred,
      failureReason: writerResult.failedReason ?? validation.reason,
      semanticFailureReason: writerDiagnostics.lastSemanticValidationFailureReason,
      promptTokenCount: runtimeDiagnostics.promptTokenCount > 0
        ? runtimeDiagnostics.promptTokenCount
        : nil,
      outputCharacterCount: writerResult.text.count,
      duration: duration,
      candidatePreview: writerDiagnostics.lastGeneratedCandidate,
      repairedOutput: writerDiagnostics.lastRepairedOutput,
      acceptedOutput: acceptedOutput,
      initialDecodeCode: runtimeDiagnostics.initialDecodeCode,
      generationDecodeCode: runtimeDiagnostics.generationDecodeCode
    )
  }

  static func runSequential(
    count: Int,
    label: String,
    packet: HostLLMPacket,
    fallbackText: String,
    settings: HostIntelligenceSettings,
    onProgress: (@Sendable (Int, Int) -> Void)? = nil
  ) async -> [HostLocalModelEvaluationRun] {
    var runs: [HostLocalModelEvaluationRun] = []
    runs.reserveCapacity(count)

    for index in 1...count {
      onProgress?(index, count)
      let run = await runOnce(
        label: "\(label) #\(index)",
        packet: packet,
        fallbackText: fallbackText,
        settings: settings
      )
      runs.append(run)
    }

    return runs
  }
}

private enum HostLocalModelEvaluationDuration {
  static func seconds(since mark: ContinuousClock.Instant, on clock: ContinuousClock) -> TimeInterval {
    let duration = mark.duration(to: clock.now)
    return Double(duration.components.seconds)
      + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
  }

  static func format(_ seconds: TimeInterval) -> String {
    if seconds < 0.01 {
      return String(format: "%.0f ms", seconds * 1000)
    }
    return String(format: "%.2f s", seconds)
  }
}
