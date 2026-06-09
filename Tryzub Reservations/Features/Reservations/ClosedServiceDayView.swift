//
//  ClosedServiceDayView.swift
//  Tryzub Reservations
//
//  Calm day-off presentation when the selected service date is closed.
//

import SwiftUI

struct ClosedServiceDayView: View {
  @State private var animateSymbols = false

  var body: some View {
    VStack(spacing: 20) {
      Spacer(minLength: 24)

      ZStack {
        Image(systemName: "moon.zzz.fill")
          .font(.system(size: 56))
          .foregroundStyle(.secondary.opacity(0.85))
          .offset(y: animateSymbols ? -4 : 4)
          .animation(
            .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
            value: animateSymbols
          )

        Image(systemName: "pawprint.fill")
          .font(.title3.weight(.semibold))
          .foregroundStyle(.tertiary)
          .offset(x: 34, y: 28)
          .rotationEffect(.degrees(animateSymbols ? -8 : 8))
          .animation(
            .easeInOut(duration: 3.1).repeatForever(autoreverses: true),
            value: animateSymbols
          )

        Text("zzz")
          .font(.caption.weight(.bold))
          .foregroundStyle(.tertiary)
          .offset(x: -42, y: -30)
          .opacity(animateSymbols ? 0.35 : 0.9)
          .animation(
            .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
            value: animateSymbols
          )
      }
      .frame(height: 110)

      VStack(spacing: 10) {
        Text("Woof — day off.")
          .font(.title2.weight(.semibold))
          .multilineTextAlignment(.center)

        Text("The restaurant is closed on this day.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)

        Text("Pick another date above to review reservations.")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, 24)

      Spacer(minLength: 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 16)
    .padding(.vertical, 20)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .onAppear {
      animateSymbols = true
    }
  }
}

struct ClosedDayReservationsNoticeView: View {
  let reservationCount: Int
  let newCount: Int
  let reviewCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Closed day with reservations", systemImage: "calendar.badge.exclamationmark")
        .font(.headline)
        .foregroundStyle(.orange)

      Text("Review bookings for this date.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      if newCount + reviewCount > 0 {
        Text("\(newCount + reviewCount) booking\(newCount + reviewCount == 1 ? "" : "s") still need staff review.")
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      } else {
        Text("\(reservationCount) reservation\(reservationCount == 1 ? "" : "s") on this closed day.")
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.orange.opacity(0.22), lineWidth: 1)
    }
  }
}
