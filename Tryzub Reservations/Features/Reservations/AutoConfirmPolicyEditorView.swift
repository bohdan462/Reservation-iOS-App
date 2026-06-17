//
//  AutoConfirmPolicyEditorView.swift
//  Tryzub Reservations
//
//  Manager-facing backend auto-confirm policy editor (PATCH /restaurant-setup only).
//

import SwiftUI

private enum AutoConfirmRuleFocusedField: Hashable {
    case startTime
    case endTime
}

// MARK: - Editor

struct AutoConfirmPolicyEditorView: View {
    @ObservedObject var settingsStore: RestaurantSettingsStore
    @ObservedObject var controller: ReservationsController

    let initialSetup: RestaurantSetup
    var onSaved: (RestaurantSetup) -> Void = { _ in }

    @State private var draft: AutoConfirmPolicyEditorDraft
    @State private var validationMessages: [String] = []
    @State private var isSaving = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

    @State private var showEnableAutoConfirmDialog = false
    @State private var showHighRiskSaveDialog = false
    @State private var pendingSaveAfterHighRisk = false

    @State private var editingRule: AutoConfirmRuleDraft?
    @State private var isAddingRule = false

    @State private var excludedDateToAdd = Date()

    init(
        setup: RestaurantSetup,
        settingsStore: RestaurantSettingsStore,
        controller: ReservationsController,
        onSaved: @escaping (RestaurantSetup) -> Void = { _ in }
    ) {
        self.initialSetup = setup
        self.settingsStore = settingsStore
        self.controller = controller
        self.onSaved = onSaved
        _draft = State(initialValue: AutoConfirmPolicyEditorDraft(setup: setup))
    }

