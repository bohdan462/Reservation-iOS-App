//
//  HostTableConfigView.swift
//  Tryzub Reservations
//
//  Local table inventory editor for Host Intelligence.
//

import SwiftUI

struct HostTableConfigView: View {
  @ObservedObject var tableStore: HostTableConfigStore

  @State private var editingTable: RestaurantTableConfig?
  @State private var isPresentingEditor = false

  var body: some View {
    List {
      Section {
        Text("Backend stores only the table name. Seat counts are local Host Intelligence settings used for recommendations.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if tableStore.sortedTables.isEmpty {
        ContentUnavailableView(
          "No Tables Configured",
          systemImage: "table.furniture",
          description: Text("Add tables to improve capacity projections.")
        )
      } else {
        ForEach(tableStore.sortedTables) { table in
          Button {
            editingTable = table
            isPresentingEditor = true
          } label: {
            tableRow(table)
          }
          .buttonStyle(.plain)
        }
        .onDelete(perform: deleteTables)
      }
    }
    .navigationTitle("Table Inventory")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          tableStore.addDefaultTable()
        } label: {
          Label("Add Table", systemImage: "plus")
        }
      }
    }
    .sheet(isPresented: $isPresentingEditor) {
      if let editingTable {
        NavigationStack {
          HostTableConfigEditorView(
            table: editingTable,
            allTables: tableStore.tables,
            onSave: { updated in
              tableStore.update(updated)
              isPresentingEditor = false
            },
            onCancel: {
              isPresentingEditor = false
            }
          )
        }
      }
    }
  }

  private func tableRow(_ table: RestaurantTableConfig) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(table.name)
          .font(.headline)
        Spacer()
        Text(table.isActive ? "Active" : "Inactive")
          .font(.caption)
          .foregroundStyle(table.isActive ? .primary : .secondary)
      }

      Text("Seats \(table.capacity)")
        .font(.subheadline)

      if !table.section.isEmpty {
        Text("Section: \(table.section)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text("Combinable with \(table.combinableTableIDs.count) table\(table.combinableTableIDs.count == 1 ? "" : "s")")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }

  private func deleteTables(at offsets: IndexSet) {
    let sorted = tableStore.sortedTables
    for index in offsets {
      tableStore.delete(sorted[index])
    }
  }
}

struct HostTableConfigEditorView: View {
  @State private var draft: RestaurantTableConfig

  let allTables: [RestaurantTableConfig]
  let onSave: (RestaurantTableConfig) -> Void
  let onCancel: () -> Void

  init(
    table: RestaurantTableConfig,
    allTables: [RestaurantTableConfig],
    onSave: @escaping (RestaurantTableConfig) -> Void,
    onCancel: @escaping () -> Void
  ) {
    _draft = State(initialValue: table)
    self.allTables = allTables
    self.onSave = onSave
    self.onCancel = onCancel
  }

  private var otherTables: [RestaurantTableConfig] {
    allTables
      .filter { $0.id != draft.id }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private var canSave: Bool {
    !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.capacity >= 1
  }

  var body: some View {
    Form {
      Section("Table") {
        TextField("Table name", text: $draft.name)
        Stepper(value: $draft.capacity, in: 1...24) {
          LabeledContent("Seats", value: "\(draft.capacity)")
        }
        TextField("Section", text: $draft.section)
        Toggle("Active", isOn: $draft.isActive)
        Stepper(value: $draft.sortOrder, in: 0...999) {
          LabeledContent("Sort order", value: "\(draft.sortOrder)")
        }
      }

      Section("Preferences") {
        Toggle("Preferred for large parties", isOn: $draft.preferredForLargeParties)
        Toggle("Preferred for wheelchair", isOn: $draft.preferredForWheelchair)
        Toggle("Preferred for quiet seating", isOn: $draft.preferredForQuietSeating)
      }

      Section("Can combine with") {
        if otherTables.isEmpty {
          Text("Add more tables to configure combinations.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(otherTables) { table in
            Toggle(table.name, isOn: combinableBinding(for: table.id))
          }
        }
      }
    }
    .navigationTitle("Edit Table")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel", action: onCancel)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          var sanitized = draft
          sanitized.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
          sanitized.capacity = max(draft.capacity, 1)
          sanitized.combinableTableIDs.removeAll { $0 == draft.id }
          onSave(sanitized)
        }
        .disabled(!canSave)
      }
    }
  }

  private func combinableBinding(for tableID: UUID) -> Binding<Bool> {
    Binding(
      get: { draft.combinableTableIDs.contains(tableID) },
      set: { isSelected in
        if isSelected {
          if !draft.combinableTableIDs.contains(tableID) {
            draft.combinableTableIDs.append(tableID)
          }
        } else {
          draft.combinableTableIDs.removeAll { $0 == tableID }
        }
      }
    )
  }
}
