//
//  TryzubProductIntroView.swift
//  Tryzub Reservations
//
//  First-launch intro — one glass frame, pulse mark, continue.
//

import SwiftUI

struct TryzubProductIntroView: View {
  var onFinished: () -> Void

  var body: some View {
    TryzubGroupedCanvas {
      Color.clear
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 72)
        .overlay {
          HostPulseIcon(isActive: true, size: 28)
        }
        .tryzubMinimalSurface(cornerRadius: 22)

      VStack {
        Spacer()
        Button(action: onFinished) {
          HStack(spacing: 6) {
            Text("Continue")
            Image(systemName: "arrow.right")
              .font(.caption2.weight(.bold))
          }
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, 22)
          .padding(.vertical, 11)
        }
        .buttonStyle(TryzubGlassCapsuleButtonStyle())
        .padding(.bottom, 28)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Tryzub introduction")
  }
}

#if DEBUG
#Preview {
  TryzubProductIntroView(onFinished: {})
}
#endif
