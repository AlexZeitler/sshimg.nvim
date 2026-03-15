#!/usr/bin/env python3
"""
imgd - sshimg.nvim local daemon
Listens on localhost:9999 for image paste requests from remote Neovim.
Fetches image from local clipboard and transfers to remote via scp.

Usage:
    imgd [--port PORT] [--host HOST]

Requirements:
    - wl-paste (Wayland)
    - scp
"""

import socketserver
import subprocess
import os
import tempfile
import json
import argparse


DEFAULT_PORT = 9999
DEFAULT_HOST = "127.0.0.1"


def get_clipboard_image():
    """Fetch PNG image from local clipboard."""
    # Wayland
    if os.environ.get("WAYLAND_DISPLAY") or os.environ.get("XDG_SESSION_TYPE") == "wayland":
        result = subprocess.run(
            ["wl-paste", "--type", "image/png"],
            capture_output=True,
        )
        if result.returncode != 0:
            return None, f"wl-paste failed: {result.stderr.decode().strip()}"
        if not result.stdout:
            return None, "Clipboard is empty or does not contain an image"
        return result.stdout, None

    return None, "Unsupported platform or display server"


def transfer_image(image_data, remote_host, remote_path):
    """Transfer image data to remote host via scp."""
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp.write(image_data)
        tmp_path = tmp.name

    try:
        result = subprocess.run(
            ["scp", tmp_path, f"{remote_host}:{remote_path}"],
            capture_output=True,
        )
        if result.returncode != 0:
            return False, f"scp failed: {result.stderr.decode().strip()}"
        return True, None
    finally:
        os.unlink(tmp_path)


class ImageHandler(socketserver.StreamRequestHandler):
    def handle(self):
        try:
            raw = self.rfile.readline().strip()
            request = json.loads(raw)

            remote_host = request.get("host")
            remote_path = request.get("path")

            if not remote_host or not remote_path:
                self.respond({"ok": False, "error": "Missing host or path"})
                return

            print(f"[imgd] Request: {remote_host}:{remote_path}", flush=True)

            image_data, err = get_clipboard_image()
            if err:
                print(f"[imgd] Clipboard error: {err}", flush=True)
                self.respond({"ok": False, "error": err})
                return

            print(f"[imgd] Got image ({len(image_data)} bytes), transferring...", flush=True)

            ok, err = transfer_image(image_data, remote_host, remote_path)
            if not ok:
                print(f"[imgd] Transfer error: {err}", flush=True)
                self.respond({"ok": False, "error": err})
                return

            print(f"[imgd] Done: {remote_path}", flush=True)
            self.respond({"ok": True, "path": remote_path})

        except Exception as e:
            self.respond({"ok": False, "error": str(e)})

    def respond(self, data):
        self.wfile.write((json.dumps(data) + "\n").encode())


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


def main():
    parser = argparse.ArgumentParser(description="sshimg.nvim local daemon")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--host", default=DEFAULT_HOST)
    args = parser.parse_args()

    print(f"[imgd] Listening on {args.host}:{args.port}", flush=True)
    with ReusableTCPServer((args.host, args.port), ImageHandler) as server:
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\n[imgd] Stopped", flush=True)


if __name__ == "__main__":
    main()
