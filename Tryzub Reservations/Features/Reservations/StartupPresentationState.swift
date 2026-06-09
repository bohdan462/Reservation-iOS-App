//
//  StartupPresentationState.swift
//  Tryzub Reservations
//
//  Presentation-only startup entrance state for cache-first launch.
//

import Foundation

enum StartupPresentationState: Equatable {
  case checkingCache
  case loadingSavedReservations
  case emptyCacheLoadingNetwork
  case showingCachedDataRefreshing
  case ready
  case failedNoCache(String)
}

enum StartupCacheLoadingMode: Equatable {
  case checkingSavedData
  case loadingSavedReservations
  case loadingFromNetwork
}
