//
//  NetworkPathMonitor.swift
//  Tryzub Reservations
//

import Foundation
import Network

/// Low-energy reachability signal. `NWPathMonitor` only fires on path changes — no polling.
final class NetworkPathMonitor {
    typealias PathChangeHandler = @MainActor (Bool) -> Void

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "tryzub.network.path", qos: .utility)
    private var isStarted = false
    private var onPathChange: PathChangeHandler?

    func start(onPathChange: @escaping PathChangeHandler) {
        guard !isStarted else { return }
        isStarted = true
        self.onPathChange = onPathChange

        monitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.onPathChange?(isSatisfied)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        onPathChange = nil
        monitor.pathUpdateHandler = nil
        monitor.cancel()
    }

    deinit {
        stop()
    }
}
