import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ChatStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            ChatView()
        }
        .tint(Color(red: 0.27, green: 0.53, blue: 1.0))
        .background(Palette.bg)
        .preferredColorScheme(.dark)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: ChatStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("BLUECOMMS")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Palette.muted)
                Text(store.localName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text("\(store.shortID)  ·  \(store.fingerprint)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .textSelection(.enabled)
                if store.isDemo {
                    Text("DEMO")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.accent.opacity(0.2))
                        .foregroundStyle(Palette.accent)
                        .clipShape(Capsule())
                        .padding(.top, 4)
                }
            }
            .padding(16)

            Divider().overlay(Palette.hairline)

            Text("Nearby")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            if store.peers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No peers yet.")
                        .foregroundStyle(Palette.text)
                    Text("Turn Wi-Fi on and allow Local Network for this app in System Settings → Privacy & Security.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            } else {
                List(store.peers, selection: Binding(
                    get: { store.selectedPeerID },
                    set: { if let id = $0 { store.select(peerID: id) } }
                )) { peer in
                    PeerRow(peer: peer, isSelected: peer.id == store.selectedPeerID)
                        .tag(peer.id)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            Spacer(minLength: 0)

            Text(store.statusLine)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.sidebar)
    }
}

private struct PeerRow: View {
    let peer: NearbyPeer
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(peer.isOnline ? Palette.online : Palette.muted)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(peer.shortName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ChatView: View {
    @EnvironmentObject private var store: ChatStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.hairline)
            messageList
            Divider().overlay(Palette.hairline)
            composer
        }
        .background(Palette.bg)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            if let peer = store.selectedPeer {
                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(store.isConnectedToSelection ? "Secure session" : (peer.isOnline ? "Nearby" : "Last seen recently"))
                        .font(.system(size: 12))
                        .foregroundStyle(store.isConnectedToSelection ? Palette.online : Palette.muted)
                }
                Spacer()
                if store.isConnectedToSelection {
                    Button("Disconnect") { store.disconnect() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Connect") { store.connectToSelection() }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.phase == .connecting)
                }
            } else {
                Text("Select a nearby peer")
                    .foregroundStyle(Palette.muted)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if store.selectedPeer == nil {
                        empty("Pick someone in the sidebar. BlueComms only talks over the local radio — no internet.")
                    } else if store.selectedMessages.isEmpty {
                        empty("No messages yet. Connect and type below.")
                    } else {
                        ForEach(store.selectedMessages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(20)
            }
            .onChange(of: store.selectedMessages.count) {
                if let last = store.selectedMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $store.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.composer)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onSubmit(store.sendDraft)
            Button("Send") { store.sendDraft() }
                .buttonStyle(.borderedProminent)
                .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.selectedPeerID == nil)
        }
        .padding(16)
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isLocal { Spacer(minLength: 80) }
            VStack(alignment: message.isLocal ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isLocal ? Palette.localBubble : Palette.remoteBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
            }
            if !message.isLocal { Spacer(minLength: 80) }
        }
    }
}

private enum Palette {
    static let bg = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let sidebar = Color(red: 0.09, green: 0.10, blue: 0.13)
    static let composer = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let localBubble = Color(red: 0.16, green: 0.36, blue: 0.78)
    static let remoteBubble = Color(red: 0.16, green: 0.18, blue: 0.22)
    static let text = Color(red: 0.93, green: 0.94, blue: 0.96)
    static let muted = Color(red: 0.62, green: 0.65, blue: 0.70)
    static let online = Color(red: 0.27, green: 0.77, blue: 0.55)
    static let accent = Color(red: 0.27, green: 0.53, blue: 1.0)
    static let hairline = Color.white.opacity(0.08)
}
