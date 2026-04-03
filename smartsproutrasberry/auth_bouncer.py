"""
Smart Sprout — Pi-Bouncer Authentication Daemon
──────────────────────────────────────────────────────────
Runs as a daemon thread inside main.py.

Responsibilities:
  1. Listen to Firestore `login_requests` collection for
     documents belonging to THIS device (DEVICE_ID filter).
  2. Hash the incoming PIN and compare against the locally
     stored SHA-256 hash from device_config.json.
  3. Enforce in-memory rate limiting:
       - 5 failed attempts → 15-minute lockout per deviceId.
       - Passive expiry — no background thread required.
  4. On success: mint a Firebase Custom Token via Admin SDK
     and write it back as status="approved".
  5. On failure: write status="error" or "rate_limited".

Security model:
  - PIN comparison happens ONLY on the Pi (trusted hardware).
  - The Flutter app never reads the stored hash.
  - The Admin SDK bypasses all Firestore Security Rules,
    so the Pi's writes are always authoritative.
  - Rate limit state is in-memory (resets on Pi reboot),
    which is acceptable — a reboot is a physical action.
──────────────────────────────────────────────────────────
"""

import hashlib
import threading
import time
import config

from firebase_admin import auth as firebase_auth, firestore

# ═══════════════════════════════════════════════════════
# Rate Limit Store
# ═══════════════════════════════════════════════════════
# Structure: { deviceId: {"failures": int, "locked_until": float} }
# Thread-safe via _rl_lock.

_rate_limit_store: dict = {}
_rl_lock = threading.Lock()

_MAX_FAILURES    = 5
_LOCKOUT_SECONDS = 900   # 15 minutes


# ═══════════════════════════════════════════════════════
# PIN Hashing
# ═══════════════════════════════════════════════════════

def _hash_pin(raw_pin: str) -> str:
    """SHA-256 hash of the raw PIN string. Returns a hex digest."""
    return hashlib.sha256(raw_pin.encode("utf-8")).hexdigest()


def _get_stored_hash() -> str:
    """
    Reads the hashed_pin from device_config.json.
    Runs the one-time migration if only plaintext 'password' exists.
    """
    cfg = config._load_device_config()

    if "hashed_pin" in cfg:
        return cfg["hashed_pin"]

    # ── One-time migration: hash the plaintext password ──
    plaintext = cfg.get("password", "")
    if plaintext:
        hashed = _hash_pin(plaintext)
        cfg["hashed_pin"] = hashed
        # Remove plaintext to prevent future exposure
        cfg.pop("password", None)
        config._save_device_config(cfg)
        print(f"[AUTH_BOUNCER] ✅ PIN migrated to SHA-256 hash. Plaintext removed.")
        return hashed

    print("[AUTH_BOUNCER] ⚠️  WARNING: No PIN found in device_config.json!")
    return ""


# ═══════════════════════════════════════════════════════
# Rate Limiting
# ═══════════════════════════════════════════════════════

def _is_rate_limited(device_id: str) -> tuple:
    """
    Returns (is_locked: bool, seconds_remaining: float).
    Expiry is passive — checks time.time() vs locked_until.
    """
    with _rl_lock:
        record = _rate_limit_store.get(device_id, {})
        locked_until = record.get("locked_until", 0.0)
        if locked_until and time.time() < locked_until:
            remaining = locked_until - time.time()
            return True, remaining
        # Auto-expire: clear lock if window has passed
        if locked_until and time.time() >= locked_until:
            _rate_limit_store.pop(device_id, None)
        return False, 0.0


def _record_failure(device_id: str):
    """Increments the failure counter. Locks on 5th failure."""
    with _rl_lock:
        record = _rate_limit_store.setdefault(device_id, {"failures": 0, "locked_until": 0.0})
        record["failures"] += 1
        print(f"[AUTH_BOUNCER] ❌ Failed attempt #{record['failures']} for {device_id}")
        if record["failures"] >= _MAX_FAILURES:
            record["locked_until"] = time.time() + _LOCKOUT_SECONDS
            print(f"[AUTH_BOUNCER] 🔒 {device_id} RATE LIMITED for {_LOCKOUT_SECONDS // 60} minutes.")


def _reset_failures(device_id: str):
    """Clears the failure counter after a successful login."""
    with _rl_lock:
        _rate_limit_store.pop(device_id, None)
        print(f"[AUTH_BOUNCER] ✅ Failure counter reset for {device_id}")


# ═══════════════════════════════════════════════════════
# Core Request Handler
# ═══════════════════════════════════════════════════════

