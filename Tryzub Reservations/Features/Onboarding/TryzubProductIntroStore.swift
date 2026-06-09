//
//  TryzubProductIntroStore.swift
//  Tryzub Reservations
//
//  One-time product intro gate before sign-in / main shell.
//

import Foundation

@MainActor
final class TryzubProductIntroStore: ObservableObject {
  @Published private(set) var hasCompletedIntro: Bool

  private let defaultsKey = "tryzub.productIntro.completed.v1"

  init() {
    hasCompletedIntro = UserDefaults.standard.bool(forKey: defaultsKey)
  }

  func complete() {
    guard !hasCompletedIntro else { return }
    hasCompletedIntro = true
    UserDefaults.standard.set(true, forKey: defaultsKey)
  }

  #if DEBUG
  func resetForPreview() {
    hasCompletedIntro = false
    UserDefaults.standard.removeObject(forKey: defaultsKey)
  }
  #endif
}
