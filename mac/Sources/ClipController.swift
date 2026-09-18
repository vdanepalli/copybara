import AppKit
import Network
import Combine

/// Watches the Mac clipboard and pushes changes to the iPad over the LAN.
///
/// Role: the Mac is the *client*. The iPad advertises a Bonjour service and
/// this browses for it, connects, and sends length-prefixed encrypted messages
/// whenever the clipboard changes.
@MainActor
final class ClipController: ObservableObject {
    @Published var isConnected = false
    @Published var statusText = "Looking for iPad…"
    @Published var lastSent = ""
    @Published var enabled = true {
        didSet { if enabled { sendCurrentClipboard(force: true) } }
    }

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var pollTimer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let queue = DispatchQueue(label: "copybara.net")

    init() {
        startBrowsing()
        startPolling()
    }

    // MARK: Bonjour discovery

    private func startBrowsing() {
        let params = NWParameters()
        let browser = NWBrowser(
            for: .bonjour(type: CopybaraProtocol.serviceType, domain: nil),
            using: params
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            guard let result = results.first else { return }
            Task { @MainActor in
                if self.connection == nil {
                    self.connect(to: result.endpoint)
                }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in self?.restartBrowsingSoon() }
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func restartBrowsingSoon() {
        browser?.cancel()
        browser = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.startBrowsing()
        }
    }

    // MARK: Connection

    private func connect(to endpoint: NWEndpoint) {
        statusText = "Connecting…"
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.statusText = "Connected to iPad"
                    self.sendCurrentClipboard(force: true)
                case .failed, .cancelled:
                    self.isConnected = false
                    self.statusText = "Disconnected — searching…"
                    self.connection = nil
                    self.restartBrowsingSoon()
                case .waiting(let err):
                    self.statusText = "Waiting: \(err.localizedDescription)"
                    // A stuck connection won't recover on its own — drop it and re-discover.
                    self.connection?.cancel()
                    self.connection = nil
                    self.isConnected = false
                    self.restartBrowsingSoon()
                default:
                    break
                }
            }
        }
        connection = conn
        conn.start(queue: queue)
    }

    // MARK: Clipboard polling

    private func startPolling() {
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkClipboard() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func checkClipboard() {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        sendCurrentClipboard(force: false)
    }

    func sendCurrentClipboard(force: Bool) {
        guard enabled, isConnected, let connection else { return }
        guard let message = Self.readPasteboard(), !message.isEmpty else { return }
        guard let json = try? JSONEncoder().encode(message),
              let sealed = try? CopybaraProtocol.encrypt(json) else { return }
        let framed = Framing.frame(sealed)
        connection.send(content: framed, completion: .contentProcessed { _ in })
        lastSent = message.summary
    }

    // MARK: Pasteboard reading

    private static func readPasteboard() -> ClipMessage? {
        let pb = NSPasteboard.general
        var msg = ClipMessage()

        if let text = pb.string(forType: .string) { msg.text = text }
        if let rtf = pb.data(forType: .rtf) { msg.rtfBase64 = rtf.base64EncodedString() }
        if let html = pb.string(forType: .html) { msg.html = html }

        if let png = pb.data(forType: .png) {
            msg.pngBase64 = png.base64EncodedString()
        } else if let tiff = pb.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) {
            msg.pngBase64 = png.base64EncodedString()
        }

        return msg.isEmpty ? nil : msg
    }
}
