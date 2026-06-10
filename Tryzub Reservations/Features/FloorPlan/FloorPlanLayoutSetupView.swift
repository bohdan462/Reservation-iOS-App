//
//  FloorPlanLayoutSetupView.swift
//  Tryzub Reservations
//

import SwiftUI

enum FloorPlanTableSizePreset: Int, CaseIterable, Identifiable {
    case oneCube = 1
    case twoCubes = 2
    case threeCubes = 3

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .oneCube:
            return "1 cube"
        case .twoCubes:
            return "2 cubes"
        case .threeCubes:
            return "3 cubes"
        }
    }

    var capacityLine: String {
        switch self {
        case .oneCube:
            return "Fits 1–4 guests"
        case .twoCubes:
            return "Fits 4–6 guests"
        case .threeCubes:
            return "Fits 6–8 guests"
        }
    }

    var widthUnits: Int { rawValue }
    var heightUnits: Int { 1 }

    var minCapacity: Int {
        switch self {
        case .oneCube: return 1
        case .twoCubes: return 4
        case .threeCubes: return 6
        }
    }

    var maxCapacity: Int {
        switch self {
        case .oneCube: return 4
        case .twoCubes: return 6
        case .threeCubes: return 8
        }
    }
}

struct FloorPlanLayoutDraftTable: Identifiable, Equatable {
    var backendID: Int
    var restaurantKey: String
    var tableKey: String
    var label: String
    var x: Int
    var y: Int
    var widthUnits: Int
    var heightUnits: Int
    var minCapacity: Int
    var maxCapacity: Int
    var sortOrder: Int
    var isActive: Bool

    var id: String { tableKey }

    var capacityLine: String {
        "Fits \(minCapacity)–\(maxCapacity) guests"
    }

    func toDTO() -> RestaurantTableDTO {
        RestaurantTableDTO(
            id: backendID,
            restaurantKey: restaurantKey,
            tableKey: tableKey,
            label: label,
            x: x,
            y: y,
            widthUnits: widthUnits,
            heightUnits: heightUnits,
            minCapacity: minCapacity,
            maxCapacity: maxCapacity,
            section: nil,
            sortOrder: sortOrder,
            isActive: isActive,
            createdAt: nil,
            updatedAt: nil
        )
    }

    static func newTable(
        index: Int,
        restaurantKey: String,
        preset: FloorPlanTableSizePreset = .oneCube,
        x: Int = 0,
        y: Int = 0
    ) -> FloorPlanLayoutDraftTable {
        FloorPlanLayoutDraftTable(
            backendID: 0,
            restaurantKey: restaurantKey,
            tableKey: "T\(index)",
            label: "T\(index)",
            x: x,
            y: y,
            widthUnits: preset.widthUnits,
            heightUnits: preset.heightUnits,
            minCapacity: preset.minCapacity,
            maxCapacity: preset.maxCapacity,
            sortOrder: index,
            isActive: true
        )
    }

    static func defaultSeedTables(restaurantKey: String) -> [FloorPlanLayoutDraftTable] {
        [
            newTable(index: 1, restaurantKey: restaurantKey, preset: .oneCube, x: 0, y: 0),
            newTable(index: 2, restaurantKey: restaurantKey, preset: .twoCubes, x: 1, y: 0),
            newTable(index: 3, restaurantKey: restaurantKey, preset: .threeCubes, x: 3, y: 0)
        ]
    }

    var isSavedOnBackend: Bool {
        backendID > 0
    }

    static func fromDTO(_ dto: RestaurantTableDTO) -> FloorPlanLayoutDraftTable {
        FloorPlanLayoutDraftTable(
            backendID: dto.id,
            restaurantKey: dto.restaurantKey,
            tableKey: dto.tableKey,
            label: dto.label,
            x: dto.x,
            y: dto.y,
            widthUnits: dto.widthUnits,
            heightUnits: dto.heightUnits,
            minCapacity: dto.minCapacity,
            maxCapacity: dto.maxCapacity,
            sortOrder: dto.sortOrder,
            isActive: dto.isActive
        )
    }
}

struct FloorPlanLayoutSetupView: View {
    @EnvironmentObject private var controller: ReservationsController
    @ObservedObject var store: FloorPlanStore
    let onDismiss: () -> Void

    @State private var drafts: [FloorPlanLayoutDraftTable] = []
    @State private var selectedTableKey: String?
    @State private var restaurantKey = "tryzub"
    @FocusState private var focusedLabelField: Bool

