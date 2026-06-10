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

    var title: String {
        switch self {
        case .oneCube:
            return "1 cube: 1–4"
        case .twoCubes:
            return "2 cubes: 4–6"
        case .threeCubes:
            return "3 cubes: 6–8"
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
            label: "Table \(index)",
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
    @ObservedObject var store: FloorPlanStore
    let onDismiss: () -> Void

    @State private var drafts: [FloorPlanLayoutDraftTable] = []
    @State private var selectedTableKey: String?
    @State private var restaurantKey = "tryzub"

    var body: some View {
        NavigationStack {
            List {
                if drafts.isEmpty {
                    Section {
                        Text("Add tables and place them on the grid. Save sends layout to the backend.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Tables") {
                    ForEach($drafts) { $draft in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Label", text: $draft.label)
                                if !draft.isActive {
                                    Text("Inactive")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                            Picker("Size", selection: sizePresetBinding(for: $draft)) {
                                ForEach(FloorPlanTableSizePreset.allCases) { preset in
                                    Text(preset.title).tag(preset)
                                }
                            }
                            Stepper("X: \(draft.x)", value: $draft.x, in: 0...24)
                            Stepper("Y: \(draft.y)", value: $draft.y, in: 0...24)
                            Toggle("Active", isOn: $draft.isActive)

                            if draft.isSavedOnBackend {
                                if draft.isActive {
                                    Button("Deactivate table", role: .destructive) {
                                        deactivateDraft(tableKey: draft.tableKey)
                                    }
                                }
                            } else {
                                Button("Remove draft", role: .destructive) {
                                    removeDraft(tableKey: draft.tableKey)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .onTapGesture {
                            selectedTableKey = draft.tableKey
                        }
                    }

                    Button("Add table") {
                        addTable()
                    }
                }

                if !drafts.isEmpty {
                    Section("Grid placement") {
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
                        .frame(height: 280)
                    }
                }
            }
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
                await store.loadLayout()
                seedDrafts()
            }
        }
    }

    private func seedDrafts() {
        if store.layoutTables.isEmpty {
            drafts = FloorPlanLayoutDraftTable.defaultSeedTables(restaurantKey: restaurantKey)
        } else {
            restaurantKey = store.layoutTables.first?.restaurantKey ?? restaurantKey
            drafts = store.layoutTables.map(FloorPlanLayoutDraftTable.fromDTO)
        }
    }

    private func addTable() {
        let nextIndex = (drafts.map(\.sortOrder).max() ?? 0) + 1
        drafts.append(FloorPlanLayoutDraftTable.newTable(index: nextIndex, restaurantKey: restaurantKey))
    }

    private func deactivateDraft(tableKey: String) {
        guard let index = drafts.firstIndex(where: { $0.tableKey == tableKey }) else { return }
        drafts[index].isActive = false
        if selectedTableKey == tableKey {
            selectedTableKey = nil
        }
    }

    private func removeDraft(tableKey: String) {
        drafts.removeAll { $0.tableKey == tableKey }
        if selectedTableKey == tableKey {
            selectedTableKey = nil
        }
    }

    private func placeSelectedTable(x: Int, y: Int) {
        guard let selectedTableKey,
              let index = drafts.firstIndex(where: { $0.tableKey == selectedTableKey }) else {
            return
        }
        drafts[index].x = x
        drafts[index].y = y
    }

    private func saveLayout() async {
        let payload = drafts.map { $0.toDTO() }
        let saved = await store.saveLayout(payload)
        if saved {
            onDismiss()
        }
    }

    private func sizePresetBinding(
        for draft: Binding<FloorPlanLayoutDraftTable>
    ) -> Binding<FloorPlanTableSizePreset> {
        Binding(
            get: {
                FloorPlanTableSizePreset(rawValue: draft.wrappedValue.widthUnits) ?? .oneCube
            },
            set: { preset in
                draft.wrappedValue.widthUnits = preset.widthUnits
                draft.wrappedValue.heightUnits = preset.heightUnits
                draft.wrappedValue.minCapacity = preset.minCapacity
                draft.wrappedValue.maxCapacity = preset.maxCapacity
            }
        )
    }
}

private struct FloorPlanSetupGridView: View {
    let drafts: [FloorPlanLayoutDraftTable]
    let selectedTableKey: String?
    let onSelect: (String) -> Void
    let onPlace: (Int, Int) -> Void

    private let unitSize: CGFloat = 28
    private let columns = 12
    private let rows = 8

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        Rectangle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            .frame(width: unitSize, height: unitSize)
                            .offset(x: CGFloat(column) * unitSize, y: CGFloat(row) * unitSize)
                            .onTapGesture {
                                onPlace(column, row)
                            }
                    }
                }

                ForEach(drafts.filter(\.isActive)) { draft in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            draft.tableKey == selectedTableKey
                                ? TryzubColors.primaryControl.opacity(0.25)
                                : TryzubColors.info.opacity(0.18)
                        )
                        .overlay(
                            Text(draft.label)
                                .font(.caption2.weight(.semibold))
                                .padding(4)
                        )
                        .frame(
                            width: CGFloat(draft.widthUnits) * unitSize - 2,
                            height: CGFloat(draft.heightUnits) * unitSize - 2
                        )
                        .offset(
                            x: CGFloat(draft.x) * unitSize + 1,
                            y: CGFloat(draft.y) * unitSize + 1
                        )
                        .onTapGesture {
                            onSelect(draft.tableKey)
                        }
                }
            }
            .frame(
                width: CGFloat(columns) * unitSize,
                height: CGFloat(rows) * unitSize
            )
        }
    }
}
