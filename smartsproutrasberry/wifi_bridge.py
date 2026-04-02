"""
wifi_bridge.py — Smart Sprout Wi-Fi Manager Bridge
====================================================
Runs a lightweight local HTTP server on port 7788.
The Flutter Linux app sends requests here to scan,
connect, forget, and check Wi-Fi status via nmcli.

Start this script alongside main.py on the Raspberry Pi.
It is automatically launched by the systemd service.
"""

import subprocess
import json
import re
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

PORT = 7788


def _run(cmd: list[str]) -> tuple[str, str, int]:
    """Run a shell command and return (stdout, stderr, returncode)."""
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout.strip(), result.stderr.strip(), result.returncode


def scan_wifi() -> list[dict]:
    """Return a sorted list of nearby Wi-Fi networks with signal strength."""
    stdout, _, _ = _run([
        "nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY,IN-USE",
        "dev", "wifi", "list", "--rescan", "yes"
    ])
    networks = []
    seen = set()
    for line in stdout.splitlines():
        parts = line.split(":")
        if len(parts) < 4:
            continue
        ssid, signal, security, in_use = parts[0], parts[1], parts[2], parts[3]
        if not ssid or ssid in seen:
            continue
        seen.add(ssid)
        try:
            signal_int = int(signal)
        except ValueError:
            signal_int = 0

        if signal_int >= 70:
            strength = "strong"
        elif signal_int >= 40:
            strength = "medium"
        else:
            strength = "weak"

        networks.append({
            "ssid": ssid,
            "signal": signal_int,
            "strength": strength,
            "secured": security not in ("", "--"),
            "connected": in_use == "*",
        })

    # Sort: connected first, then by signal strength
    networks.sort(key=lambda x: (-int(x["connected"]), -x["signal"]))
    return networks


def connect_wifi(ssid: str, password: str) -> dict:
    """Connect to a Wi-Fi network. Returns success/failure with a message."""
    if password:
        stdout, stderr, code = _run([
            "nmcli", "dev", "wifi", "connect", ssid,
            "password", password
        ])
    else:
        stdout, stderr, code = _run([
            "nmcli", "dev", "wifi", "connect", ssid
        ])

    if code == 0:
        return {"success": True, "message": f"Connected to {ssid}"}
    else:
        msg = stderr or stdout or "Unknown error"
        return {"success": False, "message": msg}


def forget_wifi(ssid: str) -> dict:
    """Remove a saved Wi-Fi connection profile."""
    stdout, stderr, code = _run([
        "nmcli", "connection", "delete", ssid
    ])
    if code == 0:
        return {"success": True, "message": f"Forgot {ssid}"}
    else:
        return {"success": False, "message": stderr or stdout}


def current_status() -> dict:
    """Return the currently connected Wi-Fi SSID and connection state."""
    stdout, _, code = _run([
        "nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"
    ])
    for line in stdout.splitlines():
        parts = line.split(":")
        if len(parts) >= 2 and parts[0] == "yes":
            return {"connected": True, "ssid": parts[1]}
    return {"connected": False, "ssid": ""}


class WifiBridgeHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Suppress HTTP request logs to keep the console clean
        pass

    def _send_json(self, data: dict, status: int = 200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)

        if path == "/scan":
            self._send_json({"networks": scan_wifi()})

        elif path == "/status":
            self._send_json(current_status())

        elif path == "/connect":
            ssid = params.get("ssid", [""])[0]
            password = params.get("password", [""])[0]
            if not ssid:
                self._send_json({"success": False, "message": "SSID required"}, 400)
            else:
                self._send_json(connect_wifi(ssid, password))

        elif path == "/forget":
            ssid = params.get("ssid", [""])[0]
            if not ssid:
                self._send_json({"success": False, "message": "SSID required"}, 400)
            else:
                self._send_json(forget_wifi(ssid))

        else:
            self._send_json({"error": "Unknown endpoint"}, 404)


def start_bridge():
    server = HTTPServer(("127.0.0.1", PORT), WifiBridgeHandler)
    print(f"[WiFi Bridge] Running on http://127.0.0.1:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    start_bridge()
