//
//  HostOnDeviceSupportPhase.swift
//  Tryzub Reservations
//
//  Staff-facing on-device support preparation status.
//

import Foundation

enum HostOnDeviceSupportPhase: Equatable {
  case idle
  case unavailable
  case waitingForSafeMoment
  case preparing(progress: Double?)
  case ready
  case failed(staffMessage: String)

  var showsHostTabStatus: Bool {
    switch self {
    case .waitingForSafeMoment, .preparing, .ready, .failed:
      return true
    case .idle, .unavailable:
      return false
    }
  }

  var showsMoreSection: Bool {
    switch self {
    case .idle:
      return false
    case .unavailable, .waitingForSafeMoment, .preparing, .ready, .failed:
      return true
    }
  }

  var hostTabLine: String? {
    switch self {
    case .idle, .unavailable:
      return nil
    case .waitingForSafeMoment:
      return "On-device support will prepare when the app is idle."
    case .preparing(let progress):
      if let progress {
        return "Preparing on-device assistance · \(Int((progress * 100).rounded()))%"
      }
      return "Preparing on-device assistance…"
    case .ready:
      return "On-device support ready"
    case .failed(let staffMessage):
      return staffMessage
    }
  }

  var title: String {
    switch self {
    case .idle:
      return "On-device support"
    case .unavailable:
      return "On-device support unavailable"
    case .waitingForSafeMoment:
      return "Setting up local support"
    case .preparing:
      return "Preparing on-device assistance"
    case .ready:
      return "On-device support ready"
    case .failed:
      return "On-device support"
    }
  }

  var subtitle: String? {
    switch self {
    case .idle:
      return nil
    case .unavailable:
      return "On-device support unavailable in this build."
    case .waitingForSafeMoment:
      return "On-device support will prepare when the app is idle."
    case .preparing:
      return "Keeping this private on this iPhone."
    case .ready:
      return "Private local assistance is prepared for this iPhone."
    case .failed(let staffMessage):
      return staffMessage
    }
  }

  var copyProgressFraction: Double? {
    if case .preparing(let progress) = self {
      return progress
    }
    return nil
  }

  var pulseIsActive: Bool {
    switch self {
    case .waitingForSafeMoment, .preparing, .ready:
      return true
    case .idle, .unavailable, .failed:
      return false
    }
  }
}
