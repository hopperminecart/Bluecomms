import Foundation
import Network

final class NetworkManager: @unchecked Sendable {
    let serviceType = "_bluecomms._tcp"
    let serviceDomain = "local."
    
    var listener: NWListener?
    var browser: NWBrowser?
    var activeConnection: PeerConnection?
    
    var discoveredPeers: [NWBrowser.Result] = []
    var deviceName: String
    
    var onPeersUpdated: (([NWBrowser.Result]) -> Void)?
    var onConnectionEstablished: (() -> Void)?
    var onMessageReceived: ((String) -> Void)?

    init() {
        self.deviceName = Host.current().localizedName ?? "Unknown Mac"
    }

    func start() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        
        // Start Listener
        do {
            let newListener = try NWListener(using: params)
            newListener.service = NWListener.Service(name: deviceName, type: serviceType, domain: serviceDomain)
            newListener.stateUpdateHandler = { state in
                if case .ready = state {
                    print("[LISTENER] Ready to accept connections.")
                } else if case .failed(let error) = state {
                    print("[LISTENER] Failed with error: \(error)")
                }
            }
            newListener.newConnectionHandler = { [weak self] newConnection in
                print("\n[LISTENER] Incoming connection from \(newConnection.endpoint)")
                self?.acceptConnection(newConnection)
            }
            newListener.start(queue: .main)
            self.listener = newListener
            print("[LISTENER] Started advertising '\(deviceName)'")
        } catch {
            print("[LISTENER] Failed to create listener: \(error)")
        }
        
        // Start Browser
        let browserParams = NWParameters.tcp
        browserParams.includePeerToPeer = true
        let newBrowser = NWBrowser(for: .bonjour(type: serviceType, domain: serviceDomain), using: browserParams)
        
        newBrowser.stateUpdateHandler = { state in
            if case .ready = state {
                print("[BROWSER] Started browsing for peers.")
            } else if case .failed(let error) = state {
                print("[BROWSER] Failed with error: \(error)")
            }
        }
        
        newBrowser.browseResultsChangedHandler = { [weak self] results, changes in
            self?.discoveredPeers = Array(results)
            self?.onPeersUpdated?(self?.discoveredPeers ?? [])
        }
        
        newBrowser.start(queue: .main)
        self.browser = newBrowser
    }
    
    func connectToPeer(at index: Int) {
        guard index >= 0 && index < discoveredPeers.count else {
            print("Invalid peer index.")
            return
        }
        let peer = discoveredPeers[index]
        print("[CONNECTION] Initiating connection to \(peer.endpoint)")
        
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let connection = NWConnection(to: peer.endpoint, using: params)
        acceptConnection(connection)
    }
    
    private func acceptConnection(_ connection: NWConnection) {
        activeConnection?.cancel()
        
        let peerConnection = PeerConnection(connection: connection)
        peerConnection.onStateChange = { [weak self] state in
            switch state {
            case .ready:
                print("\n[CONNECTION] Ready")
                self?.onConnectionEstablished?()
            case .failed(let error):
                print("\n[CONNECTION] Failed: \(error)")
                self?.activeConnection = nil
            case .cancelled:
                print("\n[CONNECTION] Cancelled")
                self?.activeConnection = nil
            case .preparing:
                print("\n[CONNECTION] Preparing...")
            case .waiting(let error):
                print("\n[CONNECTION] Waiting: \(error)")
            case .setup:
                break
            @unknown default:
                break
            }
        }
        peerConnection.onMessageReceived = { [weak self] message in
            self?.onMessageReceived?(message)
        }
        
        self.activeConnection = peerConnection
        peerConnection.start()
    }
    
    func send(message: String) {
        if let conn = activeConnection {
            conn.send(message: message)
            print("[SEND] \(message.utf8.count) bytes")
        } else {
            print("No active connection to send message.")
        }
    }
    
    func stop() {
        activeConnection?.cancel()
        listener?.cancel()
        browser?.cancel()
    }
}
