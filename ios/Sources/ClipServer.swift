import Foundation
import Network
import Combine
import UIKit
import UniformTypeIdentifiers

/// The iPad side. Advertises a Bonjour service, accepts the Mac's connection,
/// and writes each received clipboard message into `UIPasteboard.general`.
///
/// IMPORTANT iOS reality: the general pasteboard can only be written while this
/// app is the *active* (foreground) app — a backgrounded app gets
/// "Pasteboard is not available at this time". Since we can only act when
/// active, there's no point keeping alive in the background (it would only burn
/// battery), so we let iOS suspend us normally. We buffer the latest message and
/// apply it:
///   • immediately, if the app is currently active (incl. Split View), or
///   • when the app next becomes active (reconnect → Mac re-pushes clipboard).
/// Tip: keep Copybara in Split View next to GoodNotes → both are active at once
/// → clips land on the clipboard with no tap.
@MainActor
final class ClipServer: ObservableObject {
    @Published var isRunning = false
    @Published var isPeerConnected = false
    @Published var statusText = "Starting…"
    @Published var lastReceived = ""
    @Published var lastReceivedAt: Date?
    @Published var debugInfo = ""
    /// True when a clip has arrived but hasn't been written to the clipboard yet
    /// (because the app wasn't active). Cleared once applied.
    @Published var hasPending = false

    private var pending: ClipMessage?
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "copybara.listener")

    func start() {
        startListener()
    }

    /// Call when the app becomes active. Because iOS suspends us in the
    /// background (we deliberately don't keep alive — see note below), the
    /// listener/connection may have been torn down. Re-advertise if we're not
    /// currently connected so the Mac rediscovers us and re-pushes the current
    /// clipboard; then apply anything already buffered.
    func onBecameActive() {
        if !isPeerConnected { restartListener() }
        applyPendingIfActive()
    }

    private func restartListener() {
        listener?.cancel()
        listener = nil
        for (_, c) in connections { c.cancel() }
        connections.removeAll()
        isPeerConnected = false
        startListener()
    }

    private func startListener() {
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let listener = try NWListener(using: params)
            listener.service = NWListener.Service(
                name: UIDevice.current.name,
                type: CopybaraProtocol.serviceType
            )
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.statusText = "Waiting for Mac…"
                    case .failed:
                        self.isRunning = false
                        self.statusText = "Listener failed — retrying…"
                        self.restartSoon()
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            statusText = "Could not start: \(error.localizedDescription)"
            restartSoon()
        }
    }

    private func restartSoon() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.startListener()
        }
    }

    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        connections[id] = conn
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isPeerConnected = true
                    self.statusText = "Connected to Mac"
                case .failed, .cancelled:
                    self.connections[id] = nil
                    self.isPeerConnected = !self.connections.isEmpty
                    if !self.isPeerConnected { self.statusText = "Waiting for Mac…" }
                default:
                    break
                }
            }
        }
        conn.start(queue: queue)
        receiveFrame(on: conn)
    }

    // MARK: Length-prefixed receive (4-byte big-endian length + payload)

    private nonisolated func receiveFrame(on conn: NWConnection) {
        receiveExactly(4, on: conn) { [weak self] header in
            guard let self, let header else { return }
            let len = header.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
            guard len > 0, len < 50_000_000 else { self.receiveFrame(on: conn); return }
            self.receiveExactly(Int(len), on: conn) { payload in
                if let payload { Task { @MainActor in self.handle(payload) } }
                self.receiveFrame(on: conn)
            }
        }
    }

    private nonisolated func receiveExactly(_ count: Int, on conn: NWConnection,
                                            accumulated: Data = Data(),
                                            completion: @escaping (Data?) -> Void) {
        let remaining = count - accumulated.count
        conn.receive(minimumIncompleteLength: 1, maximumLength: remaining) { chunk, _, isComplete, error in
            var acc = accumulated
            if let chunk, !chunk.isEmpty { acc.append(chunk) }
            if acc.count >= count {
                completion(acc)
            } else if isComplete || error != nil {
                completion(nil)
            } else {
                self.receiveExactly(count, on: conn, accumulated: acc, completion: completion)
            }
        }
    }

    // MARK: Handle a message

    private func handle(_ sealed: Data) {
        guard let json = try? CopybaraProtocol.decrypt(sealed),
              let msg = try? JSONDecoder().decode(ClipMessage.self, from: json),
              !msg.isEmpty else { return }
        pending = msg
        lastReceived = msg.summary
        lastReceivedAt = Date()
        applyPendingIfActive()
    }

    /// Called on receive and whenever the app becomes active.
    func applyPendingIfActive() {
        guard pending != nil else { return }
        if UIApplication.shared.applicationState == .active {
            applyPendingNow()
        } else {
            hasPending = true
            debugInfo = "Clip ready — open Copybara (or Split View) to place it on the clipboard."
        }
    }

    /// Force-apply the buffered clip. Only succeeds when the app is active; if it
    /// isn't, iOS rejects the write and we keep the clip pending.
    func applyPendingNow() {
        guard let msg = pending else { return }
        guard UIApplication.shared.applicationState == .active else {
            hasPending = true
            debugInfo = "Bring Copybara to the front to apply."
            return
        }

        var item: [String: Any] = [:]
        if let text = msg.text { item[UTType.utf8PlainText.identifier] = text }
        if let b64 = msg.rtfBase64, let data = Data(base64Encoded: b64) { item[UTType.rtf.identifier] = data }
        if let html = msg.html { item[UTType.html.identifier] = html }
        if let b64 = msg.pngBase64, let data = Data(base64Encoded: b64) { item[UTType.png.identifier] = data }
        guard !item.isEmpty else { return }

        // Hard replace: assigning `items` drops every previous representation
        // (e.g. a stale image) instead of merging.
        UIPasteboard.general.items = [item]
        pending = nil
        hasPending = false
        debugInfo = "✓ on clipboard: \(sent(msg)) — \(msg.summary)"
    }

    private func sent(_ msg: ClipMessage) -> String {
        var t: [String] = []
        if msg.text != nil { t.append("text") }
        if msg.html != nil { t.append("html") }
        if msg.rtfBase64 != nil { t.append("rtf") }
        if msg.pngBase64 != nil { t.append("png") }
        return t.joined(separator: "+")
    }
}
