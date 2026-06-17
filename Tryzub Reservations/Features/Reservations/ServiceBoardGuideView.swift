//
//  ServiceBoardGuideView.swift
//  Tryzub Reservations
//
//  Staff-facing operating guide for the service board.
//

import SwiftUI

struct ServiceBoardGuideView: View {
    private let sections: [GuideSection] = [
        GuideSection(
            title: "Start with Today",
            systemImage: "house",
            body: "Check arrivals, guests, new bookings, and reservations that still need tables."
        ),
        GuideSection(
            title: "Assign tables",
            systemImage: "square.grid.3x3",
            body: "Use Floor or reservation detail to pick tables before guests arrive."
        ),
        GuideSection(
            title: "Confirm and remind",
            systemImage: "bell.badge",
            body: "Use confirmation and reminder actions when guests still need notice."
        ),
        GuideSection(
            title: "During service",
            systemImage: "person.2",
            body: "Seat guests, watch overdue arrivals, and clear completed parties as tables turn."
        ),
        GuideSection(
            title: "Host Intelligence",
            systemImage: "sparkles",
            body: "The board highlights what needs attention. It never changes reservations by itself."
        ),
        GuideSection(
            title: "End of service",
            systemImage: "checkmark.seal",
            body: "Use the wrap-up summary to see what was handled and what still needs a final status."
        )
    ]

    var body: some View {
        List {
            Section {
                Text("A short shift guide for hosts, managers, and floor staff.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("How to use the service board") {
                ForEach(sections) { section in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: section.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TryzubColors.primaryControl)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                            Text(section.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("What is local") {
                Text("This iPad can keep local display preferences and draft wording. Restaurant settings, floor tables, reminders, confirmations, and reservation status come from the shared backend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Service Board Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GuideSection: Identifiable {
    let title: String
    let systemImage: String
    let body: String

    var id: String { title }
}
