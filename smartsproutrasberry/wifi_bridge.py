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
import os
import sqlite3
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

try:
    import firebase_admin
    from firebase_admin import credentials, auth as fb_auth, firestore as fb_firestore

    # main.py already calls firebase_admin.initialize_app() via firebase_manager.
    # We REUSE that existing app here instead of creating a second one.
    # Only initialize if no app exists yet (e.g., when wifi_bridge is run standalone).
    _SERVICE_ACCOUNT = os.path.join(os.path.dirname(__file__), 'firebase-adminsdk.json')
    if not firebase_admin._apps:
        _cred = credentials.Certificate(_SERVICE_ACCOUNT)
        firebase_admin.initialize_app(_cred)
        print('[WiFi Bridge] Initialized Firebase Admin SDK (standalone mode)')
    else:
        print('[WiFi Bridge] Reusing existing Firebase Admin SDK app from main.py')
    _FIREBASE_ADMIN_OK = True
except Exception as _e:
    print(f'[WiFi Bridge] firebase_admin unavailable: {_e}')
    _FIREBASE_ADMIN_OK = False

PORT = 7788

# ── Device ID that owns all data in Firestore ──
_DEVICE_ID = 'SPROUT_A1B2'

# ── Path to the local SQLite database written by local_db.py ──
_DB_PATH = os.path.join(os.path.dirname(__file__), 'telemetry.db')



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


def get_weekly_analytics(cutoff_seconds: int = None) -> list[dict]:
    """
    Aggregates the last 7 calendar days of telemetry from local SQLite.

    Returns a list of 7 dicts in ascending date order (oldest → today):
      [
        {"dayIndex": 0, "avgMoisture": 42.5, "avgTemp": 28.1,
         "hasData": true, "hasFault": false},
        ...
      ]
    dayIndex 0 = 6 days ago, dayIndex 6 = today.

    Args:
        cutoff_seconds: Unix timestamp of the start of the 7-day window,
            as computed by Flutter (local midnight - 6 days).
            When provided, this is used verbatim so the bridge and chart
            labels use the EXACT same day boundary.
    """
    import datetime as _dt

    # Build a slot for each of the 7 days (0 = 6 days ago … 6 = today)
    day_buckets: dict[int, list[dict]] = {i: [] for i in range(7)}

    if cutoff_seconds is not None:
        week_start = int(cutoff_seconds)
        print(f'[WiFi Bridge] /analytics: using Flutter cutoff={week_start}')
    else:
        # Compute LOCAL midnight (not UTC!) so day boundaries match Flutter.
        local_now = _dt.datetime.now()
        local_midnight = _dt.datetime(local_now.year, local_now.month, local_now.day)
        week_start = int(local_midnight.timestamp()) - 6 * 86400
        print(f'[WiFi Bridge] /analytics: computed local week_start={week_start}')

    if not os.path.exists(_DB_PATH):
        return [{'dayIndex': i, 'avgMoisture': 0.0, 'avgTemp': 0.0,
                 'hasData': False, 'hasFault': False}
                for i in range(7)]

    try:
        conn = sqlite3.connect(_DB_PATH, timeout=5)
        conn.execute("PRAGMA journal_mode=WAL;")
        conn.row_factory = sqlite3.Row
        cur = conn.execute(
            """
            SELECT timestamp, moisture_b1, moisture_b2, moisture_b3, temperature
            FROM  telemetry
            WHERE timestamp >= ?
            ORDER BY timestamp ASC
            """,
            (week_start,),
        )
        rows = cur.fetchall()
        conn.close()
    except Exception as e:
        print(f"[WiFi Bridge] Analytics DB error: {e}")
        return [{'dayIndex': i, 'avgMoisture': 0.0, 'avgTemp': 0.0,
                 'hasData': False, 'hasFault': False}
                for i in range(7)]

    for row in rows:
        day_idx = (row['timestamp'] - week_start) // 86400
        if 0 <= day_idx <= 6:
            day_buckets[day_idx].append({
                'b1': row['moisture_b1'],
                'b2': row['moisture_b2'],
                'b3': row['moisture_b3'],
                'temp': row['temperature'],
            })

    result = []
    for i in range(7):
        readings = day_buckets[i]
        if not readings:
            result.append({
                'dayIndex': i,
                'avgMoisture': 0.0,
                'avgTemp': 0.0,
                'hasData': False,
                'hasFault': False,
            })
            continue

        total_m, total_t, m_count, t_count = 0.0, 0.0, 0, 0
        has_fault = False

        for r in readings:
            # Collect valid (>= 0) moisture values, track faults
            bed_vals = [r['b1'], r['b2'], r['b3']]
            valid_beds = [v for v in bed_vals if v >= 0]
            if len(valid_beds) < len(bed_vals):
                has_fault = True  # At least one bed was -1 (fault)
            if valid_beds:
                total_m += sum(valid_beds) / len(valid_beds)
                m_count += 1

            temp = r['temp']
            if temp >= 0:
                total_t += temp
                t_count += 1
            else:
                has_fault = True

        result.append({
            'dayIndex': i,
            'avgMoisture': round(total_m / m_count, 1) if m_count > 0 else 0.0,
            'avgTemp': round(total_t / t_count, 1) if t_count > 0 else 0.0,
            'hasData': True,
            'hasFault': has_fault,
        })

    return result


