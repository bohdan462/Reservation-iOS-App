//
//  ReservationDetailView.swift
//  Tryzub Reservations
//

import MessageUI
import PhotosUI
import SwiftUI
import SwiftData
import UIKit

// MARK: - Detail Presentation

struct ReservationDetailPresentation {
    struct Header {
        let guestName: String
        let status: ReservationStatus
        let dateText: String
        let timeText: String
        let partyText: String
        let tableText: String
        let sourceText: String
    }

    struct Row: Identifiable {
        let title: String
        let value: String
        var allowsWrap = false

        var id: String {
            "\(title)-\(value)"
        }
    }

    let header: Header
    let guestRows: [Row]
    let reservationRows: [Row]
    let notesRows: [Row]
    let emailStatus: String
    let actionPolicy: ReservationHostActionPolicy

    static func make(
        reservation: ReservationRecord,
        capabilities: AppCapabilities
    ) -> ReservationDetailPresentation {
        let emailStatus = Self.emailStateText(for: reservation)
        var reservationRows: [Row] = [
            Row(title: "Email", value: emailStatus),
            Row(title: "Submitted", value: submittedValue(for: reservation))
        ]

        if let timingText = reservation.operationalTimingDisplayText() {
            reservationRows.insert(Row(title: "Timing", value: timingText, allowsWrap: true), at: 0)
        }

        if let confirmedAt = reservation.confirmedAt?.nilIfBlank {
            reservationRows.append(Row(title: "Confirmed", value: serverTimestamp(confirmedAt)))
        }

        if let reminderSentAt = reservation.reminderEmailSentAt?.nilIfBlank {
            reservationRows.append(Row(title: "Reminder", value: "Sent \(serverTimestamp(reminderSentAt))"))
        } else if reservation.statusValue == .confirmed,
                  reservation.hasUsableConfirmationEmail {
            reservationRows.append(Row(title: "Reminder", value: "Not sent"))
        }

        var notesRows: [Row] = []
        if let guestNotes = reservation.guestNotes?.nilIfBlank {
            notesRows.append(Row(title: "Guest", value: guestNotes, allowsWrap: true))
        }
        if let staffNotes = reservation.staffNotes?.nilIfBlank {
            notesRows.append(Row(title: "Staff", value: staffNotes, allowsWrap: true))
        }

        return ReservationDetailPresentation(
            header: Header(
                guestName: reservation.guestName,
                status: reservation.statusValue,
                dateText: reservation.displayDate,
                timeText: reservation.displayTime,
                partyText: "\(reservation.partySize) \(reservation.partySize == 1 ? "guest" : "guests")",
                tableText: reservation.tableDisplay,
                sourceText: reservation.sourceDisplayName
            ),
            guestRows: [
                Row(title: "Phone", value: reservation.formattedPhone),
                Row(title: "Email", value: reservation.email.nilIfBlank ?? "No email")
            ],
            reservationRows: reservationRows,
            notesRows: notesRows,
            emailStatus: emailStatus,
            actionPolicy: ReservationHostActionPolicy(
                reservation: reservation,
                capabilities: capabilities,
                surface: .detail
            )
        )
    }

    private static func emailStateText(for reservation: ReservationRecord) -> String {
        if reservation.hasConfirmationEmailRecord {
            return "Confirmation email recorded"
        }

        if reservation.hasManualConfirmationEmailRecord {
            return "Manual email recorded (legacy note)"
        }

        if reservation.hasUsableConfirmationEmail {
            return "Email not sent"
        }

        return "No email"
    }

    private static func serverTimestamp(_ value: String) -> String {
        if let date = ReservationFormatters.serverDateTime.date(from: value) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return value
    }

    private static func submittedValue(for reservation: ReservationRecord) -> String {
        let stamp = serverTimestamp(reservation.createdAt)
        if let ago = reservation.submittedAgoText {
            return "\(stamp) · \(ago)"
        }
        return stamp
    }
}

// MARK: - Reservation Detail

struct ReservationDetailView: View {
    let reservation: ReservationRecord
    let environment: AppEnvironment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var hostIntentStore: HostReservationOpenIntentStore
    @EnvironmentObject private var hostIntelligenceSettingsStore: HostIntelligenceSettingsStore
    @EnvironmentObject private var guestIntelligenceStore: GuestIntelligenceStore
    @EnvironmentObject private var floorPlanStore: FloorPlanStore
    @EnvironmentObject private var activityStore: ReservationActivityStore
    @EnvironmentObject private var emailAutomationSettingsStore: EmailAutomationSettingsStore
    // Guest Insights uses the active reservation window, not the full SwiftData cache.
    @Query private var windowCachedReservations: [ReservationRecord]
    /// Local-device attachments for this reservation (Phase 5). Persisted by reservationRemoteID.
    @Query private var attachments: [ReservationAttachmentRecord]
    /// Local structured staff notes (deposit, preorder, kitchen, bar, setup, manager).
    @Query private var structuredNoteRecords: [ReservationStructuredNoteRecord]

    // MARK: - Local UI State

    @State private var showEditScreen = false
    @State private var isSavingQuickAction = false
    @State private var errorMessage: String?
    @State private var pendingAction: ReservationHostAction?
    @State private var tableAssignmentReservation: ReservationRecord?
    @State private var seatPromptReservation: ReservationRecord?
    @State private var seatAfterTableAssignment = false
    @State private var isShowingHideWrongEntryConfirmation = false
    @State private var guestManageLink: ReservationGuestManageLinkDTO?
    @State private var guestManageLinkMessage: String?
    @State private var isGeneratingGuestManageLink = false
    @State private var guestConfirmationMailDraft: GuestConfirmationMailPresenter.Draft?
    @StateObject private var guestInsightAnalysisCoordinator = GuestInsightsAnalysisCoordinator()
    @StateObject private var guestCommunicationCoordinator = GuestCommunicationCoordinator.templateOnly()

