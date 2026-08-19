import Foundation
import BlueCommsCore

let manager: NetworkManager
do {
    manager = try NetworkManager()
} catch {
    fputs("Failed to load device identity: \(error)\n", stderr)
    exit(1)
}

print("========================================")
print("BlueComms")
print("Local device: \(manager.deviceName) · \(manager.shortID)")
print("Fingerprint:  \(manager.fingerprint)")
print("Type 'help' for commands.")
print("========================================")

manager.onLog = { message in
    print("\n\(message)")
    printPrompt()
}

manager.onPeersUpdated = { peers in
    print("\n--- Discovered Peers ---")
    if peers.isEmpty {
        print("(none yet)")
    } else {
        for (index, peer) in peers.enumerated() {
            print("[\(index)] \(peer.displayName) · \(peer.shortName)")
        }
    }
    print("------------------------")
    printPrompt()
}

manager.onConnectionEstablished = {
    print("\nSecure session ready. Type a message, or 'disconnect' / 'quit'.")
    printPrompt()
}

manager.onMessageReceived = { message in
    print("\n[RECEIVE] \(message.utf8.count) bytes: \(message)")
    printPrompt()
}

manager.start()

let inputQueue = DispatchQueue(label: "bluecomms.input")
inputQueue.async {
    printPrompt()
    while true {
        guard let input = readLine() else {
            manager.stop()
            exit(0)
        }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            printPrompt()
            continue
        }
        handleCommand(trimmed, manager: manager)
    }
}

RunLoop.main.run()

private func handleCommand(_ raw: String, manager: NetworkManager) {
    let lowered = raw.lowercased()
    if lowered == "quit" || lowered == "exit" {
        manager.stop()
        exit(0)
    }
    if lowered == "help" {
        printHelp()
        printPrompt()
        return
    }
    if lowered == "list" {
        printPeerList(manager.peers)
        printPrompt()
        return
    }
    if lowered == "disconnect" {
        manager.disconnect()
        printPrompt()
        return
    }
    if lowered == "connect" || lowered.hasPrefix("connect ") {
        let rest = raw.dropFirst("connect".count).trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.isEmpty {
            print("Usage: connect <index|name>")
            printPrompt()
            return
        }
        if let index = Int(rest) {
            manager.connectToPeer(at: index)
        } else {
            manager.connectToPeer(named: rest)
        }
        printPrompt()
        return
    }
    if manager.isConnected {
        manager.send(message: raw)
    } else {
        print("Not connected. Type 'list', then 'connect <index>', or 'help'.")
    }
    printPrompt()
}

private func printPeerList(_ peers: [DiscoveredPeer]) {
    print("--- Discovered Peers ---")
    if peers.isEmpty {
        print("(none yet)")
    } else {
        for (index, peer) in peers.enumerated() {
            print("[\(index)] \(peer.displayName) · \(peer.shortName)")
        }
    }
    print("------------------------")
}

private func printHelp() {
    print(
        """
        Commands:
          help                 Show this list
          list                 Show discovered peers
          connect <index>      Connect by list index
          connect <name>       Connect by name or short id
          disconnect           Close the current session
          quit / exit          Stop advertising and leave
          <text>               Send a message once connected
        """
    )
}

private func printPrompt() {
    print("> ", terminator: "")
    fflush(stdout)
}
