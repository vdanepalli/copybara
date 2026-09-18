import SwiftUI

@main
struct CopybaraApp: App {
    @StateObject private var server = ClipServer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(server: server)
                .onAppear { server.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { server.onBecameActive() }
        }
    }
}

struct ContentView: View {
    @ObservedObject var server: ClipServer

    var body: some View {
        VStack(spacing: 24) {
            Text("Copybara 🦫")
                .font(.largeTitle.bold())

            statusCard

            if server.hasPending {
                Button {
                    server.applyPendingNow()
                } label: {
                    Label("Apply latest clip to clipboard", systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if !server.lastReceived.isEmpty {
                receivedCard
            }

            if !server.debugInfo.isEmpty {
                Text(server.debugInfo)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            Text("Tip: keep Copybara in Split View next to GoodNotes — then copies from your Mac land on the clipboard automatically. Otherwise, tap into Copybara to apply the latest clip, then paste.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(server.isPeerConnected ? Color.green : (server.isRunning ? Color.orange : Color.red))
                .frame(width: 14, height: 14)
            Text(server.statusText)
                .font(.headline)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var receivedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last received")
                .font(.caption).foregroundStyle(.secondary)
            Text(server.lastReceived)
                .font(.body)
                .lineLimit(3)
            if let at = server.lastReceivedAt {
                Text(at.formatted(date: .omitted, time: .standard))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