    private var selectedDraftIndex: Int? {
        guard let selectedTableKey else { return nil }
        return drafts.firstIndex(where: { $0.tableKey == selectedTableKey })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    instructionCard
                    Text("Layout editor v14H")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    saveStateBanner
                    floorMapCard
                    tableChipsSection
                    selectedTableEditor
                    addTableButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(TryzubColors.screenBackground)
            .navigationTitle("Set Up Tables")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveLayout() }
                    }
                    .disabled(store.isSavingLayout || drafts.isEmpty)
                }
            }
            .task {
                store.resetLayoutSaveState()
                await store.loadLayout()
                seedDrafts()
            }
        }
    }

    // MARK: - Sections

    private var instructionCard: some View {
        TryzubSectionCard(title: "Build the floor layout", systemImage: "square.grid.3x3") {
            Text("Build a compact table map once, then staff can assign reservations from the Floor tab.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var saveStateBanner: some View {
        switch store.layoutSaveState {
        case .idle:
            EmptyView()
        case .saving:
            saveBanner(
                text: FloorPlanLayoutSaveCopy.saving,
                icon: "arrow.triangle.2.circlepath",
                tint: TryzubColors.info
            )
        case .saved:
            saveBanner(
                text: FloorPlanLayoutSaveCopy.saved,
                icon: "checkmark.circle.fill",
                tint: TryzubColors.success
            )
        case let .failed(message):
            saveBanner(
                text: message,
                icon: "exclamationmark.triangle.fill",
                tint: TryzubColors.warning
            )
        }
    }

    private func saveBanner(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            if store.layoutSaveState == .saving {
                TryzubSubtleLoadingDot(diameter: 6)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(TryzubColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var floorMapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Floor map", systemImage: "map")
                .font(TryzubTypography.sectionTitle)
                .foregroundStyle(TryzubColors.primaryText)

            FloorPlanSetupGridView(
                drafts: drafts,
                selectedTableKey: selectedTableKey,
                onSelect: { key in
                    selectedTableKey = key
                },
                onPlace: { x, y in
                    placeSelectedTable(x: x, y: y)
                }
            )
            .frame(height: 200)

            Text("Tap a table to edit. Tap empty space to place selected table.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TryzubSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TryzubColors.cardBackground, in: RoundedRectangle(cornerRadius: TryzubSpacing.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TryzubSpacing.cornerRadius, style: .continuous)
                .stroke(TryzubColors.border, lineWidth: 1)
        }
    }

    private var tableChipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tables", systemImage: "table.furniture")
                .font(TryzubTypography.sectionTitle)
                .foregroundStyle(TryzubColors.primaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(drafts) { draft in
                        tableChip(for: draft)
                    }
                }
            }
        }
    }

    private func tableChip(for draft: FloorPlanLayoutDraftTable) -> some View {
        let isSelected = draft.tableKey == selectedTableKey
        return Button {
            selectedTableKey = draft.tableKey
        } label: {
            HStack(spacing: 6) {
                Text(draft.label)
                    .font(.subheadline.weight(.semibold))
                if !draft.isActive {
                    Text("Inactive")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? TryzubColors.primaryControl.opacity(0.22)
                    : TryzubColors.cardBackground
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? TryzubColors.primaryControl : TryzubColors.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(draft.isActive ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectedTableEditor: some View {
        if let index = selectedDraftIndex {
            TryzubSectionCard(title: "Selected table", systemImage: "pencil") {
                selectedTableEditorContent(for: $drafts[index])
            }
        } else if !drafts.isEmpty {
            Text("Tap a table in the grid or list to edit it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    private func selectedTableEditorContent(for draft: Binding<FloorPlanLayoutDraftTable>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(draft.wrappedValue.capacityLine) · X \(draft.wrappedValue.x) · Y \(draft.wrappedValue.y)")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("LABEL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Table label", text: draft.label)
                    .focused($focusedLabelField)
                    .textInputAutocapitalization(.words)
                    .staffFormFieldChrome(isFocused: focusedLabelField)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("SIZE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(FloorPlanTableSizePreset.allCases) { preset in
                        sizeChip(preset: preset, draft: draft)
                    }
                }
            }

            axisControl(title: "X", value: draft.x, range: 0...24)
            axisControl(title: "Y", value: draft.y, range: 0...24)

            Toggle("Active", isOn: draft.isActive)

            if !draft.wrappedValue.isActive, draft.wrappedValue.isSavedOnBackend {
                Label("Inactive", systemImage: "moon.zzz.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            if draft.wrappedValue.isSavedOnBackend {
                if draft.wrappedValue.isActive {
                    Button("Deactivate table", role: .destructive) {
                        deactivateDraft(tableKey: draft.wrappedValue.tableKey)
                    }
                }
            } else {
                Button("Remove draft", role: .destructive) {
                    removeDraft(tableKey: draft.wrappedValue.tableKey)
                }
            }
        }
    }

    private func sizeChip(
        preset: FloorPlanTableSizePreset,
        draft: Binding<FloorPlanLayoutDraftTable>
    ) -> some View {
        let isSelected = draft.wrappedValue.widthUnits == preset.widthUnits
        return Button {
            draft.wrappedValue.widthUnits = preset.widthUnits
            draft.wrappedValue.heightUnits = preset.heightUnits
            draft.wrappedValue.minCapacity = preset.minCapacity
            draft.wrappedValue.maxCapacity = preset.maxCapacity
        } label: {
            Text(preset.shortTitle)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected
                        ? TryzubColors.primaryControl
                        : TryzubColors.cardBackground
                )
                .foregroundStyle(isSelected ? Color.white : TryzubColors.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.clear : TryzubColors.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func axisControl(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(width: 20, alignment: .leading)
            Spacer()
            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(TryzubColors.cardBackground)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(TryzubColors.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(value.wrappedValue <= range.lowerBound)

            Text("\(value.wrappedValue)")
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(minWidth: 28)

            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(TryzubColors.cardBackground)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(TryzubColors.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(value.wrappedValue >= range.upperBound)
        }
    }

    private var addTableButton: some View {
        Button {
            addTable()
        } label: {
            Label("Add another table", systemImage: "plus")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(TryzubColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TryzubColors.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func seedDrafts() {
        restaurantKey = controller.restaurantSetup.restaurantKey.nilIfBlank ?? restaurantKey
        if store.layoutTables.isEmpty {
            drafts = FloorPlanLayoutDraftTable.defaultSeedTables(restaurantKey: restaurantKey)
        } else {
            restaurantKey = store.layoutTables.first?.restaurantKey ?? restaurantKey
            drafts = store.layoutTables.map(FloorPlanLayoutDraftTable.fromDTO)
        }
        if selectedTableKey == nil {
            selectedTableKey = drafts.first?.tableKey
        }
    }

    private func addTable() {
        let nextIndex = (drafts.map(\.sortOrder).max() ?? 0) + 1
        let table = FloorPlanLayoutDraftTable.newTable(index: nextIndex, restaurantKey: restaurantKey)
        drafts.append(table)
        selectedTableKey = table.tableKey
    }

    private func deactivateDraft(tableKey: String) {
        guard let index = drafts.firstIndex(where: { $0.tableKey == tableKey }) else { return }
        drafts[index].isActive = false
    }

    private func removeDraft(tableKey: String) {
        drafts.removeAll { $0.tableKey == tableKey }
        if selectedTableKey == tableKey {
            selectedTableKey = drafts.first?.tableKey
        }
    }

    private func floorMapGridBounds() -> (columns: Int, rows: Int) {
        let layoutMaxX = drafts.map { $0.x + max($0.widthUnits, 1) }.max() ?? 0
        let layoutMaxY = drafts.map { $0.y + max($0.heightUnits, 1) }.max() ?? 0
        return (max(layoutMaxX, 6), max(layoutMaxY, 3))
    }

    private func placeSelectedTable(x: Int, y: Int) {
        guard let selectedTableKey,
              let index = drafts.firstIndex(where: { $0.tableKey == selectedTableKey }) else {
            return
        }
        let bounds = floorMapGridBounds()
        let draft = drafts[index]
        let width = max(draft.widthUnits, 1)
        let height = max(draft.heightUnits, 1)
        drafts[index].x = min(max(0, x), max(bounds.columns - width, 0))
        drafts[index].y = min(max(0, y), max(bounds.rows - height, 0))
    }

    private func saveLayout() async {
        let payload = drafts.map { $0.toDTO() }
        let saved = await store.saveLayout(payload)
        if saved {
            try? await Task.sleep(for: .milliseconds(350))
            onDismiss()
        }
    }
}

// MARK: - Floor Map

private struct FloorPlanSetupGridView: View {
    let drafts: [FloorPlanLayoutDraftTable]
    let selectedTableKey: String?
    let onSelect: (String) -> Void
    let onPlace: (Int, Int) -> Void

    private var layoutMaxX: Int {
        drafts.map { $0.x + max($0.widthUnits, 1) }.max() ?? 0
    }

    private var layoutMaxY: Int {
        drafts.map { $0.y + max($0.heightUnits, 1) }.max() ?? 0
    }

    private var columns: Int {
        max(layoutMaxX, 6)
    }

    private var rows: Int {
        max(layoutMaxY, 3)
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 24
            let availableHeight = geometry.size.height - 24
            let unitSize = min(
                42,
                availableWidth / CGFloat(columns),
                availableHeight / CGFloat(rows)
            )
            let gridWidth = CGFloat(columns) * unitSize
            let gridHeight = CGFloat(rows) * unitSize
            let originX = (geometry.size.width - gridWidth) / 2
            let originY = (geometry.size.height - gridHeight) / 2

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(TryzubColors.info.opacity(0.06))

                floorGridLines(
                    unitSize: unitSize,
                    originX: originX,
                    originY: originY
                )

                placementCells(
                    unitSize: unitSize,
                    originX: originX,
                    originY: originY
                )

                ForEach(drafts) { draft in
                    tableBlock(draft: draft, unitSize: unitSize)
                        .offset(
                            x: originX + CGFloat(draft.x) * unitSize + 2,
                            y: originY + CGFloat(draft.y) * unitSize + 2
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func floorGridLines(
        unitSize: CGFloat,
        originX: CGFloat,
        originY: CGFloat
    ) -> some View {
        Path { path in
            for column in 0...columns {
                let x = originX + CGFloat(column) * unitSize
                path.move(to: CGPoint(x: x, y: originY))
                path.addLine(to: CGPoint(x: x, y: originY + CGFloat(rows) * unitSize))
            }
            for row in 0...rows {
                let y = originY + CGFloat(row) * unitSize
                path.move(to: CGPoint(x: originX, y: y))
                path.addLine(to: CGPoint(x: originX + CGFloat(columns) * unitSize, y: y))
            }
        }
        .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
    }

    private func placementCells(
        unitSize: CGFloat,
        originX: CGFloat,
        originY: CGFloat
    ) -> some View {
        ForEach(0..<rows, id: \.self) { row in
            ForEach(0..<columns, id: \.self) { column in
                Color.clear
                    .frame(width: unitSize, height: unitSize)
                    .contentShape(Rectangle())
                    .offset(
                        x: originX + CGFloat(column) * unitSize,
                        y: originY + CGFloat(row) * unitSize
                    )
                    .onTapGesture {
                        onPlace(column, row)
                    }
            }
        }
    }

    @ViewBuilder
    private func tableBlock(draft: FloorPlanLayoutDraftTable, unitSize: CGFloat) -> some View {
        let isSelected = draft.tableKey == selectedTableKey
        let width = CGFloat(max(draft.widthUnits, 1)) * unitSize - 4
        let height = CGFloat(max(draft.heightUnits, 1)) * unitSize - 4

        Button {
            onSelect(draft.tableKey)
        } label: {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(TryzubColors.primaryControl.opacity(draft.isActive ? 0.18 : 0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected ? TryzubColors.primaryControl : TryzubColors.primaryControl.opacity(0.28),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }
                .shadow(
                    color: TryzubColors.primaryControl.opacity(isSelected ? 0.28 : 0),
                    radius: isSelected ? 6 : 0
                )
                .overlay {
                    tableBlockLabel(for: draft)
                }
                .frame(width: width, height: height)
                .opacity(draft.isActive ? 1 : 0.42)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(draft.label), fits \(draft.minCapacity) to \(draft.maxCapacity) guests, position X \(draft.x), Y \(draft.y)")
    }

    @ViewBuilder
    private func tableBlockLabel(for draft: FloorPlanLayoutDraftTable) -> some View {
        if draft.widthUnits == 1 {
            Text(draft.label)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(draft.isActive ? TryzubColors.primaryText : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 3)
        } else {
            VStack(spacing: 1) {
                Text(draft.label)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(draft.isActive ? TryzubColors.primaryText : .secondary)
                    .lineLimit(1)
                Text("\(draft.minCapacity)–\(draft.maxCapacity)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