def get_firebase_custom_token() -> dict:
    """
    Mint a Firebase custom token for the device using the Admin SDK,
    then exchange it for an ID token via the Firebase REST API.
    Returns: {"idToken": "...", "expiresIn": "3600"} or {"error": "..."}
    """
    if not _FIREBASE_ADMIN_OK:
        return {"error": "firebase_admin not available"}

    try:
        # Step 1: Mint a custom token (this is a JWT, NOT an idToken)
        custom_token = fb_auth.create_custom_token(_DEVICE_ID)
        if isinstance(custom_token, bytes):
            custom_token = custom_token.decode('utf-8')

        # Step 2: Exchange custom token for ID token via Firebase REST
        import urllib.request
        api_key = _read_api_key()
        if not api_key:
            return {"error": "Could not read Firebase API key"}

        exchange_url = f'https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key={api_key}'
        payload = json.dumps({"token": custom_token, "returnSecureToken": True}).encode()
        req = urllib.request.Request(exchange_url, data=payload,
                                     headers={'Content-Type': 'application/json'},
                                     method='POST')
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read())
            return {"idToken": result["idToken"], "expiresIn": result.get("expiresIn", "3600")}
    except Exception as e:
        print(f'[WiFi Bridge] Token mint error: {e}')
        return {"error": str(e)}


def _read_api_key() -> str:
    """Read the Firebase API key from the .env file next to this script."""
    env_path = os.path.join(os.path.dirname(__file__), '.env')
    try:
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line.startswith('FIREBASE_API_KEY='):
                    return line.split('=', 1)[1].strip().strip('"').strip("'")
    except Exception:
        pass
    # Fallback: hardcode the web API key (public, not a secret)
    return 'AIzaSyANlBxYFTPv0t7_RuGlRApt_aCtI8M-s44'


