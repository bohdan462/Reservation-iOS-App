//
//  ReservationSharedUI.swift
//  Tryzub Reservations
//

import SwiftUI

struct ReservationDashedLine: View {
    var isVertical = false

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                if isVertical {
                    path.move(to: CGPoint(x: proxy.size.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height))
                } else {
                    path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
                }
            }
            .stroke(
                Color.primary.opacity(0.14),
                style: StrokeStyle(lineWidth: 1, dash: [4, 5], dashPhase: 0)
            )
        }
    }
}
