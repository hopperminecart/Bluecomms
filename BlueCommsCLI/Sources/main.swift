import Foundation
import Network

let manager = NetworkManager()

print("========================================")
print("BlueComms CLI Network Validation Spike")
print("Local Device: \(manager.deviceName)")
print("========================================")

manager.onPeersUpdated = { peers in
    print("\n--- Discovered Peers ---")
    for (index, peer) in peers.enumerated() {
        if case .service(let name, _, _, _) = peer.endpoint {
            print("[\(index)] \(name)")
        } else {
            print("[\(index)] \(peer.endpoint)")
        }
    }
    print("------------------------\n> ", terminator: "")
    fflush(stdout)
}

manager.onConnectionEstablished = {
    print("\nConnection established! You can now type messages.")
    print("> ", terminator: "")
    fflush(stdout)
}

manager.onMessageReceived = { message in
    print("\n[RECEIVE] \(message.utf8.count) bytes: \(message)")
    print("> ", terminator: "")
    fflush(stdout)
}

manager.start()

// REPL loop
let queue = DispatchQueue(label: "input")
queue.async {
    print("Type 'connect <index>' to connect, or type messages if connected. 'quit' to exit.")
    print("> ", terminator: "")
    fflush(stdout)
    
    while true {
        guard let input = readLine() else { continue }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            print("> ", terminator: "")
            fflush(stdout)
            continue
        }
        
        if trimmed == "quit" || trimmed == "exit" {
            manager.stop()
            exit(0)
        } else if trimmed.starts(with: "connect ") {
            let parts = trimmed.split(separator: " ")
            if parts.count == 2, let index = Int(parts[1]) {
                manager.connectToPeer(at: index)
            } else {
                print("Usage: connect <index>")
            }
        } else if manager.activeConnection != nil {
            manager.send(message: trimmed)
        } else {
            print("Not connected. Type 'connect <index>' to connect to a peer, or 'quit' to exit.")
        }
        print("> ", terminator: "")
        fflush(stdout)
    }
}

RunLoop.main.run()
