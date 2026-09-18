"""
Copybara — Windows sender (Windows -> iPad clipboard sync).

Watches the Windows clipboard and pushes changes to the Copybara iPad app over
the LAN, using the exact same wire protocol as the Mac agent:
  - discovers the iPad via Bonjour service "_copybara._tcp"
  - encrypts each clip with ChaCha20-Poly1305 under SHA256(shared secret)
  - sends length-prefixed frames: 4-byte big-endian length + ciphertext

No admin rights needed. Set up with setup.bat (isolated .venv in this folder),
then start.bat / stop.bat / status.bat, or run-console.bat to watch live.

The iPad still only *applies* clips while it is the active app — keep Copybara
in Split View next to GoodNotes for hands-free paste (same as with the Mac).
"""

import base64
import hashlib
import io
import json
import os
import socket
import struct
import sys
import time

from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

import win32clipboard as clip
from PIL import ImageGrab, Image

from zeroconf import Zeroconf, ServiceBrowser, ServiceListener

# ---------------------------------------------------------------------------
# Config — must match the Mac/iPad apps' Protocol.swift
# ---------------------------------------------------------------------------
SHARED_SECRET = "copybara-change-me-please"   # change in ALL THREE apps to match
SERVICE_TYPE = "_copybara._tcp.local."
POLL_SECONDS = 0.4

# Optional fallback if Bonjour discovery fails on your network:
# set these to the iPad's Wi-Fi IP and the port the app advertises.
FALLBACK_HOST = ""     # e.g. "192.168.1.42"
FALLBACK_PORT = 0

KEY = hashlib.sha256(SHARED_SECRET.encode("utf-8")).digest()
CF_HTML = clip.RegisterClipboardFormat("HTML Format")


# ---------------------------------------------------------------------------
# Crypto + framing (mirror of the Swift side)
# ---------------------------------------------------------------------------
def encrypt(obj: dict) -> bytes:
    data = json.dumps(obj).encode("utf-8")
    nonce = os.urandom(12)
    ct = ChaCha20Poly1305(KEY).encrypt(nonce, data, None)  # ciphertext + tag
    return nonce + ct                                       # == CryptoKit .combined


def frame(payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + payload


# ---------------------------------------------------------------------------
# Clipboard reading
# ---------------------------------------------------------------------------
def _open_clipboard(retries=8):
    for _ in range(retries):
        try:
            clip.OpenClipboard()
            return True
        except Exception:
            time.sleep(0.05)
    return False


def _extract_html(raw) -> str | None:
    if raw is None:
        return None
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8", "replace")
    s = raw.find("<!--StartFragment-->")
    e = raw.find("<!--EndFragment-->")
    if s != -1 and e != -1:
        return raw[s + len("<!--StartFragment-->"): e].strip()
    lt = raw.find("<")
    return raw[lt:] if lt != -1 else None


def read_clipboard() -> dict | None:
    msg: dict = {}

    if _open_clipboard():
        try:
            if clip.IsClipboardFormatAvailable(clip.CF_UNICODETEXT):
                try:
                    text = clip.GetClipboardData(clip.CF_UNICODETEXT)
                    if text:
                        msg["text"] = text
                except Exception:
                    pass
            if clip.IsClipboardFormatAvailable(CF_HTML):
                try:
                    html = _extract_html(clip.GetClipboardData(CF_HTML))
                    if html:
                        msg["html"] = html
                except Exception:
                    pass
        finally:
            clip.CloseClipboard()

    # Image via Pillow (manages the clipboard itself, so do it after closing).
    try:
        im = ImageGrab.grabclipboard()
        if isinstance(im, Image.Image):
            buf = io.BytesIO()
            im.convert("RGBA").save(buf, "PNG")
            msg["pngBase64"] = base64.b64encode(buf.getvalue()).decode("ascii")
    except Exception:
        pass

    return msg or None


def clipboard_seq() -> int:
    try:
        return clip.GetClipboardSequenceNumber()
    except Exception:
        return 0


# ---------------------------------------------------------------------------
# Bonjour discovery
# ---------------------------------------------------------------------------
class _Listener(ServiceListener):
    def __init__(self):
        self.found = None

    def _resolve(self, zc, type_, name):
        info = zc.get_service_info(type_, name, timeout=3000)
        if info and info.parsed_addresses():
            ipv4 = [a for a in info.parsed_addresses() if ":" not in a]
            ip = ipv4[0] if ipv4 else info.parsed_addresses()[0]
            self.found = (ip, info.port)

    def add_service(self, zc, type_, name):
        self._resolve(zc, type_, name)

    def update_service(self, zc, type_, name):
        self._resolve(zc, type_, name)

    def remove_service(self, zc, type_, name):
        pass


def discover(timeout=8):
    zc = Zeroconf()
    listener = _Listener()
    ServiceBrowser(zc, SERVICE_TYPE, listener)
    t0 = time.time()
    while time.time() - t0 < timeout and not listener.found:
        time.sleep(0.2)
    zc.close()
    return listener.found


def find_ipad():
    target = discover()
    if target:
        return target
    if FALLBACK_HOST and FALLBACK_PORT:
        print(f"[copybara] Bonjour found nothing; using fallback {FALLBACK_HOST}:{FALLBACK_PORT}")
        return (FALLBACK_HOST, FALLBACK_PORT)
    return None


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
def summary(msg: dict) -> str:
    if msg.get("text"):
        t = msg["text"].replace("\n", " ")
        return (t[:50] + "...") if len(t) > 50 else t
    if msg.get("pngBase64"):
        return "[image]"
    if msg.get("html"):
        return "styled text"
    return "empty"


def serve_once():
    target = find_ipad()
    if not target:
        print("[copybara] iPad not found on the network. Is the Copybara app open on the iPad,"
              " and are both devices on the same Wi-Fi? Retrying...")
        time.sleep(3)
        return

    host, port = target
    print(f"[copybara] connecting to iPad at {host}:{port} ...")
    sock = socket.create_connection((host, port), timeout=8)
    sock.settimeout(None)
    print("[copybara] connected. Copy anything on Windows; paste on the iPad (Split View).")

    last_seq = None
    try:
        # Send whatever is currently on the clipboard right away.
        msg = read_clipboard()
        if msg:
            sock.sendall(frame(encrypt(msg)))
            print(f"[copybara] sent: {summary(msg)}")
        last_seq = clipboard_seq()

        while True:
            time.sleep(POLL_SECONDS)
            seq = clipboard_seq()
            if seq == last_seq:
                continue
            last_seq = seq
            msg = read_clipboard()
            if not msg:
                continue
            sock.sendall(frame(encrypt(msg)))
            print(f"[copybara] sent: {summary(msg)}")
    finally:
        try:
            sock.close()
        except Exception:
            pass


def main():
    # Force UTF-8 stdio so printing copied text (emoji, accents) never crashes,
    # even under the Microsoft Store Python's cp1252 default.
    for _s in (sys.stdout, sys.stderr):
        try:
            _s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    print("Copybara - Windows to iPad clipboard sender")
    print("Press Ctrl+C to quit.\n")
    while True:
        try:
            serve_once()
        except KeyboardInterrupt:
            print("\n[copybara] bye")
            sys.exit(0)
        except Exception as e:
            print(f"[copybara] disconnected ({e}); reconnecting...")
            time.sleep(2)


if __name__ == "__main__":
    main()
