# Copybara wire protocol

Both apps share an identical `Protocol.swift` (Mac: `mac/Sources/Protocol.swift`,
iPad: `ios/Sources/Protocol.swift`). Keep them in sync.

## Roles

- **iPad = server.** Advertises a Bonjour service and listens for connections.
- **Mac = client.** Browses for the service, connects, and pushes clipboard
  changes. (One-directional: Mac → iPad only.)

## Discovery

- Bonjour service type: `_copybara._tcp` (constant `CopybaraProtocol.serviceType`).
- The iPad advertises using the device name; the Mac browses and connects to the
  first result. Both list the service in `NSBonjourServices` and declare
  `NSLocalNetworkUsageDescription` (required for local-network access).

## Transport & framing

- Plain TCP via Apple's `Network` framework (`NWListener` / `NWConnection`).
- Each message is length-prefixed:

  ```
  [ 4-byte big-endian UInt32 length ][ payload of that length ]
  ```

- The iPad reads exactly 4 bytes, then exactly `length` bytes, then repeats.

## Payload

- `payload` = `ChaChaPoly.seal(json).combined`, where `json` is a UTF-8 encoded
  `ClipMessage`.
- Key = `SHA256(sharedSecret)` as a `SymmetricKey`. Change `sharedSecret` in both
  files to your own phrase; only devices with the same secret can talk.

### `ClipMessage`

```swift
struct ClipMessage: Codable {
    var text: String?        // public.utf8-plain-text
    var rtfBase64: String?   // public.rtf (base64 of the RTF data)
    var html: String?        // public.html
    var pngBase64: String?   // public.png (base64 of the PNG data)
}
```

Any subset may be present. The Mac includes every representation the system
clipboard offers (so paste-and-match-style and code formatting survive); images
are converted to PNG (from TIFF if needed).

## Applying on the iPad

The received representations are written as a single `UIPasteboard` item keyed by
their UTIs, using `UIPasteboard.general.items = [item]` (a hard replace, so a
previous image never lingers under new text).

**Constraint:** the write only succeeds while the app is *active* (foreground /
Split View). See [DESIGN-NOTES.md](DESIGN-NOTES.md).