def _handle_request(db, doc_ref, doc_id: str, data: dict):
    """
    Validates a single login_request document.
    Writes the result (approved / error / rate_limited) back to Firestore.
    All exceptions are caught to prevent the listener thread from crashing.
    """
    device_id = data.get("deviceId", "")
    raw_pin   = data.get("pin", "")
    status    = data.get("status", "")

    # Guard: only process requests for THIS device
    if device_id != config.DEVICE_ID:
        return

    # Guard: only process pending requests
    if status != "pending":
        return

    print(f"[AUTH_BOUNCER] 🔑 Processing login request {doc_id} for {device_id}")

    try:
        # ── Step 1: Rate limit check ──
        locked, remaining = _is_rate_limited(device_id)
        if locked:
            locked_until_ts = time.time() + remaining
            print(f"[AUTH_BOUNCER] ⛔ {device_id} is rate limited. {remaining:.0f}s remaining.")
            doc_ref.update({
                "status":       "rate_limited",
                "locked_until": int(locked_until_ts),
                "error":        f"Too many failed attempts. Try again in {int(remaining // 60) + 1} minute(s).",
                "processedAt":  firestore.SERVER_TIMESTAMP,
            })
            return

        # ── Step 2: PIN verification ──
        stored_hash = _get_stored_hash()
        incoming_hash = _hash_pin(raw_pin)

        if not stored_hash:
            print("[AUTH_BOUNCER] ⚠️  Cannot verify PIN — no stored hash.")
            doc_ref.update({
                "status":      "error",
                "error":       "Device configuration error. Contact admin.",
                "processedAt": firestore.SERVER_TIMESTAMP,
            })
            return

        if incoming_hash != stored_hash:
            _record_failure(device_id)
            locked_after, rem_after = _is_rate_limited(device_id)
            if locked_after:
                doc_ref.update({
                    "status":       "rate_limited",
                    "locked_until": int(time.time() + rem_after),
                    "error":        f"Too many failed attempts. Try again in {int(rem_after // 60) + 1} minute(s).",
                    "processedAt":  firestore.SERVER_TIMESTAMP,
                })
            else:
                doc_ref.update({
                    "status":      "error",
                    "error":       "Incorrect PIN.",
                    "processedAt": firestore.SERVER_TIMESTAMP,
                })
            return

        # ── Step 3: Mint Firebase Custom Token ──
        # UID is set to device_id so FirebaseAuth.currentUser.uid == deviceId.
        # This allows Firestore Security Rules to use:
        #   request.auth.uid == deviceId
        print(f"[AUTH_BOUNCER] 🎫 Minting Custom Token for UID={device_id}")
        custom_token_bytes = firebase_auth.create_custom_token(device_id)

        # create_custom_token returns bytes — decode for Firestore string storage
        if isinstance(custom_token_bytes, bytes):
            custom_token = custom_token_bytes.decode("utf-8")
        else:
            custom_token = str(custom_token_bytes)

        # ── Step 4: Write approval back to Firestore ──
        doc_ref.update({
            "status":      "approved",
            "token":       custom_token,
            "processedAt": firestore.SERVER_TIMESTAMP,
        })

        _reset_failures(device_id)
        print(f"[AUTH_BOUNCER] ✅ Login APPROVED for {device_id}. Token issued.")

    except Exception as e:
        print(f"[AUTH_BOUNCER] ❌ Exception handling request {doc_id}: {e}")
        try:
            doc_ref.update({
                "status":      "error",
                "error":       "Internal authentication error. Please try again.",
                "processedAt": firestore.SERVER_TIMESTAMP,
            })
        except Exception as write_err:
            print(f"[AUTH_BOUNCER] ⚠️  Could not write error status: {write_err}")


# ═══════════════════════════════════════════════════════
# Firestore Snapshot Listener
# ═══════════════════════════════════════════════════════

def _on_login_snapshot(db, col_snapshot, changes, read_time):
    """
    Called by Firestore on_snapshot whenever login_requests changes.
    Only ADDED documents are processed — UPDATE and REMOVED are ignored.
    This prevents re-processing when the Pi writes the token back (UPDATE).
    """
    for change in changes:
        if change.type.name != "ADDED":
            continue
        try:
            doc_id  = change.document.id
            data    = change.document.to_dict() or {}
            doc_ref = change.document.reference
            _handle_request(db, doc_ref, doc_id, data)
        except Exception as e:
            print(f"[AUTH_BOUNCER] ⚠️  Listener error on doc {change.document.id}: {e}")


# ═══════════════════════════════════════════════════════
# Public Entry Point
# ═══════════════════════════════════════════════════════

def start_auth_bouncer(db) -> object:
    """
    Attaches a Firestore on_snapshot listener to the login_requests collection.
    Filters server-side for documents where deviceId == DEVICE_ID.

    Called from main.py after firebase_manager.init_firebase() succeeds.
    Returns the listener handle (call .unsubscribe() to stop).
    """
    print(f"[AUTH_BOUNCER] 🚀 Starting Pi-Bouncer for device: {config.DEVICE_ID}")

    # Run one-time PIN migration on startup
    _get_stored_hash()

    try:
        login_ref = db.collection("login_requests")

        def _snapshot_callback(col_snapshot, changes, read_time):
            _on_login_snapshot(db, col_snapshot, changes, read_time)

        listener = login_ref.on_snapshot(_snapshot_callback)
        print("[AUTH_BOUNCER] ✅ Listening for login requests.")
        return listener

    except Exception as e:
        print(f"[AUTH_BOUNCER] ❌ Failed to start listener: {e}")
        return None
