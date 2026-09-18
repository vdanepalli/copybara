import Foundation
import CryptoKit

// MARK: - Shared wire protocol (keep identical on Mac + iPad)

enum CopybaraProtocol {
    /// Bonjour service this iPad advertises and the Mac browses for.
    static let serviceType = "_copybara._tcp"

    /// Pre-shared secret. CHANGE THIS to your own phrase and use the SAME
    /// value in the Mac app's Protocol.swift.
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

    var summary: String {
        if let t = text, !t.isEmpty {
            let oneLine = t.replacingOccurrences(of: "\n", with: " ")
            return oneLine.count > 60 ? String(oneLine.prefix(60)) + "…" : oneLine
        }
        if pngBase64 != nil { return "🖼 image" }
        if rtfBase64 != nil || html != nil { return "styled text" }
        return "empty"
    }
}
