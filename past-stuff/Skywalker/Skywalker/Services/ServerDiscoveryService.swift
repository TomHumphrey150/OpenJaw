//
//  ServerDiscoveryService.swift
//  Skywalker
//
//  Bonjour/mDNS service discovery for relay server
//

import Foundation
import Network

@Observable
@MainActor
class ServerDiscoveryService {
    var discoveredServers: [DiscoveredServer] = []
    var isScanning: Bool = false
    var permissionDenied: Bool = false
    var errorMessage: String?
    var hasScannedOnce: Bool = false

    nonisolated(unsafe) private var browser: NWBrowser?

    struct DiscoveredServer: Identifiable {
        let id = UUID()
        let name: String
        let host: String
        let port: Int

        var displayName: String {
            "\(name) (\(host):\(port))"
        }
    }

    func startScanning() {
        guard !isScanning else { return }

        isScanning = true
        discoveredServers.removeAll()

        // Create browser for "_openjaw-relay._tcp" service type
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_openjaw-relay._tcp", domain: nil), using: parameters)

        browser?.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                switch newState {
                case .ready:
                    print("[Discovery] Browser ready, scanning for servers...")
                    self?.permissionDenied = false
                    self?.errorMessage = nil
                case .failed(let error):
                    print("[Discovery] Browser failed: \(error)")
                    self?.isScanning = false
                    self?.hasScannedOnce = true

                    // Check if permission was denied (error code -65555 = NoAuth)
                    let nsError = error as NSError
                    if nsError.code == -65555 {
                        self?.permissionDenied = true
                        self?.errorMessage = "Local Network permission denied. Go to Settings > Skywalker > Local Network to enable."
                    } else {
                        self?.errorMessage = "Discovery failed: \(error.localizedDescription)"
                    }
                case .cancelled:
                    print("[Discovery] Browser cancelled")
                    self?.isScanning = false
                    self?.hasScannedOnce = true
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleBrowseResults(results: results, changes: changes)
            }
        }

        browser?.start(queue: .main)
    }

    func stopScanning() {
        stopBrowser()
        isScanning = false
        hasScannedOnce = true
    }

    nonisolated private func stopBrowser() {
        browser?.cancel()
        browser = nil
    }

    private func handleBrowseResults(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                resolveEndpoint(result: result)
            case .removed(let result):
                removeServer(result: result)
            default:
                break
            }
        }
    }

    private func resolveEndpoint(result: NWBrowser.Result) {
        guard case .service(let name, let type, let domain, _) = result.endpoint else {
            return
        }

        print("[Discovery] Found service: \(name)")

        // Create a connection to resolve the endpoint
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .ready = state {
                    if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                       case .hostPort(let host, let port) = innerEndpoint {

                        var hostString = "\(host)"
                        // Strip interface identifier (e.g., "192.168.1.43%en0" -> "192.168.1.43")
                        if let percentIndex = hostString.firstIndex(of: "%") {
                            hostString = String(hostString[..<percentIndex])
                        }

                        let portInt = Int(port.rawValue)

                        let server = DiscoveredServer(
                            name: name,
                            host: hostString,
                            port: portInt
                        )

                        // Add to discovered servers if not already present
                        if !self!.discoveredServers.contains(where: { $0.host == hostString && $0.port == portInt }) {
                            self?.discoveredServers.append(server)
                            print("[Discovery] Resolved server: \(hostString):\(portInt)")
                        }
                    }
                    connection.cancel()
                }
            }
        }

        connection.start(queue: .main)
    }

    private func removeServer(result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else {
            return
        }

        discoveredServers.removeAll { $0.name == name }
        print("[Discovery] Removed server: \(name)")
    }

    deinit {
        stopBrowser()
    }
}
