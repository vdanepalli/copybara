import Foundation
import CryptoKit

// MARK: - Shared wire protocol (keep identical on Mac + iPad)

enum CopybaraProtocol {
    /// Bonjour service the iPad advertises and the Mac browses for.
    static let serviceType = "_copybara._tcp"

    /// Pre-shared secret. CHANGE THIS to your own phrase and use the SAME
    /// value in the iPad app's Protocol.swift. Everything is encrypted with a
    /// key derived from this, so only your two devices can talk.
    static let sharedSecret = "copybara-change-me-please"

    static var key: SymmetricKey {
        let digest = SHA256.hash(data: Data(sharedSecret.utf8))
        return SymmetricKey(data: Data(digest))
    }

    static func encrypt(_ plaintext: Data) throws -> Data {
        try ChaChaPoly.seal(plaintext, using: key).combined
    }

    static func decrypt(_ data: Data) throws -> Data {
        let box = try ChaChaPoly.SealedBox(combined: data)
        return try ChaChaPoly.open(box, using: key)
    }
}

/// One clipboard event. Any subset of representations may be present.
struct ClipMessage: Codable {
    var text: String?
    var rtfBase64: String?
    var html: String?
    var pngBase64: String?

    var isEmpty: Bool {
        text == nil && rtfBase64 == nil && html == nil && pngBase64 == nil
    }

    /// Short human summary for status UI.
    var summary: String {
        if let t = text, !t.isEmpty {
            let oneLine = t.replacingOccurrences(of: "\n", with: " ")
            return oneLine.count > 40 ? String(oneLine.prefix(40)) + "…" : oneLine
        }
        if pngBase64 != nil { return "🖼 image" }
        if rtfBase64 != nil || html != nil { return "styled text" }
        return "empty"
    }
}

// MARK: - Length-prefixed framing

enum Framing {
    /// 4-byte big-endian length + payload.
    static func frame(_ payload: Data) -> Data {
        var len = UInt32(payload.count).bigEndian
        var out = Data()
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }
}
