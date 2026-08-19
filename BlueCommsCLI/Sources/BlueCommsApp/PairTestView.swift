import BlueCommsCore
import SwiftUI

struct PairTestView: View {
    @ObservedObject var sender: ChatStore
    @ObservedObject var receiver: ChatStore

    var body: some View {
        HStack(spacing: 0) {
            pane(title: "SENDER", store: sender, accent: Color(red: 0.16, green: 0.36, blue: 0.78))
            Divider()
            pane(title: "RECEIVER", store: receiver, accent: Color(red: 0.12, green: 0.55, blue: 0.40))
        }
        .background(Color(red: 0.07, green: 0.08, blue: 0.10))
        .preferredColorScheme(.dark)
    }

    private func pane(title: String, store: ChatStore, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(accent)
                Spacer()
                Text("\(store.localName) · \(store.shortID)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            Text(store.statusLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.selectedMessages.isEmpty ? store.conversations.values.flatMap { $0 } : store.selectedMessages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            if message.kind == .file {
                                Text(message.fileName ?? "file")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(fileCaption(message))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                if message.fileState == .transferring {
                                    ProgressView(value: message.progress)
                                }
                            } else {
                                Text(message.text)
                                    .font(.system(size: 13))
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func fileCaption(_ message: ChatMessage) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(message.fileSize ?? 0), countStyle: .file)
        let state = message.fileState?.rawValue ?? "unknown"
        let pct = Int(message.progress * 100)
        return "\(size) · \(state) · \(pct)%"
    }
}
