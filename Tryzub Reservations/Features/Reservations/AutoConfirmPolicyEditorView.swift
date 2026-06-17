//
//  AutoConfirmPolicyEditorView.swift
//  Tryzub Reservations
//
//  Manager-facing backend auto-confirm policy editor (PATCH /restaurant-setup only).
//

import SwiftUI

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
            AutoConfirmRuleEditorSheet(
                draft: rule,
                isNew: false,
                existingRuleIDs: draft.rules.map(\.id).filter { $0 != rule.id },
                onCancel: { editingRule = nil },
                onSave: { updated in
                    if let index = draft.rules.firstIndex(where: { $0.id == rule.id }) {
                        draft.rules[index] = updated
                    }
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
            Text("Backend auto-confirm sends confirmation emails and marks eligible website reservations as confirmed after website form import. This iPad never auto-confirms reservations locally.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

            if draft.autoConfirmEnabled, draft.enabledRuleCount == 0 {
                Text("Add at least one enabled time window before turning auto-confirm on.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var guardTogglesCard: some View {
        editorCard(title: "Safety Guards", systemImage: "shield") {
            Toggle("Require guest email", isOn: $draft.autoConfirmRequireEmail)
            Toggle("Block guest notes", isOn: $draft.autoConfirmBlockGuestNotes)
            Toggle("Block duplicates/corrections", isOn: $draft.autoConfirmBlockDuplicates)
            Toggle("Block suspicious contact info", isOn: $draft.autoConfirmBlockSuspicious)

            Text("Safer settings leave these protections on. Reservations with notes, duplicate signals, or suspicious contact data should stay for staff review.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rulesCard: some View {
        editorCard(title: "Time Windows", systemImage: "clock") {
            if draft.rules.isEmpty {
                Text("No rules yet. Add a time window to allow backend auto-confirm.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.rules) { rule in
                    AutoConfirmRuleRow(
                        rule: rule,
                        onEdit: { editingRule = rule },
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
                Label("Add Rule", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
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
            let policy = try draft.buildPolicy()
            let request = RestaurantSetupUpdateRequest(
                autoConfirmEnabled: draft.autoConfirmEnabled,
                autoConfirmRequireEmail: draft.autoConfirmRequireEmail,
                autoConfirmBlockGuestNotes: draft.autoConfirmBlockGuestNotes,
                autoConfirmBlockDuplicates: draft.autoConfirmBlockDuplicates,
                autoConfirmBlockSuspicious: draft.autoConfirmBlockSuspicious,
                autoConfirmPolicy: policy
            )

            let saved = try await settingsStore.saveRestaurantAutomationSetup(request: request)
            _ = try? await controller.loadRestaurantSetup(force: true)
            draft = AutoConfirmPolicyEditorDraft(setup: saved)
            onSaved(saved)
            successMessage = "Auto-confirm policy saved."
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

// MARK: - Draft

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

    var hasHighRiskRules: Bool {
        rules.contains { rule in
            rule.enabled && (rule.weekday == 4 || rule.weekday == 5 || rule.maxPartySize >= 8)
        }
    }

    init(setup: RestaurantSetup) {
        autoConfirmEnabled = setup.autoConfirmEnabled
        autoConfirmRequireEmail = setup.autoConfirmRequireEmail
        autoConfirmBlockGuestNotes = setup.autoConfirmBlockGuestNotes
        autoConfirmBlockDuplicates = setup.autoConfirmBlockDuplicates
        autoConfirmBlockSuspicious = setup.autoConfirmBlockSuspicious
        rules = setup.autoConfirmPolicy.rules.map(AutoConfirmRuleDraft.init(rule:))
        excludedDates = setup.autoConfirmPolicy.excludedDates.sorted()
    }

    func validationMessages() -> [String] {
        var messages: [String] = []

        if autoConfirmEnabled, enabledRuleCount == 0 {
            messages.append("Add at least one enabled time window before turning auto-confirm on.")
        }

        do {
            let policy = try buildPolicy()
            messages.append(contentsOf: AutoConfirmPolicyValidation.validate(policy: policy))
        } catch {
            messages.append(error.localizedDescription)
        }

        return messages
    }

    func buildPolicy() throws -> AutoConfirmPolicy {
        let encodedRules = try rules.map { try $0.toRule() }
        return AutoConfirmPolicy(rules: encodedRules, excludedDates: excludedDates)
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
        let normalizedStart = try AutoConfirmTimeFormatting.normalizedStorage(from: startTime, field: "Start time")
        let normalizedEnd = try AutoConfirmTimeFormatting.normalizedStorage(from: endTime, field: "End time")
        return AutoConfirmRule(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines),
            enabled: enabled,
            weekday: weekday,
            startTime: normalizedStart,
            endTime: normalizedEnd,
            maxPartySize: maxPartySize
        )
    }

    var rowTitle: String {
        "\(AutoConfirmWeekdayFormatting.name(for: weekday)) · \(AutoConfirmTimeFormatting.displayRange(start: startTime, end: endTime)) · up to \(maxPartySize) guests"
    }

    var showsWeekendWarning: Bool {
        weekday == 4 || weekday == 5
    }

    var showsLargePartyWarning: Bool {
        maxPartySize >= 8
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
    let onDelete: () -> Void
    let onToggleEnabled: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.rowTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            if rule.showsWeekendWarning {
                                warningBadge("Fri/Sat")
                            }
                            if rule.showsLargePartyWarning {
                                warningBadge("Large party")
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Toggle("", isOn: Binding(
                    get: { rule.enabled },
                    set: { _ in onToggleEnabled() }
                ))
                .labelsHidden()
            }

            HStack {
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
    let existingRuleIDs: [String]
    let onCancel: () -> Void
    let onSave: (AutoConfirmRuleDraft) -> Void

    @State private var validationMessage: String?

    init(
        draft: AutoConfirmRuleDraft,
        isNew: Bool,
        existingRuleIDs: [String],
        onCancel: @escaping () -> Void,
        onSave: @escaping (AutoConfirmRuleDraft) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.isNew = isNew
        self.existingRuleIDs = existingRuleIDs
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
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
                    TextField("End time (HH:mm)", text: $draft.endTime)
                        .keyboardType(.numbersAndPunctuation)

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
            .navigationTitle(isNew ? "Add Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveTapped()
                    }
                }
            }
        }
    }

    private func saveTapped() {
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
            let messages = AutoConfirmPolicyValidation.validate(rule: rule)
            guard messages.isEmpty else {
                validationMessage = messages.joined(separator: "\n")
                return
            }
            onSave(draft)
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
