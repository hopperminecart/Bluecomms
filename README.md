# BlueComms

Off-grid peer-to-peer chat for nearby Macs. Devices find each other with Bonjour over the local network or AWDL (`includePeerToPeer`) and talk over an encrypted TCP session. No internet or shared Wi-Fi network is required — Wi-Fi just needs to be on.

## Build and run

Needs macOS 14+ and Swift 6.1.

```bash
cd BlueCommsCLI
swift run BlueCommsApp          # Mac app
swift run BlueCommsApp --demo   # UI with simulated peers (no second Mac)
swift run BlueCommsCLI          # original terminal client
```

Run it on two Macs on the same LAN, or on two Macs with Wi-Fi on and no access point (AWDL).

The first launch creates `~/.bluecomms/` (device id, identity key, known-peer list, encrypted conversation archive) with `0700` / `0600` permissions. Chat history survives quit. Messages typed while a peer is gone stay queued and flush when that session comes back. You can keep a live session with more than one peer; the sidebar shows online vs last-seen.

## Local Network permission

macOS will not let a process browse Bonjour until it has Local Network access.

1. Run `swift run` from Terminal.
2. If a Local Network prompt appears, allow it.
3. Otherwise open **System Settings → Privacy & Security → Local Network** and enable Terminal (or the host app that launched the binary).

Keep Wi-Fi on. You do not need to join a network.

## Commands

```
help                 Show commands
list                 Show discovered peers
connect <index>      Connect by list index
connect <name>       Connect by name or short id
disconnect           Close the current session
quit / exit          Stop advertising and leave
<text>               Send a message once connected
```

Peer indexes are sorted by display name and stay stable while that set of peers is present. Your own advertisement is hidden.

## Security

Sessions use X25519 key agreement and AES-GCM. Each device has a persistent identity key.

On first connect, BlueComms stores the peer's public key (trust on first use) and prints fingerprints. Read them back to each other:

- Your "Peer fingerprint" should match their "Your fingerprint".

If the same device id later presents a different key, the connection is dropped.

This stops passive sniffing. An attacker who is present on the first connect can still poison TOFU if you skip the fingerprint check.

## Tests

This machine's Command Line Tools do not include XCTest, so tests are a regular executable:

```bash
cd BlueCommsCLI
swift run BlueCommsSelfTest
```