    init(reservation: ReservationRecord, environment: AppEnvironment) {
        self.reservation = reservation
        self.environment = environment
        let bounds = activeReservationWindowQueryBounds()
        let fromDate = bounds.from
        let toDate = bounds.to
        _windowCachedReservations = Query(
            filter: #Predicate<ReservationRecord> { record in
                !record.isHidden
                    && record.reservationDate >= fromDate
                    && record.reservationDate <= toDate
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate),
                SortDescriptor(\ReservationRecord.reservationTime)
            ]
        )
        let remoteID = reservation.remoteID
        _attachments = Query(
            filter: #Predicate<ReservationAttachmentRecord> { record in
                record.reservationRemoteID == remoteID
            },
            sort: [SortDescriptor(\ReservationAttachmentRecord.createdAt, order: .reverse)]
        )
        _structuredNoteRecords = Query(
            filter: #Predicate<ReservationStructuredNoteRecord> { record in
                record.reservationRemoteID == remoteID
            }
        )
    }

    private var guestInsightHistoryPool: [ReservationRecord] {
        GuestInsightLocalPool.boundedPool(
            selected: reservation,
            windowRecords: windowCachedReservations
        )
    }

    private var guestInsightReport: GuestInsightReport? {
        guestInsightAnalysisCoordinator.report
    }

    /// First (and only) structured note record for this reservation, if it exists.
    private var structuredNote: ReservationStructuredNoteRecord? {
        structuredNoteRecords.first
    }

    /// Returns the existing record or inserts a new one into the context.
    @MainActor
    @discardableResult
    private func getOrCreateStructuredNote() -> ReservationStructuredNoteRecord {
        if let existing = structuredNote { return existing }
        let record = ReservationStructuredNoteRecord(reservationRemoteID: reservation.remoteID)
        modelContext.insert(record)
        return record
    }

    /// Auto-seeds deposit/preorder status from NoteSignalAnalyzer results.
    /// Only runs once — skipped if a structured note record already exists.
    @MainActor
    private func autoSeedStructuredNoteFromSignals() {
        guard structuredNote == nil, !noteSignals.isEmpty else { return }
        let hasDeposit = noteSignals.contains { $0.type == .depositMentioned || $0.type == .depositVerified }
        let hasPreorder = noteSignals.contains { $0.type == .preorderMentioned || $0.type == .banquetMentioned }
        guard hasDeposit || hasPreorder else { return }
        let record = getOrCreateStructuredNote()
        if hasDeposit && record.depositStatus == .none {
            record.depositStatus = .mentioned
        }
        if hasPreorder && record.preorderStatus == .none {
            record.preorderStatus = .mentioned
        }
    }

    @State private var draftReviewContext: GuestMessageDraftReviewContext?
    @State private var guestMessageMailDraft: GuestConfirmationMailPresenter.Draft?
    @State private var pendingGuestMessageMailKind: GuestMessageDraftKind?
    @State private var guestMessageTextDraft: GuestTextMessageDraft?
    /// Signals derived deterministically from note text (Phase 6) and attachments (Phase 9).
    @State private var noteSignals: [ReservationSignal] = []
    /// Per-attachment signals keyed by ReservationAttachmentRecord.id, for inline display.
    @State private var attachmentSignalsByID: [String: [ReservationSignal]] = [:]
    /// Additive model-enriched note signals (tone + classification) — Phase 10.
    @State private var modelNoteSignals: [ReservationSignal] = []
    /// Controls the structured-notes editor sheet.
    @State private var showStructuredNoteEditor = false
    @State private var showStaffNotesEditor = false
    @State private var staffNotesDraft = ""
    // Phase 5 — Attachment state
    @State private var pendingPhotoItem: PhotosPickerItem?
    @State private var pendingPhotoData: Data?
    @State private var pendingLabel: AttachmentLabel = .other
    @State private var showLabelPicker = false
    @State private var previewAttachmentRecord: ReservationAttachmentRecord?
    @State private var attachmentError: String?

    var body: some View {
        GeometryReader { proxy in
            let safeWidth = proxy.size.width.tryzubFiniteNonNegativeLayoutValue
            let isWide = safeWidth >= 760
            ScrollView {
                detailContent(isWide: isWide)
                    .padding(.horizontal, isWide ? 20 : 16)
                    .padding(.vertical, 16)
                    .padding(.bottom, ReservationLayout.scrollBottomInset)
                    .cappedContentWidth(isWide ? 1000 : nil)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            guestCommunicationCoordinator.useLocalModelProvider = {
                hostIntelligenceSettingsStore.settings.useLocalModelForGuestMessageDrafts
            }
            guestIntelligenceStore.markDetailOpened(reservationID: reservation.remoteID)
            recomputeNoteSignals()
            logNotesSemantics()
            autoSeedStructuredNoteFromSignals()
            // Schedule OCR for any existing attachments that haven't been scanned yet.
            if AttachmentFeatureFlag.ocrEnabled {
                for attachment in attachments where attachment.ocrRanAt == nil {
                    scheduleOCR(for: attachment)
                }
            }
            // Model note enrichment (tone + missed signals) — additive, non-blocking.
            Task { await enrichNoteSignalsWithModel() }
        }
        .onChange(of: attachments) { _, _ in
            // Re-run signal analysis when attachments change (new attachment saved,
            // OCR completes and writes extractedText, or attachment deleted).
            recomputeNoteSignals()
        }
        .confirmationDialog("Label this photo", isPresented: $showLabelPicker, titleVisibility: .visible) {
            ForEach(AttachmentLabel.allCases) { label in
                Button(label.rawValue) {
                    saveAttachment(label: label)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingPhotoItem = nil
                pendingPhotoData = nil
            }
        }
        .fullScreenCover(item: $previewAttachmentRecord) { record in
            AttachmentPreviewScreen(record: record) {
                previewAttachmentRecord = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(reservation.guestName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $tableAssignmentReservation) { reservation in
            TableAssignmentSheet(reservation: reservation) { tableName in
                // Use canonical PATCH /managed-reservations/{id}/tables when a backend
                // floor layout exists. This enforces table conflict rules.
                // Fall back to legacy table_name PATCH when no layout is available.
                if floorPlanStore.hasBackendLayout,
                   let tableKey = floorPlanStore.tableKey(forLabel: tableName) {
                    TableAssignmentTrace.canonicalFloorPlan(
                        reservationID: reservation.remoteID,
                        tableKeys: [tableKey]
                    )
                    await floorPlanStore.assign(
                        reservationID: reservation.remoteID,
                        tableKeys: [tableKey],
                        controller: controller,
                        context: modelContext
                    )
                } else {
                    // Legacy path: no floor layout or table key not found.
                    // Does NOT enforce backend table conflict rules.
                    TableAssignmentTrace.legacyPatch(
                        reservationID: reservation.remoteID,
                        tableName: tableName
                    )
                    _ = try await controller.updateReservation(
                        id: reservation.remoteID,
                        request: ReservationUpdateRequest(tableName: tableName),
                        context: modelContext
                    )
                }
                if seatAfterTableAssignment {
                    seatAfterTableAssignment = false
                    await controller.updateStatus(
                        reservation: reservation,
                        status: .seated,
                        context: modelContext
                    )
                    ReservationHaptics.success()
                }
            }
        }
        .reservationSeatTableChoice(
            seatPromptReservation: $seatPromptReservation,
            onAssignTable: { reservation in
                seatAfterTableAssignment = true
                tableAssignmentReservation = reservation
            },
            onSeatWithoutTable: { _ in
                Task { await perform(.seat) }
            }
        )
        .sheet(item: $guestConfirmationMailDraft) { draft in
            GuestConfirmationMailComposer(draft: draft) { result in
                handleGuestConfirmationMailFinished(result, draft: draft)
            }
        }
        .sheet(item: $draftReviewContext) { context in
            GuestMessageDraftReviewView(
                reservationID: reservation.remoteID,
                kind: context.kind,
                draft: context.draft,
                canSendEmail: reservation.hasUsableConfirmationEmail,
                canSendText: GuestTextMessagePresenter.hasDialablePhone(reservation.phone),
                onSendEmail: { sendDraftEmail($0) },
                onSendText: { sendDraftText($0) },
                onCopyEmail: { copyDraftEmail($0) },
                onCopyText: { copyDraftText($0) },
                onDismiss: { draftReviewContext = nil }
            )
        }
        .sheet(item: $guestMessageMailDraft) { draft in
            GuestConfirmationMailComposer(draft: draft) { result in
                handleGuestMessageMailFinished(result, draft: draft)
            }
        }
        .sheet(item: $guestMessageTextDraft) { draft in
            GuestTextMessageComposer(draft: draft) { _ in
                guestMessageTextDraft = nil
            }
        }
        .navigationDestination(isPresented: $showEditScreen) {
            ReservationEditFormView(reservation: reservation) { request in
                // Detail edits are server PATCH operations through the controller.
                try await controller.updateReservation(
                    id: reservation.remoteID,
                    request: request,
                    context: modelContext
                )
            }
        }
        .confirmationDialog(
            pendingAction?.dialogTitle(for: reservation) ?? "Update Reservation?",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(pendingAction.fullTitle, role: pendingAction.role) {
                    Task {
                        await perform(pendingAction)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            if let pendingAction {
                Text(pendingAction.dialogMessage(for: reservation))
            }
        }
        .confirmationDialog(
            "Hide wrong entry?",
            isPresented: $isShowingHideWrongEntryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Hide wrong entry", role: .destructive) {
                Task {
                    await hideWrongManualEntry()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This hides the server reservation from normal lists while keeping it in backend history.")
        }
        .onChange(of: windowCachedReservations.count) { _, count in
            UIPressureTrace.phase(
                "swiftdata_query_refresh",
                duration: 0,
                extra: "source=detail/windowCachedReservations count=\(count)"
            )
        }
        .task(id: guestInsightCacheKey) {
            guestInsightAnalysisCoordinator.scheduleAnalysis(
                selected: reservation,
                pool: guestInsightHistoryPool
            )
        }
        .task(id: guestIntelligenceFetchKey) {
            guestIntelligenceStore.ensureSummary(
                reservationID: reservation.remoteID,
                dateKey: reservation.reservationDate
            )
            await guestIntelligenceStore.loadProfile(
                reservationID: reservation.remoteID,
                dateKey: reservation.reservationDate
            )
        }
        .task(id: guestMergeTraceKey) {
            guard let guestInsightReport else { return }
            guestIntelligenceStore.recordMergePresentation(
                surface: "detail",
                reservationID: reservation.remoteID,
                guestName: reservation.guestName,
                localReport: guestInsightReport,
                dateKey: reservation.reservationDate,
                semanticStamp: guestIntelligenceStore.semanticProfileStamp(
                    for: reservation.remoteID,
                    dateKey: reservation.reservationDate
                )
            )
        }
    }

    // MARK: - Detail Layout

    private func detailColumnPair<Left: View, Right: View>(
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            DetailGridColumn {
                left()
            }
            DetailGridColumn {
                right()
            }
        }
    }

    @ViewBuilder
    private func detailContent(isWide: Bool) -> some View {
        let presentation = ReservationDetailPresentation.make(
            reservation: reservation,
            capabilities: controller.capabilities
        )

        VStack(alignment: .leading, spacing: 14) {
            banners

            if isWide {
                VStack(spacing: 14) {
                    detailColumnPair {
                        DetailHeroCard(header: presentation.header, layout: .compact)
                    } right: {
                        actionBar
                    }

                    wideImportantGuestNotesRow(presentation)

                    detailColumnPair {
                        attachmentsCard
                    } right: {
                        staffNotesCard
                    }

                    detailColumnPair {
                        detailsCard(presentation)
                    } right: {
                        guestInsightsSection
                    }

                    detailColumnPair {
                        contactCard
                    } right: {
                        VStack(alignment: .leading, spacing: 14) {
                            draftMessageCard
                            ReservationActivityHistorySection(
                                reservationID: reservation.remoteID,
                                reservationLabel: presentation.header.guestName
                            )
                            ReservationServiceLoadCard(
                                reservation: reservation,
                                sameDayReservations: sameDayReservations
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            } else {
                VStack(spacing: 14) {
                    DetailHeroCard(header: presentation.header)
                    actionBar
                    importantCard(presentation)
                    noteSignalsCard
                    guestNotesCard
                    staffNotesCard
                    attachmentsCard
                    guestInsightsSection
                    detailsCard(presentation)
                    contactCard
                    draftMessageCard
                    ReservationActivityHistorySection(
                        reservationID: reservation.remoteID,
                        reservationLabel: presentation.header.guestName
                    )
                    ReservationServiceLoadCard(
                        reservation: reservation,
                        sameDayReservations: sameDayReservations
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        if let intent = hostIntentStore.consume(for: reservation.remoteID) {
            HostIntelligenceIntentBanner(intent: intent) {
                hostIntentStore.clearIfMatches(intent.id)
            }
        }

        if let message = errorMessage ?? controller.errorMessage {
            DetailWarningCard(
                title: "Action did not finish",
                message: message,
                symbolName: "exclamationmark.triangle",
                tint: .red
            )
        }

        if let attention = attentionExplanation {
            DetailWarningCard(
                title: attention.title,
                message: attention.message,
                symbolName: attention.symbol,
                tint: attention.tint
            )
        }

        if let guestManageLinkMessage {
            DetailWarningCard(
                title: "Guest link ready",
                message: guestManageLinkMessage,
                symbolName: "link",
                tint: TryzubColors.info
            )
        }

        if let message = guestCommunicationCoordinator.lastErrorMessage {
            DetailWarningCard(
                title: "Guest message",
                message: message,
                symbolName: "text.bubble",
                tint: TryzubColors.info
            )
        }
    }

    private var actionBar: some View {
        DetailActionBar(
            reservation: reservation,
            capabilities: controller.capabilities,
            isBusy: isSavingQuickAction || controller.isActionInProgress(for: reservation),
            isNetworkDegraded: controller.isNetworkDegraded,
            isGeneratingGuestManageLink: isGeneratingGuestManageLink,
            hasGuestManageLink: guestManageLink != nil,
            onAction: handleAction,
            onSeatRequiresTableChoice: { seatPromptReservation = reservation },
            onEdit: { showEditScreen = true },
            onSendGuestConfirmationEmail: canShowManualConfirmationFallback
                ? { Task { await sendGuestConfirmationEmail() } }
                : nil,
            onRecordManualConfirmationSent: showsDeveloperGuestTools && canShowManualConfirmationFallback && guestManageLink != nil
                ? { Task { await recordManualConfirmationSentFromCurrentDraft() } }
                : nil,
            onGenerateGuestManageLink: showsDeveloperGuestTools && canShowManualConfirmationFallback && controller.capabilities.canGenerateGuestManageLinks
                ? { Task { await generateGuestManageLink() } }
                : nil,
            onCopyGuestManageLink: showsDeveloperGuestTools && canShowManualConfirmationFallback && guestManageLink != nil
                ? { copyGuestManageLink() }
                : nil,
            onCopyConfirmationDraft: showsDeveloperGuestTools && canShowManualConfirmationFallback && guestManageLink != nil
                ? { copyGuestConfirmationDraft() }
                : nil,
            onHideWrongEntry: reservation.canSoftHideAsWrongEntry && !reservation.isHidden
                ? { isShowingHideWrongEntryConfirmation = true }
                : nil,
            onRestoreHidden: reservation.isHidden
                ? { Task { await restoreHiddenReservation() } }
                : nil
        )
    }

    private var showsDeveloperGuestTools: Bool {
        environment.role == .developer
    }

    private var canShowManualConfirmationFallback: Bool {
        emailAutomationSettingsStore.settings.manualMailFallbackEnabled
            && controller.capabilities.canGenerateGuestManageLinks
            && reservation.hasUsableConfirmationEmail
            && !reservation.isHidden
            && reservation.statusValue != .confirmed
            && reservation.statusValue != .completed
            && reservation.statusValue != .cancelled
            && reservation.statusValue != .noShow
    }

    private var draftMessageCard: some View {
        GuestMessageDraftActionsSection(
            reservation: reservation,
            isDrafting: guestCommunicationCoordinator.isDrafting,
            onDraft: generateGuestMessageDraft
        )
    }

    private var contactCard: some View {
        DetailSectionCard(title: "Contact", systemImage: "phone.fill") {
            VStack(spacing: 10) {
                DetailContactRow(
                    title: "Phone",
                    value: reservation.formattedPhone,
                    url: reservation.callURL
                )
                Divider().opacity(0.4)
                DetailContactRow(
                    title: "Email",
                    value: reservation.hasUsableConfirmationEmail ? reservation.email : "No email",
                    url: reservation.mailtoURL
                )

                if reservation.callURL != nil {
                    Divider().opacity(0.4)
                    GuestTextMessageActionButtons(
                        phone: reservation.phone,
                        confirmationBody: ManualTextMessageService.confirmationBody(reservation: reservation),
                        tableDueBody: ManualTextMessageService.tableDueBody(reservation: reservation),
                        includesConfirmation: showsConfirmationTextAction,
                        includesTableReady: showsTableReadyTextAction
                    )
                }
            }
        }
    }

    private var showsConfirmationTextAction: Bool {
        guard !reservation.isHidden else { return false }
        switch reservation.statusValue {
        case .new, .needsReview:
            return true
        default:
            return false
        }
    }

    private var showsTableReadyTextAction: Bool {
        guard !reservation.isHidden else { return false }
        switch reservation.statusValue {
        case .confirmed, .seated:
            return true
        case .cancelled, .completed, .noShow:
            return false
        default:
            return false
        }
    }

    /// "Important" card — shows only when there is something staff need to notice before
    private func recomputeNoteSignals() {
        let input = NoteSignalAnalyzer.Input(
            reservationID: String(reservation.remoteID),
            guestNote: reservation.guestNotes?.nilIfBlank,
            staffNote: reservation.staffNotes?.nilIfBlank
        )
        var signals = NoteSignalAnalyzer.analyze(input)

        // Merge attachment signals (label-based + OCR-based).
        var localAttSignalMap: [String: [ReservationSignal]] = [:]
        for attachment in attachments {
            let attInput = AttachmentSignalAnalyzer.Input(
                reservationID: String(reservation.remoteID),
                attachmentID: attachment.id,
                label: attachment.label,
                extractedText: attachment.extractedText
            )
            let attSignals = AttachmentSignalAnalyzer.analyze(attInput)
            localAttSignalMap[attachment.id] = attSignals
            for s in attSignals {
                AttachmentOCRTrace.labelSignal(
                    reservationID: reservation.remoteID,
                    attachmentID: attachment.id,
                    signalType: s.type.rawValue
                )
            }
            signals.append(contentsOf: attSignals)
        }
        attachmentSignalsByID = localAttSignalMap

        // Deduplicate deterministic + attachment signals by type (highest priority wins).
        var seenTypes = Set<ReservationSignalType>()
        signals = signals.sorted { $0.priority > $1.priority }.filter { signal in
            seenTypes.insert(signal.type).inserted
        }

        // Model signals (Phase 10) are additive: only surface types the deterministic and
        // attachment passes missed. Deterministic/attachment evidence always wins.
        let existingTypes = Set(signals.map { $0.type })
        let newModelSignals = modelNoteSignals.filter { !existingTypes.contains($0.type) }
        signals.append(contentsOf: newModelSignals)

        noteSignals = signals.sorted { $0.priority > $1.priority }
        for signal in noteSignals {
            WorkflowCleanupTrace.log(
                "NOTE_SIGNAL_TRACE",
                fields: [
                    "reservation": "\(reservation.remoteID)",
                    "signal": signal.type.rawValue,
                    "source": signal.source.rawValue,
                    "confidence": signal.confidence.rawValue,
                    "label": signal.title.replacingOccurrences(of: " ", with: "_")
                ]
            )
        }
    }

    private func logNotesSemantics() {
        var sections = ["guest_notes", "staff_notes"]
        if !noteSignals.isEmpty { sections.append("note_signals") }
        WorkflowCleanupTrace.log(
            "NOTES_SEMANTICS_TRACE",
            fields: [
                "reservation": "\(reservation.remoteID)",
                "guestNotesPresent": "\(reservation.guestNotes?.nilIfBlank != nil)",
                "staffNotesPresent": "\(reservation.staffNotes?.nilIfBlank != nil)",
                "sections": sections.joined(separator: ",")
            ]
        )
    }

    /// Phase 10 — asks the on-device model to read the note for tone + missed signals.
    /// Deterministic signals are already shown; this only adds, never blocks or replaces.
    private func enrichNoteSignalsWithModel() async {
        guard hostIntelligenceSettingsStore.settings.useLocalModelForNoteAnalysis else { return }
        let analyzer = LocalModelNoteAnalyzer()
        let enriched = await analyzer.analyze(
            LocalModelNoteAnalyzer.Input(
                reservationID: String(reservation.remoteID),
                guestNote: reservation.guestNotes?.nilIfBlank,
                staffNote: reservation.staffNotes?.nilIfBlank
            )
        )
        guard !enriched.isEmpty else { return }
        modelNoteSignals = enriched
        recomputeNoteSignals()
    }

    /// Schedules background Vision OCR on a newly saved attachment.
    /// OCR runs off the main thread; result is written back to SwiftData.
    private func scheduleOCR(for record: ReservationAttachmentRecord) {
        guard AttachmentFeatureFlag.ocrEnabled else { return }
        guard record.extractedText == nil else { return }

        let filename = record.filename
        let recordID = record.id
        let reservationID = reservation.remoteID

        AttachmentOCRTrace.ocrStarted(reservationID: reservationID, filename: filename)

        Task {
            // Run Vision off the main thread.
            let text = await Task.detached(priority: .utility) {
                await AttachmentOCRService.extractText(filename: filename)
            }.value

            // Write result back on main actor.
            if let text {
                AttachmentOCRTrace.ocrCompleted(
                    reservationID: reservationID,
                    filename: filename,
                    textChars: text.count,
                    signalCount: 0
                )
            } else {
                AttachmentOCRTrace.ocrEmpty(reservationID: reservationID, filename: filename)
            }

            if let existing = attachments.first(where: { $0.id == recordID }) {
                existing.extractedText = text
                existing.ocrRanAt = Date()
                try? modelContext.save()
            }
            recomputeNoteSignals()
        }
    }

    /// Shows signals derived from note text analysis (Phase 6 — Note intelligence).
    /// Only displayed when NoteSignalAnalyzer finds something actionable.
    @ViewBuilder
    private var noteSignalsCard: some View {
        if !noteSignals.isEmpty {
            DetailSectionCard(title: "Note signals", systemImage: "lightbulb") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(noteSignals) { signal in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: signalIcon(for: signal.type))
                                .foregroundStyle(signalColor(for: signal.priority))
                                .font(.subheadline)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(signal.title)
                                        .font(.subheadline.weight(.semibold))
                                    if signal.requiresReview {
                                        Text("Review")
                                            .font(.caption2.weight(.medium))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.15))
                                            .foregroundStyle(Color.orange)
                                            .cornerRadius(4)
                                    }
                                }
                                Text(signal.staffText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let evidence = signal.evidence {
                                    Text("\u{201C}\(evidence)\u{201D}")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func signalIcon(for type: ReservationSignalType) -> String {
        switch type {
        case .depositMentioned, .depositVerified: return "banknote"
        case .preorderMentioned, .banquetMentioned: return "cart"
        case .allergyOrDietary: return "allergens"
        case .accessibility: return "accessibility"
        case .occasion: return "party.popper"
        case .guestPreference: return "chair"
        case .kitchenNote: return "fork.knife"
        case .barNote: return "wineglass"
        case .guestSentiment: return "heart.text.square"
        case .serviceIssue: return "exclamationmark.bubble"
        case .guestCommunicationNeeded: return "bubble.left.and.bubble.right"
        default: return "note.text"
        }
    }

    private func signalColor(for priority: SignalPriority) -> Color {
        switch priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .accentColor
        case .low, .info: return .secondary
        }
    }

    @ViewBuilder
    private func importantCard(_ presentation: ReservationDetailPresentation) -> some View {
        let flags = ReservationImportantFlags.make(reservation: reservation)
        if !flags.isEmpty {
            DetailSectionCard(title: "Important", systemImage: "exclamationmark.triangle") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(flags) { flag in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: flag.icon)
                                .foregroundStyle(flag.tint)
                                .font(.subheadline)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(flag.title)
                                    .font(.subheadline.weight(.semibold))
                                if let detail = flag.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func wideImportantGuestNotesRow(_ presentation: ReservationDetailPresentation) -> some View {
        let hasImportant = !ReservationImportantFlags.make(reservation: reservation).isEmpty
        let hasNoteSignals = !noteSignals.isEmpty

        if hasImportant || hasNoteSignals {
            detailColumnPair {
                VStack(alignment: .leading, spacing: 14) {
                    importantCard(presentation)
                    noteSignalsCard
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } right: {
                guestNotesCard
            }
        } else {
            guestNotesCard
        }
    }

    private var guestNotesCard: some View {
        DetailSectionCard(title: "Guest Notes", systemImage: "note.text") {
            if let guestNotes = reservation.guestNotes?.nilIfBlank {
                DetailNoteRow(label: "Guest", text: guestNotes)
            } else {
                DetailPlainLine("No guest notes.")
            }
        }
    }

    private var staffNotesCard: some View {
        DetailSectionCard(title: "Staff Notes", systemImage: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                if let staffNotes = DetailStaffNotesDisplay.normalized(reservation.staffNotes) {
                    DetailNoteRow(label: "Staff", text: staffNotes)
                } else {
                    DetailPlainLine("No staff notes added yet.")
                }

                Button {
                    staffNotesDraft = reservation.staffNotes ?? ""
                    showStaffNotesEditor = true
                } label: {
                    Label(
                        reservation.staffNotes?.nilIfBlank == nil ? "Add staff notes" : "Edit staff notes",
                        systemImage: "pencil"
                    )
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(TryzubColors.primaryControl)
            }
        }
        .sheet(isPresented: $showStaffNotesEditor) {
            staffNotesEditorSheet
        }
    }

    private var staffNotesEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Staff Notes")
                    .font(.headline.weight(.semibold))
                TextEditor(text: $staffNotesDraft)
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding()
            .navigationTitle("Staff Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showStaffNotesEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveStaffNotesDraft() }
                    }
                }
            }
        }
    }

    @MainActor
    private func saveStaffNotesDraft() async {
        let trimmed = staffNotesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? nil : trimmed
        do {
            _ = try await controller.updateReservation(
                id: reservation.remoteID,
                request: ReservationUpdateRequest(
                    staffNotes: normalized,
                    expectedUpdatedAt: reservation.apiUpdatedAt
                ),
                context: modelContext,
                action: "staff_notes_update"
            )
            WorkflowCleanupTrace.log(
                "STAFF_NOTES_PATCH_TRACE",
                fields: [
                    "reservation": "\(reservation.remoteID)",
                    "result": "success",
                    "rowVersion": reservation.apiUpdatedAt ?? "none"
                ]
            )
            showStaffNotesEditor = false
            ReservationHaptics.success()
        } catch {
            WorkflowCleanupTrace.log(
                "STAFF_NOTES_PATCH_TRACE",
                fields: [
                    "reservation": "\(reservation.remoteID)",
                    "result": "failed",
                    "rowVersion": reservation.apiUpdatedAt ?? "none"
                ]
            )
            errorMessage = "Could not save staff notes. Check the connection and try again."
            ReservationHaptics.warning()
        }
    }

    private var attachmentsCard: some View {
        DetailSectionCard(title: "Attachments", systemImage: "paperclip") {
            VStack(alignment: .leading, spacing: 10) {

                if let error = attachmentError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !attachments.isEmpty {
                    ForEach(attachments) { record in
                        AttachmentRow(
                            record: record,
                            signals: attachmentSignalsByID[record.id] ?? [],
                            onTap: { previewAttachmentRecord = record },
                            onDelete: { deleteAttachment(record) }
                        )
                        if record.id != attachments.last?.id {
                            Divider().opacity(0.4)
                        }
                    }
                } else {
                    Text("No photos attached yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                PhotosPicker(
                    selection: $pendingPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Add photo", systemImage: "plus.circle")
                        .font(.subheadline.weight(.medium))
                }
                .onChange(of: pendingPhotoItem) { _, item in
                    guard let item else { return }
                    loadPhoto(item)
                }
            }
        }
    }

    // MARK: - Structured staff notes

    /// Staff-structured notes section: manager, kitchen, bar, setup notes.
    @ViewBuilder
    private var structuredNotesSection: some View {
        let note = structuredNote
        let hasContent = note?.hasStaffNoteContent ?? false
        DetailSectionCard(title: "Staff notes", systemImage: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: 0) {
                if let note, hasContent {
                    VStack(spacing: 0) {
                        if let text = note.managerNote?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                            StructuredNoteRow(label: "Manager", icon: "person.badge.key", text: text)
                            Divider().opacity(0.4).padding(.vertical, 6)
                        }
                        if let text = note.kitchenNote?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                            StructuredNoteRow(label: "Kitchen", icon: "fork.knife", text: text)
                            Divider().opacity(0.4).padding(.vertical, 6)
                        }
                        if let text = note.barNote?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                            StructuredNoteRow(label: "Bar", icon: "wineglass", text: text)
                            Divider().opacity(0.4).padding(.vertical, 6)
                        }
                        if let text = note.setupNote?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                            StructuredNoteRow(label: "Setup", icon: "chair", text: text)
                        }
                    }
                } else {
                    Text("No staff notes added yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
                Button {
                    showStructuredNoteEditor = true
                } label: {
                    Label(hasContent ? "Edit staff notes" : "Add staff notes", systemImage: hasContent ? "pencil" : "plus.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(TryzubColors.primaryControl)
                }
                .buttonStyle(.plain)
                .padding(.top, hasContent ? 8 : 0)
            }
        }
        .sheet(isPresented: $showStructuredNoteEditor) {
            StructuredNoteEditorSheet(
                reservationID: reservation.remoteID,
                guestName: reservation.guestName,
                existingRecord: structuredNote,
                modelContext: modelContext
            )
        }
    }

    /// Deposit section — shown when deposit has any content or on first open if note signals found deposit.
    @ViewBuilder
    private var depositSection: some View {
        let note = structuredNote
        let hasContent = note?.hasDepositContent ?? false
        let isDeposit = noteSignals.contains { $0.type == .depositMentioned || $0.type == .depositVerified }
        if hasContent || isDeposit {
            DetailSectionCard(title: "Deposit", systemImage: "banknote") {
                VStack(alignment: .leading, spacing: 8) {
                    if let note {
                        HStack(spacing: 8) {
                            Text("Status")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .leading)
                            DepositStatusPill(status: note.depositStatus)
                        }
                        if let amount = note.depositAmountText?.trimmingCharacters(in: .whitespacesAndNewlines), !amount.isEmpty {
                            HStack(spacing: 8) {
                                Text("Amount")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                Text(amount)
                                    .font(.subheadline)
                            }
                        }
                        if let noteText = note.depositNoteText?.trimmingCharacters(in: .whitespacesAndNewlines), !noteText.isEmpty {
                            Text(noteText)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if isDeposit {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                            Text("Deposit mentioned in notes — manager should verify.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showStructuredNoteEditor = true
                    } label: {
                        Label(hasContent ? "Edit deposit info" : "Record deposit info", systemImage: hasContent ? "pencil" : "plus.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TryzubColors.primaryControl)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Preorder / Banquet section — shown when preorder has any content or signals found preorder.
    @ViewBuilder
    private var preorderSection: some View {
        let note = structuredNote
        let hasContent = note?.hasPreorderContent ?? false
        let isPreorder = noteSignals.contains { $0.type == .preorderMentioned || $0.type == .banquetMentioned }
        if hasContent || isPreorder {
            DetailSectionCard(title: "Preorder / Banquet", systemImage: "cart") {
                VStack(alignment: .leading, spacing: 8) {
                    if let note {
                        HStack(spacing: 8) {
                            Text("Status")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .leading)
                            PreorderStatusPill(status: note.preorderStatus)
                        }
                        if let noteText = note.preorderNoteText?.trimmingCharacters(in: .whitespacesAndNewlines), !noteText.isEmpty {
                            Text(noteText)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let banquetText = note.banquetNoteText?.trimmingCharacters(in: .whitespacesAndNewlines), !banquetText.isEmpty {
                            Divider().opacity(0.4)
                            StructuredNoteRow(label: "Banquet", icon: "fork.knife.circle", text: banquetText)
                        }
                    } else if isPreorder {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                            Text("Preorder mentioned in notes — kitchen should review.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showStructuredNoteEditor = true
                    } label: {
                        Label(hasContent ? "Edit preorder info" : "Record preorder info", systemImage: hasContent ? "pencil" : "plus.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TryzubColors.primaryControl)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { return }
                await MainActor.run {
                    pendingPhotoData = data
                    pendingLabel = .other
                    showLabelPicker = true
                }
            } catch {
                await MainActor.run {
                    attachmentError = "Could not load the photo."
                    pendingPhotoItem = nil
                }
            }
        }
    }

    private func saveAttachment(label: AttachmentLabel) {
        guard let data = pendingPhotoData,
              let image = UIImage(data: data) else {
            pendingPhotoItem = nil
            pendingPhotoData = nil
            return
        }
        let record = ReservationAttachmentRecord(
            reservationRemoteID: reservation.remoteID,
            label: label
        )
        do {
            try AttachmentFileStore.save(image: image, filename: record.filename)
            modelContext.insert(record)
            attachmentError = nil
            AttachmentOCRTrace.attached(
                reservationID: reservation.remoteID,
                filename: record.filename,
                label: label.rawValue
            )
            // Immediate label-based signals appear via recomputeNoteSignals() on next @Query update.
            // Schedule background OCR to enrich signals with actual image text.
            scheduleOCR(for: record)
        } catch {
            attachmentError = error.localizedDescription
        }
        pendingPhotoItem = nil
        pendingPhotoData = nil
    }

    private func deleteAttachment(_ record: ReservationAttachmentRecord) {
        AttachmentFileStore.delete(filename: record.filename)
        modelContext.delete(record)
    }

    private func detailsCard(_ presentation: ReservationDetailPresentation) -> some View {
        DetailSectionCard(title: "Details", systemImage: "info.circle") {
            VStack(spacing: 10) {
                ForEach(presentation.reservationRows) { row in
                    DetailDataRow(title: row.title, value: row.value, allowsWrap: row.allowsWrap)
                }
            }
        }
    }

    private var sameDayReservations: [ReservationRecord] {
        windowCachedReservations.filter {
            $0.reservationDate == reservation.reservationDate && !$0.isHidden
        }
    }

    // Human explanation of why this reservation needs attention right now.
    private var attentionExplanation: (title: String, message: String, symbol: String, tint: Color)? {
        let timing = reservation.operationalTimingState()

        if reservation.statusValue == .needsReview {
            return (
                "Needs review",
                "Check this reservation before confirming. Guest Notes and Staff Notes are shown separately below.",
                "exclamationmark.triangle",
                .orange
            )
        }

        if case .overdue = timing, let text = timing.insightText {
            return ("Running late", "\(text). The reservation time has passed and it is not seated yet.", "exclamationmark.triangle", .red)
        }

        if reservation.isInReviewQueue, let ago = reservation.submittedStaffTimeText {
            return ("Awaiting confirmation", "Submitted \(ago). Confirm to notify the guest and lock the table.", "clock.badge.exclamationmark", TryzubColors.info)
        }

        return nil
    }

    @ViewBuilder
    private var guestInsightsSection: some View {
        DetailSectionCard(title: "Guest insights", systemImage: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                if let guestInsightReport {
                    // Full report available: preview card already contains profile text.
                    NavigationLink {
                        GuestInsightsView(
                            selectedReservation: reservation,
                            allReservations: guestInsightHistoryPool
                        )
                        .environmentObject(guestIntelligenceStore)
                    } label: {
                        GuestInsightsPreviewCard(
                            report: guestInsightReport,
                            presentation: guestDetailInsightPresentation(report: guestInsightReport),
                            profilePreview: guestProfilePreview,
                            mergedRegularity: mergedRegularityLevel(for: guestInsightReport)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let guestProfilePreview {
                    // Profile available but no local history report yet.
                    Text(guestProfilePreview.title)
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(guestProfilePreview.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if guestIntelligenceStore.isLoadingProfile(reservationID: reservation.remoteID) {
                    TryzubLoadingRow(title: "Loading server guest history...")
                } else if guestInsightAnalysisCoordinator.isAnalyzingLocalCache {
                    TryzubLoadingRow(title: "Calculating local cache insights...")
                }
            }
        }
    }

    private var guestProfilePreview: GuestInsightsProfilePresentation.DetailPreview? {
        GuestInsightsProfilePresentation.detailPreview(
            guestName: reservation.guestName,
            pack: guestIntelligenceStore.profilePack(for: reservation.remoteID)
        )
    }

    private func guestDetailInsightPresentation(
        report: GuestInsightReport
    ) -> GuestHistorySemantics.DetailInsightPresentation {
        let serverSummary = guestIntelligenceStore.summary(
            for: reservation.remoteID,
            dateKey: reservation.reservationDate
        )
        let serverAnswered = guestIntelligenceStore.hasServerAnswer(
            for: reservation.remoteID,
            dateKey: reservation.reservationDate
        )
        return GuestHistorySemantics.detailInsightPresentation(
            reservation: reservation,
            localReport: report,
            serverSummary: serverSummary,
            serverAnswered: serverAnswered,
            profilePack: guestIntelligenceStore.profilePack(for: reservation.remoteID)
        )
    }

    private var guestIntelligenceFetchKey: String {
        "\(reservation.remoteID)-\(reservation.reservationDate)-\(guestIntelligenceStore.cacheStamp(for: reservation.reservationDate))-\(guestIntelligenceStore.profileCacheStamp(for: reservation.remoteID))"
    }

    private var guestMergeTraceKey: String? {
        guard let guestInsightReport else { return nil }
        let serverSummary = guestIntelligenceStore.summary(
            for: reservation.remoteID,
            dateKey: reservation.reservationDate
        )
        let serverAnswered = guestIntelligenceStore.hasServerAnswer(
            for: reservation.remoteID,
            dateKey: reservation.reservationDate
        )
        return GuestHistorySemantics.mergePresentationTaskKey(
            surface: "detail",
            guestName: reservation.guestName,
            localReport: guestInsightReport,
            serverSummary: serverSummary,
            serverAnswered: serverAnswered,
            profilePack: guestIntelligenceStore.profilePack(for: reservation.remoteID)
        )
    }

    private func mergedRegularityLevel(for report: GuestInsightReport) -> GuestRegularityLevel? {
        let serverSummary = guestIntelligenceStore.summary(
            for: reservation.remoteID,
            dateKey: reservation.reservationDate
        )
        let serverAnswered = guestIntelligenceStore.hasServerAnswer(
            for: reservation.remoteID,
            dateKey: reservation.reservationDate
        )
        return GuestHistorySemantics.mergedRegularityLevel(
            localReport: report,
            serverSummary: serverSummary,
            serverAnswered: serverAnswered,
            profilePack: guestIntelligenceStore.profilePack(for: reservation.remoteID)
        )
    }

    private var guestInsightCacheKey: ReservationDetailGuestInsightCacheKey {
        ReservationDetailGuestInsightCacheKey(
            selectedReservation: reservation,
            reservations: guestInsightHistoryPool,
            guestIntelligenceStamp: "\(guestIntelligenceStore.cacheStamp(for: reservation.reservationDate))-\(guestIntelligenceStore.profileCacheStamp(for: reservation.remoteID))"
        )
    }

    // MARK: - Staff Action Routing

    // View sends staff intent only; controller owns network and cache writes.
    private func handleAction(_ action: ReservationHostAction) {
        if action == .assignTable {
            tableAssignmentReservation = reservation
        } else if action == .confirmOnly {
            Task {
                await beginPrimaryConfirmFlow(source: "primary_button")
            }
        } else if action == .cancel || action == .noShow || action == .confirmAndSendEmail {
            pendingAction = action
        } else {
            Task {
                await perform(action)
            }
        }
    }

    // Intent: Converts detail actions into controller calls.
    // Confirm opens the manual Mail flow when an email exists; no-email call-ins PATCH confirmed.
    private func perform(_ action: ReservationHostAction) async {
        pendingAction = nil
        isSavingQuickAction = true
        errorMessage = nil

        defer {
            isSavingQuickAction = false
        }

        switch action {
        case .confirmOnly:
            await beginPrimaryConfirmFlow(source: "legacy_action")
        case .confirmAndSendEmail:
            guard ReservationEmailWorkflow.isBackendConfirmEmailEnabled else { return }
            await controller.confirmReservation(reservation: reservation, context: modelContext)
            ReservationHaptics.success()
        case .seat:
            await controller.updateStatus(reservation: reservation, status: .seated, context: modelContext)
            if reservation.statusValue == .noShow {
                WorkflowCleanupTrace.log(
                    "NO_SHOW_FLOW_TRACE",
                    fields: [
                        "reservation": "\(reservation.remoteID)",
                        "action": "seat_after_no_show",
                        "result": "success"
                    ]
                )
            }
            ReservationHaptics.success()
        case .complete:
            await controller.updateStatus(reservation: reservation, status: .completed, context: modelContext)
            ReservationHaptics.success()
        case .cancel:
            await controller.updateStatus(reservation: reservation, status: .cancelled, context: modelContext)
            ReservationHaptics.warning()
        case .noShow:
            await controller.updateStatus(reservation: reservation, status: .noShow, context: modelContext)
            WorkflowCleanupTrace.log(
                "NO_SHOW_FLOW_TRACE",
                fields: [
                    "reservation": "\(reservation.remoteID)",
                    "action": "mark_no_show",
                    "result": "success"
                ]
            )
            ReservationHaptics.warning()
        case .assignTable:
            tableAssignmentReservation = reservation
        }
    }

    private func beginPrimaryConfirmFlow(source: String) async {
        ConfirmFlowTrace.log(
            reservationID: reservation.remoteID,
            phase: "start",
            fields: [
                "source": source,
                "status": reservation.status,
                "emailPresent": "\(reservation.hasUsableConfirmationEmail)"
            ]
        )

        switch reservation.statusValue {
        case .completed:
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "blocked",
                fields: ["reason": "terminal_status"]
            )
            guestManageLinkMessage = "Completed reservations cannot be confirmed."
            ReservationHaptics.warning()
            return
        case .cancelled:
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "blocked",
                fields: ["reason": "terminal_status"]
            )
            guestManageLinkMessage = "Cancelled reservations cannot be confirmed."
            ReservationHaptics.warning()
            return
        case .noShow:
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "blocked",
                fields: ["reason": "terminal_status"]
            )
            guestManageLinkMessage = "No-show reservations cannot be confirmed from the normal confirmation flow."
            ReservationHaptics.warning()
            return
        case .confirmed:
            guestManageLinkMessage = "Already confirmed."
            ReservationHaptics.selection()
            return
        default:
            break
        }

        if reservation.hasUsableConfirmationEmail {
            if ReservationEmailWorkflow.isBackendConfirmEmailEnabled {
                await controller.confirmReservation(reservation: reservation, context: modelContext)
                ReservationHaptics.success()
            } else if emailAutomationSettingsStore.settings.manualMailFallbackEnabled {
                await sendGuestConfirmationEmail(source: source)
            } else {
                guestManageLinkMessage = "Manual Mail fallback is off."
                ReservationHaptics.warning()
            }
        } else {
            await markConfirmedWithoutEmail()
        }
    }

    private func markConfirmedWithoutEmail() async {
        guard !isSavingQuickAction else { return }
        isSavingQuickAction = true
        errorMessage = nil
        defer { isSavingQuickAction = false }

        ConfirmFlowTrace.log(
            reservationID: reservation.remoteID,
            phase: "patch_confirmed",
            fields: ["mode": "without_email"]
        )
        await controller.updateStatus(reservation: reservation, status: .confirmed, context: modelContext)
        ConfirmFlowTrace.log(
            reservationID: reservation.remoteID,
            phase: "patch_confirmed",
            fields: ["result": "success"]
        )
        ConfirmFlowTrace.log(
            reservationID: reservation.remoteID,
            phase: "completed",
            fields: ["result": "sent_and_confirmed"]
        )
        guestManageLinkMessage = "Marked confirmed without email."
        ReservationHaptics.success()
    }

    // Intent: Hide a mistaken manual entry without hard-deleting server data.
    // Network: PATCH /managed-reservations/{id} is_hidden=true.
    private func hideWrongManualEntry() async {
        isSavingQuickAction = true
        errorMessage = nil

        defer {
            isSavingQuickAction = false
        }

        do {
            _ = try await controller.hideWrongEntry(
                reservation: reservation,
                context: modelContext
            )
            ReservationHaptics.warning()
        } catch {
            errorMessage = "Could not hide this entry. Please retry before relying on service lists."
            ReservationHaptics.warning()
        }
    }

    // Intent: Restores a hidden server row from detail.
    // Network: PATCH /managed-reservations/{id} is_hidden=false.
    private func restoreHiddenReservation() async {
        isSavingQuickAction = true
        errorMessage = nil

        defer {
            isSavingQuickAction = false
        }

        do {
            _ = try await controller.restoreHiddenReservation(
                reservation: reservation,
                context: modelContext
            )
            ReservationHaptics.success()
        } catch {
            errorMessage = "Could not restore this reservation. Please retry."
            ReservationHaptics.warning()
        }
    }

    // Intent: Prepares a self-service URL for manual confirmation email copy.
    // Network: POST /managed-reservations/{id}/guest-manage-link.
    // Email: Does not send email and does not mark confirmation email as sent.
    private func generateGuestManageLink() async {
        guard !isGeneratingGuestManageLink else { return }

        isGeneratingGuestManageLink = true
        errorMessage = nil
        guestManageLinkMessage = nil

        defer {
            isGeneratingGuestManageLink = false
        }

        do {
            let link = try await controller.generateGuestManageLink(reservation: reservation)
            guestManageLink = link
            UIPasteboard.general.string = link.url
            guestManageLinkMessage = "Guest link copied. Use it in the manual confirmation draft."
            ReservationHaptics.success()
        } catch {
            errorMessage = "Could not generate a guest link. Please retry."
            ReservationHaptics.warning()
        }
    }

    private func sendGuestConfirmationEmail(source: String = "more_menu") async {
        guard !isGeneratingGuestManageLink else { return }

        switch reservation.statusValue {
        case .completed:
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "blocked",
                fields: ["reason": "terminal_status"]
            )
            guestManageLinkMessage = "Completed reservations cannot be confirmed."
            ReservationHaptics.warning()
            return
        case .cancelled:
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "blocked",
                fields: ["reason": "terminal_status"]
            )
            guestManageLinkMessage = "Cancelled reservations cannot be confirmed."
            ReservationHaptics.warning()
            return
        case .noShow:
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "blocked",
                fields: ["reason": "terminal_status"]
            )
            guestManageLinkMessage = "No-show reservations cannot be confirmed from the normal confirmation flow."
            ReservationHaptics.warning()
            return
        default:
            break
        }

        let email = reservation.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "blocked",
                fields: ["reason": "missing_email"]
            )
            errorMessage = "Add a guest email in Edit before sending confirmation."
            ReservationHaptics.warning()
            return
        }

        isGeneratingGuestManageLink = true
        errorMessage = nil
        guestManageLinkMessage = nil

        defer {
            isGeneratingGuestManageLink = false
        }

        do {
            ConfirmFlowTrace.log(reservationID: reservation.remoteID, phase: "guest_link_start")
            let link = try await controller.generateGuestManageLink(
                reservation: reservation,
                announceNotice: false
            )
            guestManageLink = link

            guard let draft = GuestConfirmationMailPresenter.draft(
                reservation: reservation,
                manageLink: link
            ) else {
                errorMessage = "Add a guest email in Edit before sending confirmation."
                ReservationHaptics.warning()
                return
            }

            await recordDraftCreated(draft)

            if GuestConfirmationMailPresenter.canSendMail() {
                guestConfirmationMailDraft = draft
                ConfirmFlowTrace.log(reservationID: reservation.remoteID, phase: "mail_presented")
                guestManageLinkMessage = "This opens Mail. The reservation is marked confirmed only after the email is sent."
                ReservationHaptics.success()
            } else if GuestConfirmationMailPresenter.openMailtoFallback(draft: draft) {
                ConfirmFlowTrace.log(reservationID: reservation.remoteID, phase: "mail_presented")
                guestManageLinkMessage = "Opened Mail with a plain-text confirmation draft. Reservation is not confirmed until staff records it as sent."
                ReservationHaptics.success()
            } else {
                UIPasteboard.general.string = ManualEmailDraftService.confirmationDraft(
                    reservation: reservation,
                    manageLink: link
                )
                guestManageLinkMessage = "Mail is not set up. Draft copied. Reservation was not confirmed."
                ReservationHaptics.success()
            }
        } catch {
            errorMessage = "Could not prepare the confirmation email. Please retry."
            ReservationHaptics.warning()
        }
    }

    private func copyGuestManageLink() {
        guard let url = guestManageLink?.url else { return }
        UIPasteboard.general.string = url
        guestManageLinkMessage = "Guest link copied. Paste it into your email if needed."
        ReservationHaptics.success()
    }

    private func copyGuestConfirmationDraft() {
        guard let guestManageLink else { return }
        UIPasteboard.general.string = ManualEmailDraftService.confirmationDraft(
            reservation: reservation,
            manageLink: guestManageLink
        )
        if let draft = GuestConfirmationMailPresenter.draft(reservation: reservation, manageLink: guestManageLink) {
            Task { await recordDraftCreated(draft) }
        }
        guestManageLinkMessage = "Plain confirmation draft copied. Record sent after staff sends it."
        ReservationHaptics.success()
    }

    private func recordManualConfirmationSentFromCurrentDraft() async {
        guard let guestManageLink,
              let draft = GuestConfirmationMailPresenter.draft(
                  reservation: reservation,
                  manageLink: guestManageLink
              ) else {
            errorMessage = "Prepare a confirmation draft before recording it as sent."
            ReservationHaptics.warning()
            return
        }

        await finalizeManualConfirmationAfterSend(draft: draft)
    }

    private func handleGuestConfirmationMailFinished(
        _ result: MFMailComposeResult,
        draft: GuestConfirmationMailPresenter.Draft
    ) {
        guestConfirmationMailDraft = nil

        switch result {
        case .sent:
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "mail_result",
                fields: ["result": "sent"]
            )
            Task {
                await finalizeManualConfirmationAfterSend(draft: draft)
            }
        case .failed:
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "mail_result",
                fields: ["result": "failed"]
            )
            Task {
                await recordManualConfirmationFailure(draft: draft)
            }
        case .cancelled:
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "mail_result",
                fields: ["result": "cancelled"]
            )
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "completed",
                fields: ["result": "cancelled_no_change"]
            )
            guestManageLinkMessage = "Email was not sent. Reservation was not confirmed."
        case .saved:
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "mail_result",
                fields: ["result": "saved"]
            )
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "completed",
                fields: ["result": "cancelled_no_change"]
            )
            guestManageLinkMessage = "Email was not sent. Reservation was not confirmed."
        @unknown default:
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "mail_result",
                fields: ["result": "failed"]
            )
            guestManageLinkMessage = "Email was not sent. Reservation was not confirmed."
        }
    }

    private func recordDraftCreated(_ draft: GuestConfirmationMailPresenter.Draft) async {
        do {
            _ = try await controller.recordManualConfirmationDraftCreated(
                reservation: reservation,
                toEmail: draft.recipients.first,
                subject: draft.subject,
                bodySnapshot: draft.logBodySnapshot
            )
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "manual_email_log",
                fields: ["status": "draft_created"]
            )
        } catch {
            if !error.isOfflineLike {
                guestManageLinkMessage = "Draft ready. Could not record draft-created activity yet."
            }
        }
    }

    private func finalizeManualConfirmationAfterSend(draft: GuestConfirmationMailPresenter.Draft) async {
        guard !isSavingQuickAction else { return }
        isSavingQuickAction = true
        defer { isSavingQuickAction = false }

        do {
            _ = try await controller.recordManualConfirmationSent(
                reservation: reservation,
                toEmail: draft.recipients.first,
                subject: draft.subject,
                bodySnapshot: draft.logBodySnapshot,
                context: modelContext
            )
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "manual_email_log",
                fields: ["status": "manual_sent"]
            )
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "patch_confirmed"
            )
            _ = try await controller.updateReservation(
                id: reservation.remoteID,
                request: ReservationUpdateRequest(status: .confirmed),
                context: modelContext,
                action: "confirm_after_manual_email"
            )
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "patch_confirmed",
                fields: ["result": "success"]
            )
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "completed",
                fields: ["result": "sent_and_confirmed"]
            )
            guestManageLinkMessage = "Confirmation sent and recorded."
            ReservationHaptics.success()
        } catch {
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "patch_confirmed",
                fields: ["result": "failed"]
            )
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "completed",
                fields: ["result": "failed_no_change"]
            )
            errorMessage = "Staff may have sent email from Mail, but confirmation was not fully recorded. Check details and retry if needed."
            ReservationHaptics.warning()
        }
    }

    // Guest message drafts: template default; local model when Host Intelligence setting is on.
    private func generateGuestMessageDraft(kind: GuestMessageDraftKind) {
        guard !guestCommunicationCoordinator.isDrafting else { return }

        Task {
            guestCommunicationCoordinator.clearStaffError()
            let draft = await guestCommunicationCoordinator.draftGuestMessage(
                kind: kind,
                reservation: reservation,
                manageURL: guestManageLink?.url
            )
            draftReviewContext = GuestMessageDraftReviewContext(kind: kind, draft: draft)
            ReservationHaptics.selection()
        }
    }

    private func sendDraftEmail(_ approved: ApprovedGuestMessageDraft) {
        guard let mailDraft = guestCommunicationCoordinator.makeEmailComposerDraft(
            reservation: reservation,
            approved: approved,
            manageURL: guestManageLink?.url
        ) else {
            ReservationHaptics.warning()
            return
        }

        draftReviewContext = nil
        pendingGuestMessageMailKind = approved.kind

        Task { @MainActor in
            await Task.yield()

            if GuestConfirmationMailPresenter.canSendMail() {
                guestMessageMailDraft = mailDraft
                ReservationHaptics.selection()
            } else if GuestConfirmationMailPresenter.openMailtoFallback(draft: mailDraft) {
                pendingGuestMessageMailKind = nil
                ReservationHaptics.selection()
            } else {
                pendingGuestMessageMailKind = nil
                guestCommunicationCoordinator.copyEmailDraft(approved)
                guestCommunicationCoordinator.noteStaffError(
                    GuestCommunicationCoordinator.StaffMessage.mailUnavailableCopied
                )
                ReservationHaptics.warning()
            }
        }
    }

    private func sendDraftText(_ approved: ApprovedGuestMessageDraft) {
        guard let textDraft = guestCommunicationCoordinator.makeTextComposerDraft(
            reservation: reservation,
            approved: approved
        ) else {
            ReservationHaptics.warning()
            return
        }

        draftReviewContext = nil

        Task { @MainActor in
            await Task.yield()

            if GuestTextMessagePresenter.canSendText() {
                guestMessageTextDraft = textDraft
                ReservationHaptics.selection()
            } else if GuestTextMessagePresenter.openSMSFallback(draft: textDraft) {
                ReservationHaptics.selection()
            } else {
                guestCommunicationCoordinator.copyTextDraft(approved)
                guestCommunicationCoordinator.noteStaffError(
                    GuestCommunicationCoordinator.StaffMessage.messagesUnavailableCopied
                )
                ReservationHaptics.warning()
            }
        }
    }

    private func copyDraftEmail(_ approved: ApprovedGuestMessageDraft) {
        guestCommunicationCoordinator.copyEmailDraft(approved)
        ReservationHaptics.success()
    }

    private func handleGuestMessageMailFinished(
        _ result: MFMailComposeResult,
        draft: GuestConfirmationMailPresenter.Draft
    ) {
        guestMessageMailDraft = nil
        let kind = pendingGuestMessageMailKind
        pendingGuestMessageMailKind = nil

        guard result == .sent, let kind else { return }

        let templateKind = kind.emailTemplateKind
        guard templateKind.backendLogEmailType == nil else { return }

        GuestCommunicationTrace.manualEmailLogSkipped(
            reservationID: reservation.remoteID,
            type: templateKind
        )
    }

    private func copyDraftText(_ approved: ApprovedGuestMessageDraft) {
        guestCommunicationCoordinator.copyTextDraft(approved)
        ReservationHaptics.success()
    }

    private func recordManualConfirmationFailure(draft: GuestConfirmationMailPresenter.Draft) async {
        do {
            _ = try await controller.recordManualConfirmationFailed(
                reservation: reservation,
                toEmail: draft.recipients.first,
                subject: draft.subject,
                bodySnapshot: draft.logBodySnapshot,
                errorMessage: "Mail composer reported failure."
            )
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "manual_email_log",
                fields: ["status": "manual_failed"]
            )
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "completed",
                fields: ["result": "failed_no_change"]
            )
            guestManageLinkMessage = "Email failed. Reservation was not confirmed."
        } catch {
            ConfirmFlowTrace.log(
                reservationID: reservation.remoteID,
                phase: "completed",
                fields: ["result": "failed_no_change"]
            )
            guestManageLinkMessage = "Mail failed. Could not record failure on the server."
        }
        ReservationHaptics.warning()
    }
}

private struct GuestMessageDraftReviewContext: Identifiable {
    let id = UUID()
    let kind: GuestMessageDraftKind
    let draft: GuestMessageDraft
}

private struct ReservationDetailGuestInsightCacheKey: Hashable {
    let selectedID: Int
    let visibleCount: Int
    let maxLastSyncedAt: Date?
    let maxUpdatedAt: Date?
    let guestIntelligenceStamp: String

    init(
        selectedReservation: ReservationRecord,
        reservations: [ReservationRecord],
        guestIntelligenceStamp: String = ""
    ) {
        selectedID = selectedReservation.remoteID
        let visible = reservations.filter { !$0.isHidden }
        visibleCount = visible.count
        maxLastSyncedAt = visible.map(\.lastSyncedAt).max()
        maxUpdatedAt = visible.compactMap(\.updatedAt).max()
        self.guestIntelligenceStamp = guestIntelligenceStamp
    }
}

// MARK: - Service Load Card

private struct ReservationServiceLoadCard: View {
    let reservation: ReservationRecord
    let sameDayReservations: [ReservationRecord]

    private var slots: [ServiceTimelineSlot] {
        ServiceTimeline.slots(from: sameDayReservations)
    }

    private var highlightHour: Int? {
        Int(reservation.reservationTime.prefix(2))
    }

    private var summaryText: String {
        let expected = sameDayReservations.filter(\.isExpectedGuest)
        let guests = expected.reduce(0) { $0 + $1.partySize }
        let reservationWord = expected.count == 1 ? "reservation" : "reservations"
        return "\(expected.count) \(reservationWord) · \(guests) guests on \(reservation.displayDate)"
    }

    var body: some View {
        DetailSectionCard(title: "Service load", systemImage: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(TryzubColors.primaryControl)
                        .frame(width: 9, height: 9)
                    Text("This reservation's hour")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                ServiceLoadChart(slots: slots, highlightHour: highlightHour, height: 130)

                Text(summaryText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

// MARK: - Guest Insights Entry

private struct GuestInsightsPreviewCard: View {
    let report: GuestInsightReport
    let presentation: GuestHistorySemantics.DetailInsightPresentation
    let profilePreview: GuestInsightsProfilePresentation.DetailPreview?
    let mergedRegularity: GuestRegularityLevel?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "person.text.rectangle")
                .font(.headline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray6), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Guest insight")
                        .font(.headline.weight(.medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if let profilePreview {
                    Text(profilePreview.title)
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(profilePreview.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(presentation.historyTitle)
                        .font(.subheadline.weight(.semibold))

                    Text(presentation.historyDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(presentation.supplementalLines.enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.title)
                            .font(.caption.weight(.semibold))
                        Text(line.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                FlowLayout(spacing: 7) {
                    if let mergedRegularity {
                        GuestRegularityBadge(level: mergedRegularity)
                    }
                    if !report.staffMentionHistory.isEmpty {
                        DetailPill(label: "Staff notes", systemImage: "note.text", tint: .secondary)
                    }
                    if !report.possibleMatches.isEmpty {
                        DetailPill(label: "Possible match", systemImage: "person.2", tint: .secondary)
                    }
                }
                .lineLimit(1)
            }
        }
        // Flat inside DetailSectionCard — no nested background/border.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Reservation Hero Card

private enum DetailHeroLayout {
    case standard
    case compact
}

private struct DetailHeroCard: View {
    let header: ReservationDetailPresentation.Header
    var layout: DetailHeroLayout = .standard
    @Environment(\.detailGridEqualHeight) private var fillsAvailableHeight

    var body: some View {
        Group {
            switch layout {
            case .standard:
                standardHero
            case .compact:
                compactHero
            }
        }
        .padding(layout == .compact ? 16 : 18)
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsAvailableHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var standardHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            heroTimeRow(timeFont: .system(.largeTitle, design: .rounded, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text(header.guestName)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                DetailHeroMetadataLine(
                    partyText: header.partyText,
                    tableText: header.tableText,
                    sourceText: header.sourceText
                )
            }
        }
    }

    private var compactHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            heroTimeRow(timeFont: .system(.title, design: .rounded, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(header.guestName)
                    .font(.headline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                DetailHeroMetadataLine(
                    partyText: header.partyText,
                    tableText: header.tableText,
                    sourceText: header.sourceText
                )
            }
        }
    }

    private func heroTimeRow(timeFont: Font) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(header.timeText)
                    .font(timeFont)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(header.dateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            ReservationStatusBadge(status: header.status)
        }
    }
}

private struct DetailHeroMetadataLine: View {
    let partyText: String
    let tableText: String
    let sourceText: String

    var body: some View {
        FlowLayout(spacing: 8) {
            DetailMetadataItem(systemImage: "person.2", text: partyText)
            DetailMetadataItem(systemImage: "table.furniture", text: tableText)
            DetailMetadataItem(systemImage: "tray.and.arrow.down", text: sourceText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailMetadataItem: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Reservation Action Bar

private struct DetailActionBar: View {
    let reservation: ReservationRecord
    let capabilities: AppCapabilities
    let isBusy: Bool
    let isNetworkDegraded: Bool
    let isGeneratingGuestManageLink: Bool
    let hasGuestManageLink: Bool
    let onAction: (ReservationHostAction) -> Void
    var onSeatRequiresTableChoice: (() -> Void)? = nil
    let onEdit: () -> Void
    let onSendGuestConfirmationEmail: (() -> Void)?
    let onRecordManualConfirmationSent: (() -> Void)?
    let onGenerateGuestManageLink: (() -> Void)?
    let onCopyGuestManageLink: (() -> Void)?
    let onCopyConfirmationDraft: (() -> Void)?
    let onHideWrongEntry: (() -> Void)?
    let onRestoreHidden: (() -> Void)?

    private var policy: ReservationHostActionPolicy {
        ReservationHostActionPolicy(
            reservation: reservation,
            capabilities: capabilities,
            surface: .detail
        )
    }

    var body: some View {
        DetailSectionCard(title: "Actions", systemImage: "hand.tap.fill") {
            VStack(alignment: .leading, spacing: 12) {
                if isNetworkDegraded {
                    Label("Offline — edits require internet.", systemImage: "wifi.slash")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(TryzubColors.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if showsPendingConfirmationButtons {
                    pendingConfirmationActions
                } else {
                    ReservationActionButtons(
                        reservation: reservation,
                        capabilities: capabilities,
                        compact: false,
                        includeSecondary: false,
                        primaryFillsWidth: true,
                        actionSurface: .detail,
                        isBusy: isBusy || isNetworkDegraded,
                        onAction: onAction,
                        onSeatRequiresTableChoice: onSeatRequiresTableChoice
                    )
                }

                HStack(spacing: 10) {
                    secondaryButton(title: "Edit", systemImage: "pencil") {
                        onEdit()
                    }
                    .disabled(!capabilities.canEditReservationDetails || isNetworkDegraded)

                    if showsMoreMenu {
                        moreMenu
                            .disabled(isNetworkDegraded)
                    }
                }
            }
        }
    }

    private var showsPendingConfirmationButtons: Bool {
        policy.detailPrimaryAction == .confirmOnly
    }

    private var pendingConfirmationActions: some View {
        VStack(spacing: 10) {
            pendingConfirmationButton(
                title: primaryConfirmationTitle,
                systemImage: primaryConfirmationSystemImage,
                isPrimary: true
            ) {
                onAction(.confirmOnly)
            }
        }
    }

    private var primaryConfirmationTitle: String {
        if reservation.hasUsableConfirmationEmail {
            return ReservationEmailWorkflow.isBackendConfirmEmailEnabled ? "Confirm & Send" : "Confirm Manually"
        }
        return ReservationHostAction.confirmOnly.shortTitle
    }

    private var primaryConfirmationSystemImage: String {
        reservation.hasUsableConfirmationEmail ? "envelope.badge" : ReservationHostAction.confirmOnly.systemImage
    }

    @ViewBuilder
    private func pendingConfirmationButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let label = Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity)

        Group {
            if isPrimary {
                Button(action: action) { label }
                    .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .disabled(isBusy || isNetworkDegraded)
    }

    private func secondaryButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var moreMenu: some View {
        Menu {
            ForEach(policy.detailSecondaryActions) { action in
                Button(role: action.role) {
                    onAction(action)
                } label: {
                    Label(action.fullTitle, systemImage: action.systemImage)
                }
            }

            if !policy.detailSecondaryActions.isEmpty,
               hasAdminActions {
                Divider()
            }

            if let onSendGuestConfirmationEmail {
                Button {
                    onSendGuestConfirmationEmail()
                } label: {
                    Label(
                        isGeneratingGuestManageLink ? "Preparing draft" : "Confirm Manually",
                        systemImage: "envelope"
                    )
                }
                .disabled(isGeneratingGuestManageLink)
            }

            if let onGenerateGuestManageLink {
                Button {
                    onGenerateGuestManageLink()
                } label: {
                    Label(
                        isGeneratingGuestManageLink ? "Generating guest link" : "Manual guest link",
                        systemImage: "link.badge.plus"
                    )
                }
                .disabled(isGeneratingGuestManageLink)
            }

            if hasGuestManageLink, let onCopyGuestManageLink {
                Button {
                    onCopyGuestManageLink()
                } label: {
                    Label("Copy guest link", systemImage: "doc.on.doc")
                }
            }

            if hasGuestManageLink, let onCopyConfirmationDraft {
                Button {
                    onCopyConfirmationDraft()
                } label: {
                    Label("Copy plain draft", systemImage: "doc.plaintext")
                }
            }

            if hasGuestManageLink, let onRecordManualConfirmationSent {
                Button {
                    onRecordManualConfirmationSent()
                } label: {
                    Label("Record sent", systemImage: "envelope.badge")
                }
            }

            if (onSendGuestConfirmationEmail != nil || onRecordManualConfirmationSent != nil || onGenerateGuestManageLink != nil || onCopyGuestManageLink != nil || onCopyConfirmationDraft != nil),
               onHideWrongEntry != nil || onRestoreHidden != nil {
                Divider()
            }

            if let onHideWrongEntry {
                Button(role: .destructive) {
                    onHideWrongEntry()
                } label: {
                    Label("Hide wrong entry", systemImage: "archivebox")
                }
            }

            if let onRestoreHidden {
                Button {
                    onRestoreHidden()
                } label: {
                    Label("Restore to lists", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isBusy || isGeneratingGuestManageLink)
    }

    private var showsMoreMenu: Bool {
        !policy.detailSecondaryActions.isEmpty || hasAdminActions
    }

    private var hasAdminActions: Bool {
        onSendGuestConfirmationEmail != nil
            || onRecordManualConfirmationSent != nil
            || onGenerateGuestManageLink != nil
            || onCopyGuestManageLink != nil
            || onCopyConfirmationDraft != nil
            || onHideWrongEntry != nil
            || onRestoreHidden != nil
    }
}

// MARK: - Shared Detail Components

private struct DetailGridEqualHeightKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var detailGridEqualHeight: Bool {
        get { self[DetailGridEqualHeightKey.self] }
        set { self[DetailGridEqualHeightKey.self] = newValue }
    }
}

private struct DetailGridColumn<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .environment(\.detailGridEqualHeight, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DetailSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content
    @Environment(\.detailGridEqualHeight) private var fillsAvailableHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)

            content

            if fillsAvailableHeight {
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsAvailableHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct DetailDataRow: View {
    let title: String
    let value: String
    var allowsWrap = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DetailContactRow: View {
    let title: String
    let value: String
    let url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let url {
                Link(destination: url) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(value)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Image(systemName: title == "Phone" ? "phone.fill" : "envelope.fill")
                            .font(.footnote)
                            .padding(.top, 2)
                    }
                    .foregroundStyle(TryzubColors.info)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(value)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct DetailPlainLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailWarningCard: View {
    let title: String
    let message: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.medium))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct DetailPill: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
    }
}

// MARK: - DetailNoteRow

private enum DetailStaffNotesDisplay {
    static func normalized(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var kept: [String] = []
        for line in lines {
            let normalized = line.lowercased()
            var skip = false

            for index in kept.indices {
                let existing = kept[index]
                let existingNormalized = existing.lowercased()
                if existingNormalized == normalized {
                    skip = true
                    break
                }
                if existingNormalized.contains(normalized), existing.count >= line.count {
                    skip = true
                    break
                }
                if normalized.contains(existingNormalized), line.count > existing.count {
                    kept[index] = line
                    skip = true
                    break
                }
            }

            if !skip {
                kept.append(line)
            }
        }

        return kept.isEmpty ? nil : kept.joined(separator: "\n")
    }
}

private struct DetailNoteRow: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(noteLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var noteLabel: String {
        switch label.lowercased() {
        case "guest":   return "Guest note"
        case "staff":   return "Staff note"
        case "manager": return "Manager note"
        case "kitchen": return "Kitchen note"
        case "bar":     return "Bar note"
        case "setup":   return "Setup note"
        case "deposit": return "Deposit note"
        case "preorder": return "Preorder note"
        default:        return label
        }
    }
}

// MARK: - ReservationImportantFlags

// MARK: - Attachment sub-views (Phase 5)

/// Single attachment row: thumbnail, label, date, OCR status, signal pills, delete swipe.
private struct AttachmentRow: View {
    let record: ReservationAttachmentRecord
    /// Signals already computed for this attachment by the parent view's recomputeNoteSignals().
    let signals: [ReservationSignal]
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 10) {
            thumbnailView
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: record.label.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(record.label.rawValue)
                        .font(.subheadline.weight(.semibold))
                }
                if !signals.isEmpty {
                    attachmentSignalPills
                } else {
                    Text(record.label.reviewInstruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(record.displayDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if AttachmentFeatureFlag.ocrEnabled {
                        ocrStatusLabel
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onAppear {
            if thumbnail == nil {
                thumbnail = AttachmentFileStore.thumbnail(filename: record.filename)
            }
        }
    }

    @ViewBuilder
    private var attachmentSignalPills: some View {
        FlowLayout(spacing: 4) {
            ForEach(signals.prefix(3)) { signal in
                Text(signal.title)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(signalPillColor(signal.priority).opacity(0.14))
                    .foregroundStyle(signalPillColor(signal.priority))
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var ocrStatusLabel: some View {
        // Show only when OCR ran and found text. No "Reading..." — OCR is a silent background benefit.
        if record.ocrRanAt != nil, record.extractedText != nil {
            Label("Text read", systemImage: "doc.text.magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func signalPillColor(_ priority: SignalPriority) -> Color {
        switch priority {
        case .critical: return .red
        case .high:     return .orange
        case .medium:   return .blue
        case .low, .info: return .secondary
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let image = thumbnail {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.systemFill))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: record.label.systemImage)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

/// Full-screen attachment preview with a close button.
private struct AttachmentPreviewScreen: View {
    let record: ReservationAttachmentRecord
    let onDismiss: () -> Void

    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                    }
                    .background(Color.black)
                } else {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
            .navigationTitle(record.label.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss() }
                }
            }
            .onAppear {
                image = AttachmentFileStore.load(filename: record.filename)
            }
        }
    }
}

// MARK: - Deterministic importance flags

/// Deterministic flag list shown in the "Important" card. No model, no fetch.
/// Reads only the fields that are already in the reservation record.
struct ReservationImportantFlag: Identifiable {
    let id: String
    let title: String
    let detail: String?
    let icon: String
    let tint: Color
}

enum ReservationImportantFlags {
    static func make(reservation: ReservationRecord) -> [ReservationImportantFlag] {
        var flags: [ReservationImportantFlag] = []

        // No table picked (only relevant for not-yet-complete reservations).
        if !reservation.hasTableAssignment,
           reservation.statusValue != .cancelled,
           reservation.statusValue != .noShow,
           reservation.statusValue != .completed {
            flags.append(ReservationImportantFlag(
                id: "no_table",
                title: "No table picked",
                detail: nil,
                icon: "chair",
                tint: .orange
            ))
        }

        // Large party.
        if reservation.partySize >= 7 {
            flags.append(ReservationImportantFlag(
                id: "large_party",
                title: "Large party · \(reservation.partySize) guests",
                detail: reservation.tableName.flatMap { $0.nilIfBlank }.map { "Table: \($0)" },
                icon: "person.3",
                tint: .blue
            ))
        }

        // Note-based signals (dietary, deposit, preorder, accessibility) are handled by
        // NoteSignalAnalyzer and shown in NOTE SIGNALS — not duplicated here.
        // IMPORTANT keeps only operational flags: no table, large party.

        return flags
    }
}

// MARK: - Detail String Helpers

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        let trimmed = trimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Reservation Detail") {
    NavigationStack {
        ReservationDetailView(
            reservation: ReservationPreviewData.sampleRecord,
            environment: AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer)
        )
    }
    .modelContainer(ReservationPreviewData.previewContainer)
    .environmentObject(
        ReservationsController.preview(
            environment: AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer)
        )
    )
    .environmentObject(HiddenReservationsStore())
    .environmentObject(HostReservationOpenIntentStore())
    .environmentObject(HostTableConfigStore())
    .environmentObject(HostIntelligenceSettingsStore())
    .environmentObject(GuestIntelligenceStore(apiClient: ReservationsAPIClient.preview))
    .environmentObject(FloorPlanStore(apiClient: ReservationsAPIClient.preview))
    .environmentObject(ReservationActivityStore(apiClient: ReservationsAPIClient.preview))
    .environmentObject(EmailAutomationSettingsStore.shared)
}
#endif