def get_analytics_from_cloud(cutoff_seconds: int = None) -> dict:
    """
    Query Firestore using the Admin SDK (bypasses ALL security rules).
    Reads devices/SPROUT_A1B2/telemetry for the last 7 calendar days
    and returns the same day-by-day format as /analytics.

    Args:
        cutoff_seconds: Unix timestamp of the start of the 7-day window,
            as computed by Flutter (DateTime(today).subtract(6 days)).
            When provided, this is used verbatim so the bridge and chart
            labels use the EXACT same boundary — timezone-agnostic.

    Returns {"days": [{"dayIndex": 0, "avgMoisture": X, "avgTemp": Y}, ...]}
    or {"error": "..."} on failure.
    """
    if not _FIREBASE_ADMIN_OK:
        return {"error": "firebase_admin not available"}

    try:
        import datetime as _dt
        db = fb_firestore.client()

        if cutoff_seconds is not None:
            # Use Flutter's own computed cutoff — same local-midnight in flutter
            week_start = int(cutoff_seconds)
            print(f'[WiFi Bridge] /analytics_cloud: using Flutter cutoff={week_start}')
        else:
            # Fallback: compute local midnight on the Pi
            local_now = _dt.datetime.now()
            local_midnight = _dt.datetime(local_now.year, local_now.month, local_now.day)
            week_start = int(local_midnight.timestamp()) - 6 * 86400
            print(f'[WiFi Bridge] /analytics_cloud: computed Pi week_start={week_start}')

        coll_ref = (
            db.collection('devices')
              .document(_DEVICE_ID)
              .collection('telemetry')
              .where('timestamp', '>=', week_start)
              .order_by('timestamp', direction=fb_firestore.Query.DESCENDING)
              .limit(2000)
        )
        docs = coll_ref.stream()

        # Bucket into 7 day slots (0 = 6 days ago, 6 = today)
        day_buckets: dict[int, list[dict]] = {i: [] for i in range(7)}

        for doc in docs:
            d = doc.to_dict()
            ts = d.get('timestamp', 0)
            if not isinstance(ts, (int, float)):
                continue
            day_idx = (int(ts) - week_start) // 86400
            if 0 <= day_idx <= 6:
                day_buckets[day_idx].append(d)

        result = []
        for i in range(7):
            readings = day_buckets[i]
            if not readings:
                result.append({'dayIndex': i, 'avgMoisture': 0.0, 'avgTemp': 0.0,
                               'hasData': False, 'hasFault': False})
                continue

            total_m, total_t, m_count, t_count = 0.0, 0.0, 0, 0
            has_fault = False
            for d in readings:
                try:
                    soil = d.get('soil_moisture', {})
                    all_vals = []
                    if isinstance(soil, dict) and soil:
                        all_vals = [float(v) for v in soil.values()]
                    elif isinstance(soil, list) and soil:
                        all_vals = [float(v) for v in soil]

                    valid_vals = [v for v in all_vals if v >= 0]
                    if len(valid_vals) < len(all_vals):
                        has_fault = True  # At least one bed was -1 (fault)
                    if valid_vals:
                        total_m += sum(valid_vals) / len(valid_vals)
                        m_count += 1

                    temp = float(d.get('temperature', -1))
                    if temp >= 0:
                        total_t += temp
                        t_count += 1
                    else:
                        has_fault = True
                except Exception:
                    pass

            # hasData = True when telemetry docs exist (even if all faulted).
            # hasFault = True when any reading had a -1 sensor value.
            # Fault-only days show as amber dots at 0 on the chart.
            result.append({
                'dayIndex': i,
                'avgMoisture': round(total_m / m_count, 1) if m_count > 0 else 0.0,
                'avgTemp': round(total_t / t_count, 1) if t_count > 0 else 0.0,
                'hasData': True,
                'hasFault': has_fault,
            })


        print(f'[WiFi Bridge] /analytics_cloud: returned {len(result)} day buckets')
        return {'days': result}

    except Exception as e:
        print(f'[WiFi Bridge] /analytics_cloud error: {e}')
        return {'error': str(e)}


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

        elif path == "/analytics":
            # Accept optional cutoff= param so day boundaries match Flutter
            cutoff_param = params.get('cutoff', [None])[0]
            cutoff_seconds = int(cutoff_param) if cutoff_param else None
            self._send_json({"days": get_weekly_analytics(cutoff_seconds=cutoff_seconds)})

        elif path == "/analytics_cloud":
            # Admin SDK → Firestore (bypasses all security rules)
            # Accept optional cutoff= param so Flutter dictates the week boundary
            cutoff_param = params.get('cutoff', [None])[0]
            cutoff_seconds = int(cutoff_param) if cutoff_param else None
            result = get_analytics_from_cloud(cutoff_seconds=cutoff_seconds)
            if 'error' in result:
                self._send_json(result, 500)
            else:
                self._send_json(result)

        elif path == "/token":
            # Mint a real Firebase ID token authenticated as SPROUT_A1B2
            result = get_firebase_custom_token()
            if 'error' in result:
                self._send_json(result, 500)
            else:
                self._send_json(result)

        else:
            self._send_json({"error": "Unknown endpoint"}, 404)


def start_bridge():
    server = HTTPServer(("127.0.0.1", PORT), WifiBridgeHandler)
    print(f"[WiFi Bridge] Running on http://127.0.0.1:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    start_bridge()
