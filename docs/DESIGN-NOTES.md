# Design notes & decisions

Why Copybara is built the way it is — including the dead ends, so we don't repeat
them.

## Goal

Mimic Universal Clipboard **Mac → iPad** when Handoff/Continuity is blocked
(MDM on the Mac). Same Wi-Fi is acceptable; cross-network is a stretch goal.
Primary use: copy on Mac → paste into GoodNotes on iPad.

## Key constraint we discovered (the big one)

**iOS only lets an app write the general pasteboard while it is the *active*
(foreground) app.** A backgrounded app gets:

```
Pasteboard com.apple.UIKit.pboard.general is not available at this time.
```

This was found empirically: the first image (written while the app was in the
foreground right after launch) pasted fine; every later copy silently failed and
the clipboard stayed stuck on that first image. The logs confirmed the write was
rejected.

Consequences:
- True "zero-tap, copy-on-Mac-appears-on-iPad-in-any-app" is **not achievable**
  for a sideloaded third-party app.
- The closest reliable UX is **iPadOS Split View**: both visible apps are
  *active* simultaneously, so with Copybara beside GoodNotes, incoming clips are
  written to the pasteboard with no tap. This is the intended daily workflow.

## Abandoned approach: background-audio keepalive

Originally the iPad app played inaudible looped audio (`AVAudioSession` +
`UIBackgroundModes: [audio]`) to stay alive in the background and receive/apply
clips without being on screen.

**Removed**, because of the constraint above: even kept alive, a backgrounded app
can't *write* the pasteboard, so the keepalive only burned battery and risked
interfering with the user's audio. We now let iOS suspend the app normally.

Replacement behavior: when the app becomes active again it reconnects, and the
Mac **re-pushes the current clipboard on connect** (`sendCurrentClipboard(force:)`
on `.ready`), so the latest copy is applied immediately on return.

## Networking decisions

- **iPad is the server / advertiser, Mac is the client / browser.** The Mac is
  the one generating events, so it initiates; the iPad just needs to be
  discoverable while active.
- **Removed `includePeerToPeer`** from the Mac browser. With it on, discovery
  could return an AWDL/peer-to-peer endpoint that a plain TCP connection couldn't
  reach → connections hung at "Connecting…". Plain Wi-Fi Bonjour is reliable on
  the same LAN.
- Stuck/`waiting` connections are dropped and re-discovered rather than left to
  hang.

## Security

- Everything is encrypted with `ChaChaPoly` under a key derived from a shared
  secret (`SHA256(sharedSecret)`). LAN-only + encrypted; nothing leaves the
  network. The secret is the only thing gating who can push to the iPad.

## Signing / distribution

- Built with a **free Apple ID** (personal team `99V875JU84`). Signature expires
  ~7 days → the iPad app must be re-run from Xcode to refresh. Paid account or
  SideStore/AltStore removes the weekly step.
- Command-line `xcodebuild` can't provision for a free personal team ("No Account
  for Team") — the **first device install must come from the Xcode GUI**.
- The Mac app self-signs (ad-hoc, `CODE_SIGN_IDENTITY = "-"`) and runs locally
  with no team needed.

## Projects

- Generated with **XcodeGen** from `project.yml` in each of `mac/` and `ios/`.
  The `.xcodeproj` files are git-ignored; run `xcodegen generate` after cloning.

## Future: cross-network ("any Wi-Fi")

Add a small self-hosted relay (~$5/mo VPS). Mac and iPad each hold an outbound
connection to it; it forwards the encrypted blobs, so they no longer share a LAN.
The relay only sees ciphertext. On-iPad paste behavior (Split View) is unchanged;
the relay only changes how the two devices reach each other.