    private var canSave: Bool {
        !isSaving && validationMessages.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let errorMessage {
                    editorNotice(message: errorMessage, tint: .red)
                } else if let successMessage {
                    editorNotice(message: successMessage, tint: .green, systemImage: "checkmark.circle")
                }

                safetyHeaderCard
                masterToggleCard
                guardTogglesCard
                rulesCard
                excludedDatesCard
                dryRunCard

                if !validationMessages.isEmpty {
                    editorNotice(
                        message: validationMessages.joined(separator: "\n"),
                        tint: .orange,
                        systemImage: "exclamationmark.triangle"
                    )
                }

                saveButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Auto-Confirm Rules")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft) { _, _ in
            refreshValidation()
        }
        .onAppear {
            refreshValidation()
        }
        .confirmationDialog(
            "Auto-confirm can send confirmation emails and confirm eligible website reservations automatically after import. Continue?",
            isPresented: $showEnableAutoConfirmDialog,
            titleVisibility: .visible
        ) {
            Button("Turn On Auto-Confirm", role: .destructive) {
                draft.autoConfirmEnabled = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "This rule may auto-confirm higher-risk reservations. Continue?",
            isPresented: $showHighRiskSaveDialog,
            titleVisibility: .visible
        ) {
            Button("Save Anyway", role: .destructive) {
                pendingSaveAfterHighRisk = true
                Task { await performSave() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $editingRule) { rule in
            let originalRuleID = rule.id
            AutoConfirmRuleEditorSheet(
                draft: rule.repairedForEditing(),
                isNew: false,
                showRepairWarning: !rule.isValidRule,
                existingRuleIDs: draft.rules.map(\.id).filter { $0 != rule.id },
                onCancel: { editingRule = nil },
                onSave: { updated in
                    draft.replaceRule(replacingID: originalRuleID, with: updated)
                    #if DEBUG
                    print(
                        "[AutoConfirmRuleEdit] savedDraft id=\(updated.id) valid=\(updated.isValidRule) start=\(updated.startTime) end=\(updated.endTime) party=\(updated.maxPartySize)"
                    )
                    #endif
                    editingRule = nil
                }
            )
        }
        .sheet(isPresented: $isAddingRule) {
            AutoConfirmRuleEditorSheet(
                draft: .newRule(),
                isNew: true,
                existingRuleIDs: draft.rules.map(\.id),
                onCancel: { isAddingRule = false },
                onSave: { newRule in
                    draft.rules.append(newRule)
                    isAddingRule = false
                }
            )
        }
    }

    // MARK: - Sections

    private var safetyHeaderCard: some View {
        editorCard(title: "Backend Auto-Confirm", systemImage: "checkmark.seal") {
        }
    }

    private var masterToggleCard: some View {
        editorCard(title: "Master Toggle", systemImage: "power") {
            Toggle(
                "Auto-confirm enabled",
                isOn: Binding(
                    get: { draft.autoConfirmEnabled },
                    set: { newValue in
                        if newValue, !draft.autoConfirmEnabled {
                            showEnableAutoConfirmDialog = true
                        } else {
                            draft.autoConfirmEnabled = newValue
                        }
                    }
                )
            )
            .font(.subheadline.weight(.medium))

            if draft.autoConfirmEnabled, draft.enabledValidRuleCount == 0 {
                Text("Add at least one enabled valid time window before turning auto-confirm on.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var guardTogglesCard: some View {
        editorCard(title: "Safety", systemImage: "shield") {
            Toggle("Require guest email", isOn: $draft.autoConfirmRequireEmail)
            Toggle("Block guest notes", isOn: $draft.autoConfirmBlockGuestNotes)
            Toggle("Block duplicates/corrections", isOn: $draft.autoConfirmBlockDuplicates)
            Toggle("Block suspicious contact info", isOn: $draft.autoConfirmBlockSuspicious)
        }
    }

    private var rulesCard: some View {
        editorCard(title: "Auto-confirm windows", systemImage: "clock") {
            if draft.invalidRuleCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(draft.invalidRuleCount) imported window(s) need repair.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Imported invalid windows are disabled until repaired.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        removeInvalidWindows()
                    } label: {
                        Label("Remove Invalid Windows", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                }
            }

            if draft.rules.isEmpty {
                Text("No windows yet. Add a time window to allow backend auto-confirm.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.rules) { rule in
                    AutoConfirmRuleRow(
                        rule: rule,
                        onEdit: { editingRule = rule },
                        onRepair: { repairRule(rule) },
                        onDelete: { draft.rules.removeAll { $0.id == rule.id } },
                        onToggleEnabled: {
                            guard let index = draft.rules.firstIndex(where: { $0.id == rule.id }) else { return }
                            draft.rules[index].enabled.toggle()
                        }
                    )
                }
            }

            Button {
                isAddingRule = true
            } label: {
                Label("Add Time Window", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private func repairRule(_ rule: AutoConfirmRuleDraft) {
        let originalID = rule.id
        var repaired = rule.repairedForEditing()
        repaired.enabled = true
        draft.replaceRule(replacingID: originalID, with: repaired)
        #if DEBUG
        print(
            "[AutoConfirmRuleRepair] id=\(repaired.id) weekday=\(repaired.weekday) start=\(repaired.startTime) end=\(repaired.endTime) party=\(repaired.maxPartySize) enabled=\(repaired.enabled)"
        )
        #endif
    }

    private func removeInvalidWindows() {
        let removedCount = draft.invalidRuleCount
        draft.rules.removeAll { !$0.isValidRule }
        #if DEBUG
        print("[AutoConfirmInvalidCleanup] removed=\(removedCount) remaining=\(draft.rules.count)")
        #endif
    }

    private var excludedDatesCard: some View {
        editorCard(title: "Excluded Dates", systemImage: "calendar.badge.minus") {
            Text("Excluded dates block auto-confirm even when a time window matches.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if draft.excludedDates.isEmpty {
                Text("No excluded dates.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.excludedDates, id: \.self) { dateKey in
                    HStack {
                        Text(dateKey)
                            .font(.subheadline.monospacedDigit())
                        Spacer()
                        Button(role: .destructive) {
                            draft.excludedDates.removeAll { $0 == dateKey }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            DatePicker("Add excluded date", selection: $excludedDateToAdd, displayedComponents: .date)

            Button {
                let key = excludedDateToAdd.reservationDateString()
                guard !draft.excludedDates.contains(key) else { return }
                draft.excludedDates.append(key)
                draft.excludedDates.sort()
            } label: {
                Label("Add Date", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
    }

    private var dryRunCard: some View {
        editorCard(title: "Preview", systemImage: "eye") {
            AutoConfirmDryRunPreviewSection(apiClient: controller.environment.apiClient)

            Text("Preview only. This does not send email or confirm reservations.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var saveButton: some View {
        Button {
            Task { await saveTapped() }
        } label: {
            HStack {
                Spacer()
                if isSaving {
                    ProgressView()
                        .padding(.trailing, 6)
                }
                Text(isSaving ? "Saving…" : "Save Auto-Confirm Policy")
                    .font(.headline)
                Spacer()
            }
            .padding(.vertical, 14)
            .background(canSave ? Color.accentColor : Color.gray.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!canSave || isSaving)
    }

    // MARK: - Actions

    private func refreshValidation() {
        validationMessages = draft.validationMessages()
    }

    @MainActor
    private func saveTapped() async {
        refreshValidation()
        guard validationMessages.isEmpty else { return }

        if draft.hasHighRiskRules, !pendingSaveAfterHighRisk {
            showHighRiskSaveDialog = true
            return
        }

        await performSave()
    }

    @MainActor
    private func performSave() async {
        refreshValidation()
        guard validationMessages.isEmpty else {
            pendingSaveAfterHighRisk = false
            return
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer {
            isSaving = false
            pendingSaveAfterHighRisk = false
        }

        do {
            let buildResult = try draft.buildPolicyForSave()
            let request = RestaurantSetupUpdateRequest(
                autoConfirmEnabled: draft.autoConfirmEnabled,
                autoConfirmRequireEmail: draft.autoConfirmRequireEmail,
                autoConfirmBlockGuestNotes: draft.autoConfirmBlockGuestNotes,
                autoConfirmBlockDuplicates: draft.autoConfirmBlockDuplicates,
                autoConfirmBlockSuspicious: draft.autoConfirmBlockSuspicious,
                autoConfirmPolicy: buildResult.policy
            )

            #if DEBUG
            print(
                "[AutoConfirmSave] before rules=\(draft.rules.count) valid=\(draft.rules.filter(\.isValidRule).count) invalid=\(draft.invalidRuleCount) enabledValid=\(draft.enabledValidRuleCount) autoConfirmEnabled=\(draft.autoConfirmEnabled)"
            )
            #endif

            let saved = try await settingsStore.saveRestaurantAutomationSetup(request: request)

            let sentSignature = policySignature(buildResult.policy)
            let savedSignature = policySignature(saved.autoConfirmPolicy)
            let responseMatchesSent = sentSignature == savedSignature

            #if DEBUG
            if responseMatchesSent {
                let patchEnabledRules = saved.autoConfirmPolicy.rules.filter(\.enabled).count
                print(
                    "[AutoConfirmSave] patchSaved rules=\(saved.autoConfirmPolicy.rules.count) enabled=\(patchEnabledRules) sentRules=\(buildResult.policy.rules.count)"
                )
            } else {
                print(
                    "[AUTO_CONFIRM_SAVE_MISMATCH] sentRules=\(buildResult.policy.rules.count) savedRules=\(saved.autoConfirmPolicy.rules.count) sent=\(sentSignature) saved=\(savedSignature)"
                )
            }
            #endif

            controller.adoptRestaurantSetup(saved, reason: "auto_confirm_policy_saved")

            draft = AutoConfirmPolicyEditorDraft(setup: saved)
            if responseMatchesSent {
                draft.rules = buildResult.policy.rules.map(AutoConfirmRuleDraft.init(rule:))
            }
            onSaved(saved)
            if !responseMatchesSent {
                successMessage = "Saved, but the server returned a different auto-confirm policy. Review the list."
            } else if buildResult.removedInvalidRuleCount > 0 {
                successMessage = "Invalid auto-confirm windows were removed from the saved policy."
            } else {
                successMessage = "Auto-confirm policy saved."
            }
            ReservationHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            ReservationHaptics.warning()
        }
    }

    @ViewBuilder
    private func editorCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func editorNotice(
        message: String,
        tint: Color,
        systemImage: String = "info.circle"
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Policy save signatures

private func policySignature(_ policy: AutoConfirmPolicy) -> [String] {
    var signatures = policy.rules
        .map { rule in
            "\(rule.id)|\(rule.enabled)|\(rule.weekday)|\(rule.startTime)|\(rule.endTime)|\(rule.maxPartySize)"
        }
        .sorted()
    signatures.append("excluded_dates=" + policy.excludedDates.sorted().joined(separator: ","))
    return signatures
}

// MARK: - Draft

struct AutoConfirmPolicyBuildResult: Equatable {
    let policy: AutoConfirmPolicy
    let removedInvalidRuleCount: Int
}

struct AutoConfirmPolicyEditorDraft: Equatable {
    var autoConfirmEnabled: Bool
    var autoConfirmRequireEmail: Bool
    var autoConfirmBlockGuestNotes: Bool
    var autoConfirmBlockDuplicates: Bool
    var autoConfirmBlockSuspicious: Bool
    var rules: [AutoConfirmRuleDraft]
    var excludedDates: [String]

    var enabledRuleCount: Int {
        rules.filter(\.enabled).count
    }

    var enabledValidRuleCount: Int {
        rules.filter { $0.enabled && $0.isValidRule }.count
    }

    var invalidRuleCount: Int {
        rules.filter { !$0.isValidRule }.count
    }

    var hasHighRiskRules: Bool {
        rules.contains { rule in
            rule.enabled && rule.isValidRule && (rule.weekday == 4 || rule.weekday == 5 || rule.maxPartySize >= 8)
        }
    }

    init(setup: RestaurantSetup) {
        autoConfirmEnabled = setup.autoConfirmEnabled
        autoConfirmRequireEmail = setup.autoConfirmRequireEmail
        autoConfirmBlockGuestNotes = setup.autoConfirmBlockGuestNotes
        autoConfirmBlockDuplicates = setup.autoConfirmBlockDuplicates
        autoConfirmBlockSuspicious = setup.autoConfirmBlockSuspicious
        rules = setup.autoConfirmPolicy.rules.map { rule in
            var draft = AutoConfirmRuleDraft(rule: rule)
            if !draft.isValidRule {
                draft.enabled = false
            }
            return draft
        }
        excludedDates = setup.autoConfirmPolicy.excludedDates.sorted()

        #if DEBUG
        let invalidLoaded = rules.filter { !$0.isValidRule }.count
        let disabledInvalid = rules.filter { !$0.isValidRule && !$0.enabled }.count
        if invalidLoaded > 0 {
            print("[AutoConfirmImportRepair] invalidLoaded=\(invalidLoaded) disabledInvalid=\(disabledInvalid)")
        }
        #endif
    }

    func validationMessages() -> [String] {
        var messages: [String] = []

        if autoConfirmEnabled {
            if enabledValidRuleCount == 0 {
                messages.append("Add at least one enabled valid time window before turning auto-confirm on.")
            }

            if rules.contains(where: { $0.enabled && !$0.isValidRule }) {
                messages.append("Repair or delete invalid windows before turning auto-confirm on.")
            }
        }

        let excludedMessages = AutoConfirmPolicyValidation.validate(
            policy: AutoConfirmPolicy(rules: [], excludedDates: excludedDates)
        )
        messages.append(contentsOf: excludedMessages)

        return messages
    }

    func buildPolicyForSave() throws -> AutoConfirmPolicyBuildResult {
        if autoConfirmEnabled, enabledValidRuleCount == 0 {
            throw AutoConfirmEditorError(
                message: "Add at least one enabled valid time window before turning auto-confirm on."
            )
        }

        var validRules: [AutoConfirmRule] = []
        var removedInvalidRuleCount = 0

        for ruleDraft in rules {
            guard ruleDraft.isValidRule else {
                removedInvalidRuleCount += 1
                continue
            }
            validRules.append(try ruleDraft.toRule())
        }

        let excludedMessages = AutoConfirmPolicyValidation.validate(
            policy: AutoConfirmPolicy(rules: [], excludedDates: excludedDates)
        )
        if let first = excludedMessages.first {
            throw AutoConfirmEditorError(message: first)
        }

        let validatedPolicy = try makeValidatedPolicy(rules: validRules)

        return AutoConfirmPolicyBuildResult(
            policy: validatedPolicy,
            removedInvalidRuleCount: removedInvalidRuleCount
        )
    }

    /// Replaces an edited rule in the draft, including invalid imported rows whose id may have changed during repair.
    mutating func replaceRule(replacingID originalID: String, with updated: AutoConfirmRuleDraft) {
        let trimmedOriginal = originalID.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedOriginal.isEmpty,
           let index = rules.firstIndex(where: {
               $0.id.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedOriginal
           }) {
            rules[index] = updated
            return
        }

        if trimmedOriginal.isEmpty,
           let index = rules.firstIndex(where: { !$0.isValidRule && $0.weekday == updated.weekday }) {
            rules[index] = updated
            return
        }

        if let index = rules.firstIndex(where: { $0.id == updated.id }) {
            rules[index] = updated
            return
        }

        rules.append(updated)
    }

    private func makeValidatedPolicy(rules: [AutoConfirmRule]) throws -> AutoConfirmPolicy {
        let policy = AutoConfirmPolicy(rules: rules, excludedDates: excludedDates)
        let policyMessages = AutoConfirmPolicyValidation.validate(policy: policy)
        if let first = policyMessages.first {
            throw AutoConfirmEditorError(message: first)
        }
        return policy
    }
}

struct AutoConfirmRuleDraft: Identifiable, Equatable {
    var id: String
    var enabled: Bool
    var weekday: Int
    var startTime: String
    var endTime: String
    var maxPartySize: Int

    init(rule: AutoConfirmRule) {
        id = rule.id
        enabled = rule.enabled
        weekday = rule.weekday
        startTime = AutoConfirmTimeFormatting.shortDisplay(from: rule.startTime)
        endTime = AutoConfirmTimeFormatting.shortDisplay(from: rule.endTime)
        maxPartySize = rule.maxPartySize
    }

    init(
        id: String,
        enabled: Bool,
        weekday: Int,
        startTime: String,
        endTime: String,
        maxPartySize: Int
    ) {
        self.id = id
        self.enabled = enabled
        self.weekday = weekday
        self.startTime = startTime
        self.endTime = endTime
        self.maxPartySize = maxPartySize
    }

    static func newRule(weekday: Int = 1) -> AutoConfirmRuleDraft {
        let startStorage = "17:00:00"
        let endStorage = "18:00:00"
        return AutoConfirmRuleDraft(
            id: generateRuleID(weekday: weekday, start: startStorage, end: endStorage),
            enabled: true,
            weekday: weekday,
            startTime: "17:00",
            endTime: "18:00",
            maxPartySize: 4
        )
    }

    static func generateRuleID(weekday: Int, start: String, end: String) -> String {
        let short = UUID().uuidString.prefix(8).lowercased()
        let startPart = start.replacingOccurrences(of: ":", with: "_")
        let endPart = end.replacingOccurrences(of: ":", with: "_")
        return "auto_\(weekday)_\(startPart)_\(endPart)_\(short)"
    }

    func toRule() throws -> AutoConfirmRule {
        let normalizedStart = try AutoConfirmTimeFormatting.normalizedStorage(
            from: startTime,
            field: "\(AutoConfirmWeekdayFormatting.name(for: weekday)) window start time"
        )
        let normalizedEnd = try AutoConfirmTimeFormatting.normalizedStorage(
            from: endTime,
            field: "\(AutoConfirmWeekdayFormatting.name(for: weekday)) window end time"
        )
        return AutoConfirmRule(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines),
            enabled: enabled,
            weekday: weekday,
            startTime: normalizedStart,
            endTime: normalizedEnd,
            maxPartySize: maxPartySize
        )
    }

    var isValidRule: Bool {
        validationMessages.isEmpty
    }

    var validationMessages: [String] {
        var messages: [String] = []
        let label = "\(AutoConfirmWeekdayFormatting.name(for: weekday)) window"

        if !AutoConfirmPolicyValidation.validWeekdayRange.contains(weekday) {
            messages.append("\(label): Weekday must be 0–6.")
        }

        let trimmedStart = startTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnd = endTime.trimmingCharacters(in: .whitespacesAndNewlines)

        if !RestaurantAutomationTimeValidation.isValidTime(trimmedStart) {
            messages.append("\(label): Start time must use HH:mm or HH:mm:ss.")
        }

        if !RestaurantAutomationTimeValidation.isValidTime(trimmedEnd) {
            messages.append("\(label): End time must use HH:mm or HH:mm:ss.")
        }

        if !AutoConfirmPolicyValidation.validMaxPartySizeRange.contains(maxPartySize) {
            messages.append("\(label): Max party size must be between 1 and 20.")
        }

        if RestaurantAutomationTimeValidation.isValidTime(trimmedStart),
           RestaurantAutomationTimeValidation.isValidTime(trimmedEnd),
           let startMinutes = RestaurantAutomationTimeValidation.minutes(from: trimmedStart),
           let endMinutes = RestaurantAutomationTimeValidation.minutes(from: trimmedEnd),
           endMinutes <= startMinutes {
            messages.append("\(label): End time must be after start time.")
        }

        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedID.isEmpty {
            messages.append("\(label): Each auto-confirm window needs an id.")
        }

        return messages
    }

    var displayTitle: String {
        let weekdayName = AutoConfirmWeekdayFormatting.name(for: weekday)

        if !isValidRule {
            if !RestaurantAutomationTimeValidation.isValidTime(startTime.trimmingCharacters(in: .whitespacesAndNewlines))
                || !RestaurantAutomationTimeValidation.isValidTime(endTime.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return "\(weekdayName) · Needs time · tap Edit"
            }
            if !AutoConfirmPolicyValidation.validMaxPartySizeRange.contains(maxPartySize) {
                return "\(weekdayName) · Needs party size · tap Edit"
            }
            return "\(weekdayName) · Needs fix · tap Edit"
        }

        return "\(weekdayName) · \(AutoConfirmTimeFormatting.displayRange(start: startTime, end: endTime)) · up to \(maxPartySize) guests"
    }

    var rowTitle: String {
        displayTitle
    }

    var showsWeekendWarning: Bool {
        weekday == 4 || weekday == 5
    }

    var showsLargePartyWarning: Bool {
        maxPartySize >= 8
    }

    /// Returns a sheet-safe copy with editable defaults for invalid backend-loaded rules.
    /// Does not mutate the policy draft until the user saves from the sheet.
    func repairedForEditing() -> AutoConfirmRuleDraft {
        guard !isValidRule else { return self }

        var repaired = self

        if !AutoConfirmPolicyValidation.validWeekdayRange.contains(repaired.weekday) {
            repaired.weekday = 1
        }

        let trimmedStart = repaired.startTime.trimmingCharacters(in: .whitespacesAndNewlines)
        if !RestaurantAutomationTimeValidation.isValidTime(trimmedStart) {
            repaired.startTime = "17:00"
        }

        let trimmedEnd = repaired.endTime.trimmingCharacters(in: .whitespacesAndNewlines)
        if !RestaurantAutomationTimeValidation.isValidTime(trimmedEnd) {
            repaired.endTime = "18:00"
        }

        if !AutoConfirmPolicyValidation.validMaxPartySizeRange.contains(repaired.maxPartySize) {
            repaired.maxPartySize = 4
        }

        if repaired.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let startStorage = repaired.startTime.count == 5 ? "\(repaired.startTime):00" : repaired.startTime
            let endStorage = repaired.endTime.count == 5 ? "\(repaired.endTime):00" : repaired.endTime
            repaired.id = Self.generateRuleID(
                weekday: repaired.weekday,
                start: startStorage,
                end: endStorage
            )
        }

        repaired.ensureEndTimeAfterStart()
        repaired.enabled = true

        return repaired
    }

    private mutating func ensureEndTimeAfterStart() {
        guard RestaurantAutomationTimeValidation.isValidTime(startTime),
              RestaurantAutomationTimeValidation.isValidTime(endTime),
              let startMinutes = RestaurantAutomationTimeValidation.minutes(from: startTime),
              let endMinutes = RestaurantAutomationTimeValidation.minutes(from: endTime),
              endMinutes <= startMinutes else {
            return
        }

        let bumpedMinutes = min(startMinutes + 60, (23 * 60) + 59)
        endTime = String(format: "%02d:%02d", bumpedMinutes / 60, bumpedMinutes % 60)
    }
}

enum AutoConfirmTimeFormatting {
    static func shortDisplay(from storage: String) -> String {
        let trimmed = storage.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 5 ? String(trimmed.prefix(5)) : trimmed
    }

    static func normalizedStorage(from display: String, field: String) throws -> String {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RestaurantAutomationTimeValidation.isValidTime(trimmed) else {
            throw AutoConfirmEditorError(message: "\(field) must use HH:mm or HH:mm:ss.")
        }
        return trimmed.count == 5 ? "\(trimmed):00" : trimmed
    }

    static func displayRange(start: String, end: String) -> String {
        "\(friendlyTime(start))–\(friendlyTime(end))"
    }

    static func friendlyTime(_ value: String) -> String {
        let normalized = value.count == 5 ? "\(value):00" : value
        guard let date = ReservationFormatters.apiTime.date(from: String(normalized.prefix(8))) else {
            return value
        }
        return ReservationFormatters.shortTime.string(from: date)
    }
}

enum AutoConfirmWeekdayFormatting {
    static func name(for weekday: Int) -> String {
        switch weekday {
        case 0: return "Monday"
        case 1: return "Tuesday"
        case 2: return "Wednesday"
        case 3: return "Thursday"
        case 4: return "Friday"
        case 5: return "Saturday"
        case 6: return "Sunday"
        default: return "Day \(weekday)"
        }
    }

    static let orderedWeekdays = [0, 1, 2, 3, 4, 5, 6]
}

struct AutoConfirmEditorError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Rule Row

private struct AutoConfirmRuleRow: View {
    let rule: AutoConfirmRuleDraft
    let onEdit: () -> Void
    let onRepair: () -> Void
    let onDelete: () -> Void
    let onToggleEnabled: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.displayTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(rule.isValidRule ? Color.primary : Color.orange)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            if !rule.isValidRule {
                                warningBadge("Needs repair")
                                warningBadge("Disabled until repaired")
                            }
                            if rule.isValidRule && rule.showsWeekendWarning {
                                warningBadge("Fri/Sat")
                            }
                            if rule.isValidRule && rule.showsLargePartyWarning {
                                warningBadge("Large party")
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                if rule.isValidRule {
                    Toggle("", isOn: Binding(
                        get: { rule.enabled },
                        set: { _ in onToggleEnabled() }
                    ))
                    .labelsHidden()
                } else {
                    Toggle("", isOn: .constant(rule.enabled))
                        .labelsHidden()
                        .disabled(true)
                }
            }

            HStack {
                if !rule.isValidRule {
                    Button("Repair", action: onRepair)
                }
                Button("Edit", action: onEdit)
                Spacer()
                Button("Delete", role: .destructive, action: onDelete)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 6)
    }

    private func warningBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .foregroundStyle(.orange)
    }
}

// MARK: - Rule Sheet

private struct AutoConfirmRuleEditorSheet: View {
    @State private var draft: AutoConfirmRuleDraft
    let isNew: Bool
    let showRepairWarning: Bool
    let existingRuleIDs: [String]
    let onCancel: () -> Void
    let onSave: (AutoConfirmRuleDraft) -> Void

    @State private var validationMessage: String?
    @FocusState private var focusedField: AutoConfirmRuleFocusedField?

    init(
        draft: AutoConfirmRuleDraft,
        isNew: Bool,
        showRepairWarning: Bool = false,
        existingRuleIDs: [String],
        onCancel: @escaping () -> Void,
        onSave: @escaping (AutoConfirmRuleDraft) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.isNew = isNew
        self.showRepairWarning = showRepairWarning
        self.existingRuleIDs = existingRuleIDs
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var canSave: Bool {
        draft.isValidRule
            && !draft.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !existingRuleIDs.contains(draft.id.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        NavigationStack {
            Form {
                if showRepairWarning {
                    Section {
                        Text("This saved window had invalid values. Review and save to repair it.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if !draft.validationMessages.isEmpty {
                    Section {
                        ForEach(draft.validationMessages, id: \.self) { message in
                            Text(message)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }

                Section("Rule") {
                    Toggle("Enabled", isOn: $draft.enabled)

                    Picker("Weekday", selection: $draft.weekday) {
                        ForEach(AutoConfirmWeekdayFormatting.orderedWeekdays, id: \.self) { day in
                            Text(AutoConfirmWeekdayFormatting.name(for: day)).tag(day)
                        }
                    }

                    TextField("Start time (HH:mm)", text: $draft.startTime)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .startTime)
                    TextField("End time (HH:mm)", text: $draft.endTime)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .endTime)

                    Stepper(value: $draft.maxPartySize, in: 1...20) {
                        Text("Max party size: \(draft.maxPartySize)")
                    }
                }

                Section {
                    Text("End time is exclusive. Example: 17:00–18:00 covers reservations starting at 5:00 PM but not 6:00 PM.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isNew ? "Add Time Window" : "Edit Time Window")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveTapped()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func saveTapped() {
        focusedField = nil
        let trimmedID = draft.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            validationMessage = "Each auto-confirm rule needs an id."
            return
        }

        if existingRuleIDs.contains(trimmedID) {
            validationMessage = "Duplicate auto-confirm rule id: \(trimmedID)."
            return
        }

        do {
            let rule = try draft.toRule()
            let messages = draft.validationMessages
            guard messages.isEmpty else {
                validationMessage = messages.joined(separator: "\n")
                return
            }
            _ = rule
            onSave(draft)
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
