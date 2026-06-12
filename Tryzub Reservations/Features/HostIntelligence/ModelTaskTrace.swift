//
//  ModelTaskTrace.swift
//  Tryzub Reservations
//
//  Phase 10 — LLM task configuration.
//
//  DEBUG-only structured traces for per-task model usage. Lets us prove which task ran,
//  whether it produced model output, was blocked by a validator, or fell back to template.
//  No prompts, no raw output, no PII — task name + status token + short reason only.
//

import Foundation
import OSLog

enum ModelTaskTrace {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "ModelTask"
    )

    /// The model tasks the app runs. Mirrors `HostLocalModelTaskProfile`.
    enum Task: String {
        case hostBriefing
        case guestMessageDraft
        case noteAnalysis
    }

    static func started(task: Task) {
        guard isEnabled else { return }
        logger.debug("[MODEL_TASK_TRACE] task=\(task.rawValue, privacy: .public) status=started")
    }

    static func completed(task: Task, detail: String? = nil) {
        guard isEnabled else { return }
        logger.debug(
            "[MODEL_TASK_TRACE] task=\(task.rawValue, privacy: .public) status=completed detail=\(detail ?? "-", privacy: .public)"
        )
    }

    static func blocked(task: Task, reason: String) {
        guard isEnabled else { return }
        logger.debug(
            "[MODEL_TASK_TRACE] task=\(task.rawValue, privacy: .public) status=blocked reason=\(reason, privacy: .public)"
        )
    }

    static func fallback(task: Task, reason: String) {
        guard isEnabled else { return }
        logger.debug(
            "[MODEL_TASK_TRACE] task=\(task.rawValue, privacy: .public) status=fallback reason=\(reason, privacy: .public)"
        )
    }
}
