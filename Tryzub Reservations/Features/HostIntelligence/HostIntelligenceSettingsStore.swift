//
//  HostIntelligenceSettingsStore.swift
//  Tryzub Reservations
//
//  UserDefaults-backed persistence for Host Intelligence settings.
//

import Foundation

@MainActor
final class HostIntelligenceSettingsStore: ObservableObject {

  @Published private(set) var settings: HostIntelligenceSettings

  private let defaultsKey = "tryzub.hostIntelligence.settings.v1"

  init() {
    settings = HostIntelligenceSettings()
    load()
  }

  func update(transform: (inout HostIntelligenceSettings) -> Void) {
    var copy = settings
    transform(&copy)
    settings = copy
    persist()
  }

  func resetToDefaults() {
    settings = HostIntelligenceSettings()
    persist()
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
      settings = HostIntelligenceSettings()
      return
    }

    do {
      settings = try JSONDecoder().decode(HostIntelligenceSettings.self, from: data)
    } catch {
      settings = HostIntelligenceSettings()
    }
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    UserDefaults.standard.set(data, forKey: defaultsKey)
  }
}
