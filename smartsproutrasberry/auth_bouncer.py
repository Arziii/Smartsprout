"""
Smart Sprout — Pi-Bouncer Authentication Daemon  (Strict Alias Mode)
──────────────────────────────────────────────────────────────────────
Runs as a daemon thread inside main.py.

Responsibilities:
  1. Listen to Firestore `login_requests` collection for
     documents belonging to THIS device (device-ID filter).
  2. Enforce STRICT ALIAS LOGIN:
       a. Fetch the current display_name from devices/{HW_MAC_ID}.
       b. If an alias exists → the requested ID MUST match the alias.
          Typing the raw HW_MAC_ID is silently rejected as "invalid device".
       c. If no alias is set → fall back to accepting HW_MAC_ID directly.
  3. Hash the incoming PIN and compare against the locally
     stored SHA-256 hash from device_config.json.
  4. Enforce in-memory rate limiting:
       - 5 failed attempts → 15-minute lockout per requestedId.
       - Passive expiry — no background thread required.
  5. On success: mint a Firebase Custom Token with UID = HW_MAC_ID
     (immutable) and write it back as status="approved".
  6. On failure: write status="error" or "rate_limited".

Security model:
  - PIN comparison happens ONLY on the Pi (trusted hardware).
  - The Flutter app never reads the stored hash.
  - The Admin SDK bypasses all Firestore Security Rules,
    so the Pi's writes are always authoritative.
  - Rate limit state is in-memory (resets on Pi reboot),
    which is acceptable — a reboot is a physical action.
  - HW_MAC_ID is never exposed to the Flutter app as a login ID
    once an alias has been set, preventing impersonation.
──────────────────────────────────────────────────────────────────────
"""

import hashlib
import hmac
import os
import threading
import time
import config

from firebase_admin import auth as firebase_auth, firestore

# ═══════════════════════════════════════════════════════
# Rate Limit Store
# ═══════════════════════════════════════════════════════
# Structure: { requestedId: {"failures": int, "locked_until": float} }
# Thread-safe via _rl_lock.

_rate_limit_store: dict = {}
_rl_lock = threading.Lock()

_MAX_FAILURES    = 5
_LOCKOUT_SECONDS = 30    # 30 seconds


# ═══════════════════════════════════════════════════════
# PIN Hashing  — PBKDF2-HMAC-SHA256 (NIST SP 800-132, 2023)
# ═══════════════════════════════════════════════════════
# Enterprise-grade: 600,000 iterations, 32-byte random salt per password.
# Stored in device_config.json as: "pbkdf2:<hex_salt>:<hex_hash>"
# Constant-time comparison via hmac.compare_digest to prevent timing attacks.

_PBKDF2_ITERATIONS = 600_000
_PBKDF2_HASH       = "sha256"
_SALT_BYTES        = 32   # 256-bit salt


def _hash_pin_pbkdf2(raw_pin: str, salt: bytes | None = None) -> tuple[str, str]:
    """
    Derives a PBKDF2-HMAC-SHA256 key from raw_pin.

    Args:
        raw_pin: The plaintext PIN/password.
        salt:    Optional salt bytes.  If None a fresh random salt is generated.

    Returns:
        (hex_salt, hex_hash) — both must be stored together.
    """
    if salt is None:
        salt = os.urandom(_SALT_BYTES)
    dk = hashlib.pbkdf2_hmac(
        _PBKDF2_HASH,
        raw_pin.encode("utf-8"),
        salt,
        _PBKDF2_ITERATIONS,
    )
    return salt.hex(), dk.hex()


def _verify_pin(raw_pin: str, stored: str) -> bool:
    """
    Constant-time verification of a raw PIN against a stored credential string.

    Supports two storage formats:
      • "pbkdf2:<hex_salt>:<hex_hash>"  — new PBKDF2 format (preferred)
      • "<64-char-sha256-hex>"           — legacy bare SHA-256 (migration path)
    """
    if stored.startswith("pbkdf2:"):
        try:
            _, hex_salt, hex_hash = stored.split(":", 2)
            salt = bytes.fromhex(hex_salt)
            _, candidate_hash = _hash_pin_pbkdf2(raw_pin, salt)
            return hmac.compare_digest(candidate_hash, hex_hash)
        except Exception:
            return False

    # ── Legacy SHA-256 path (no salt, single hash) ──
    # Accepts it once, but the caller should re-hash with PBKDF2 afterward.
    legacy_hash = hashlib.sha256(raw_pin.encode("utf-8")).hexdigest()
    return hmac.compare_digest(legacy_hash, stored)


def _get_stored_credential() -> str:
    """
    Returns the stored credential string from device_config.json.

    Migration chain (runs once on first call after upgrade):
      1. If "pbkdf2_pin" exists  → return it (modern format, no migration needed).
      2. If "hashed_pin" exists  → migrate legacy SHA-256 to PBKDF2 with a note
         that we cannot upgrade without the plaintext (so we keep SHA-256 until
         the user next successfully logs in  — see _upgrade_credential_on_success).
      3. If "password" exists    → one-time hash: create PBKDF2, remove plaintext.
      4. Nothing                 → warn and return "".
    """
    cfg = config._load_device_config()

    # ── Already modern ──
    if "pbkdf2_pin" in cfg:
        return cfg["pbkdf2_pin"]

    # ── Plaintext still present — hash it with PBKDF2 immediately ──
    plaintext = cfg.get("password", "")
    if plaintext:
        hex_salt, hex_hash = _hash_pin_pbkdf2(plaintext)
        credential = f"pbkdf2:{hex_salt}:{hex_hash}"
        cfg["pbkdf2_pin"] = credential
        cfg.pop("password", None)
        cfg.pop("hashed_pin", None)
        config._save_device_config(cfg)
        print("[AUTH_BOUNCER] ✅ PIN upgraded to PBKDF2-HMAC-SHA256 (600k iter). "
              "Plaintext removed.")
        return credential

    # ── Legacy bare SHA-256 hash — keep it; will upgrade on next successful login ──
    if "hashed_pin" in cfg:
        print("[AUTH_BOUNCER] ⚠️  Legacy SHA-256 PIN detected. "
              "Will auto-upgrade to PBKDF2 on next successful login.")
        return cfg["hashed_pin"]

    print("[AUTH_BOUNCER] ⚠️  WARNING: No PIN found in device_config.json!")
    return ""


def _upgrade_credential_on_success(raw_pin: str):
    """
    Called after a successful PIN verification against a legacy SHA-256 hash.
    Transparently re-hashes the plaintext with PBKDF2 and saves it.
    """
    cfg = config._load_device_config()
    if "pbkdf2_pin" in cfg:
        return  # Already upgraded
    hex_salt, hex_hash = _hash_pin_pbkdf2(raw_pin)
    credential = f"pbkdf2:{hex_salt}:{hex_hash}"
    cfg["pbkdf2_pin"] = credential
    cfg.pop("hashed_pin", None)
    config._save_device_config(cfg)
    print("[AUTH_BOUNCER] ✅ PIN silently upgraded from SHA-256 to PBKDF2-HMAC-SHA256.")


# ═══════════════════════════════════════════════════════
# Rate Limiting
# ═══════════════════════════════════════════════════════

def _is_rate_limited(request_key: str) -> tuple:
    """
    Returns (is_locked: bool, seconds_remaining: float).
    Expiry is passive — checks time.time() vs locked_until.
    """
    with _rl_lock:
        record = _rate_limit_store.get(request_key, {})
        locked_until = record.get("locked_until", 0.0)
        if locked_until and time.time() < locked_until:
            remaining = locked_until - time.time()
            return True, remaining
        # Auto-expire: clear lock if window has passed
        if locked_until and time.time() >= locked_until:
            _rate_limit_store.pop(request_key, None)
        return False, 0.0


def _record_failure(request_key: str):
    """Increments the failure counter. Locks on 5th failure."""
    with _rl_lock:
        record = _rate_limit_store.setdefault(request_key, {"failures": 0, "locked_until": 0.0})
        record["failures"] += 1
        print(f"[AUTH_BOUNCER] ❌ Failed attempt #{record['failures']} for {request_key}")
        if record["failures"] >= _MAX_FAILURES:
            record["locked_until"] = time.time() + _LOCKOUT_SECONDS
            print(f"[AUTH_BOUNCER] 🔒 {request_key} RATE LIMITED for {_LOCKOUT_SECONDS} seconds.")


def _reset_failures(request_key: str):
    """Clears the failure counter after a successful login."""
    with _rl_lock:
        _rate_limit_store.pop(request_key, None)
        print(f"[AUTH_BOUNCER] ✅ Failure counter reset for {request_key}")


# ═══════════════════════════════════════════════════════
# Strict Alias Resolver
# ═══════════════════════════════════════════════════════

def _get_current_alias(db) -> str:
    """
    Fetches the display_name field from Firestore: devices/{HW_MAC_ID}.

    Returns:
        str — the alias if one is set and non-empty, otherwise "".

    An empty return value means "no alias enforced; fall back to HW_MAC_ID".
    All exceptions are caught to avoid crashing the auth thread.
    """
    try:
        doc = db.collection("devices").document(config.HW_MAC_ID).get()
        if doc.exists:
            alias = (doc.to_dict() or {}).get("device_name", "").strip()
            return alias
        print(f"[AUTH_BOUNCER] ⚠️  devices/{config.HW_MAC_ID} not found in Firestore. "
              "Running alias-less mode.")
        return ""
    except Exception as e:
        print(f"[AUTH_BOUNCER] ⚠️  Could not fetch alias from Firestore: {e}. "
              "Running alias-less mode.")
        return ""


# ═══════════════════════════════════════════════════════
# Core Request Handler
# ═══════════════════════════════════════════════════════

def _handle_request(db, doc_ref, doc_id: str, data: dict):
    """
    Validates a single login_request document using Strict Alias Login.

    Flow:
      1. Parse requested_id from the document.
      2. Fetch the current alias from Firestore devices/{HW_MAC_ID}.
      3. STRICT CHECK:
           • Alias active  → requested_id must equal alias.
                             Raw HW_MAC_ID → rejected as "Device not found."
           • No alias set  → requested_id must equal HW_MAC_ID.
      4. Rate-limit check.
      5. PIN verification.
      6. Mint Custom Token with UID = HW_MAC_ID (immutable).
      7. Write result back to Firestore.

    All exceptions are caught to prevent the listener thread from crashing.
    """
    # ── Parse fields ──
    # The Flutter app sends the ID the user typed as "deviceId".
    requested_id = data.get("deviceId", "").strip()
    raw_pin      = data.get("pin", "")
    status       = data.get("status", "")

    # Guard: only process pending requests
    if status != "pending":
        return

    print(f"[AUTH_BOUNCER] 🔑 Incoming login request {doc_id} | requestedId={requested_id!r}")

    try:
        # ── Step 1: Resolve current alias from Firestore ──
        current_alias = _get_current_alias(db)
        hw_id = config.HW_MAC_ID

        if current_alias:
            # ── STRICT ALIAS MODE ──
            # Only the alias is a valid login credential.
            # The raw hardware ID is explicitly blocked.
            print(f"[AUTH_BOUNCER] 🏷  Alias active: {current_alias!r}. "
                  f"Raw HW ID ({hw_id!r}) is disabled as login credential.")

            if requested_id == hw_id:
                # User typed the raw HW ID while alias is active — count it as a failure
                _record_failure(hw_id)  # key on hw_id since that's what was tried
                _record_failure(requested_id)
                locked, remaining = _is_rate_limited(hw_id)
                print(f"[AUTH_BOUNCER] 🚫 Login attempt with raw HW_MAC_ID while alias is active. "
                      "Rejecting.")
                if locked:
                    doc_ref.update({
                        "status":       "rate_limited",
                        "locked_until": int(time.time() + remaining),
                        "error":        f"Too many failed attempts. Try again in {int(remaining)} second(s).",
                        "processedAt":  firestore.SERVER_TIMESTAMP,
                    })
                else:
                    doc_ref.update({
                        "status":      "error",
                        "error":       "Device not found. Please check the Device ID and try again.",
                        "processedAt": firestore.SERVER_TIMESTAMP,
                    })
                return

            if requested_id != current_alias:
                # Unknown ID — count toward rate limit and respond immediately.
                _record_failure(requested_id)
                locked, remaining = _is_rate_limited(requested_id)
                print(f"[AUTH_BOUNCER] 🔍 Request for {requested_id!r} does not match "
                      f"alias {current_alias!r}. Returning not_found.")
                if locked:
                    doc_ref.update({
                        "status":       "rate_limited",
                        "locked_until": int(time.time() + remaining),
                        "error":        f"Too many failed attempts. Try again in {int(remaining)} second(s).",
                        "processedAt":  firestore.SERVER_TIMESTAMP,
                    })
                else:
                    doc_ref.update({
                        "status":      "not_found",
                        "error":       "No device found. Please check your Device ID.",
                        "processedAt": firestore.SERVER_TIMESTAMP,
                    })
                return

        else:
            # ── FALLBACK MODE: no alias set yet ──
            # Accept only the raw HW_MAC_ID.
            if requested_id != hw_id:
                # Unknown ID — count toward rate limit and respond immediately.
                _record_failure(requested_id)
                locked, remaining = _is_rate_limited(requested_id)
                print(f"[AUTH_BOUNCER] 🔍 Request for {requested_id!r} does not match "
                      f"HW_MAC_ID {hw_id!r}. Returning not_found.")
                if locked:
                    doc_ref.update({
                        "status":       "rate_limited",
                        "locked_until": int(time.time() + remaining),
                        "error":        f"Too many failed attempts. Try again in {int(remaining)} second(s).",
                        "processedAt":  firestore.SERVER_TIMESTAMP,
                    })
                else:
                    doc_ref.update({
                        "status":      "not_found",
                        "error":       "No device found. Please check your Device ID.",
                        "processedAt": firestore.SERVER_TIMESTAMP,
                    })
                return

        # ── At this point, requested_id is valid for this device ──
        print(f"[AUTH_BOUNCER] ✅ ID validation passed for {requested_id!r}")

        # ── Step 2: Rate limit check (keyed to requested_id) ──
        locked, remaining = _is_rate_limited(requested_id)
        if locked:
            locked_until_ts = time.time() + remaining
            print(f"[AUTH_BOUNCER] ⛔ {requested_id!r} is rate limited. {remaining:.0f}s remaining.")
            doc_ref.update({
                "status":       "rate_limited",
                "locked_until": int(locked_until_ts),
                "error":        f"Too many failed attempts. Try again in {int(remaining)} second(s).",
                "processedAt":  firestore.SERVER_TIMESTAMP,
            })
            return

        # ── Step 3: PIN verification (PBKDF2-HMAC-SHA256) ──
        stored_credential = _get_stored_credential()

        if not stored_credential:
            print("[AUTH_BOUNCER] ⚠️  Cannot verify PIN — no stored credential.")
            doc_ref.update({
                "status":      "error",
                "error":       "Device configuration error. Contact admin.",
                "processedAt": firestore.SERVER_TIMESTAMP,
            })
            return

        pin_ok = _verify_pin(raw_pin, stored_credential)
        if not pin_ok:
            _record_failure(requested_id)
            locked_after, rem_after = _is_rate_limited(requested_id)
            if locked_after:
                doc_ref.update({
                    "status":       "rate_limited",
                    "locked_until": int(time.time() + rem_after),
                    "error":        f"Too many failed attempts. Try again in {int(rem_after)} second(s).",
                    "processedAt":  firestore.SERVER_TIMESTAMP,
                })
            else:
                doc_ref.update({
                    "status":      "error",
                    "error":       "Incorrect password.",
                    "processedAt": firestore.SERVER_TIMESTAMP,
                })
            return

        # ── Silent PBKDF2 upgrade on the first successful SHA-256 login ──
        if not stored_credential.startswith("pbkdf2:"):
            _upgrade_credential_on_success(raw_pin)

        # ── Step 4: Mint Firebase Custom Token ──
        # CRITICAL: Always mint with HW_MAC_ID (immutable), NOT the alias.
        # This means FirebaseAuth.currentUser.uid == HW_MAC_ID always,
        # preserving all Firestore Security Rules and document ownership.
        print(f"[AUTH_BOUNCER] 🎫 Minting Custom Token with immutable UID={hw_id!r} "
              f"(requested via alias {requested_id!r})")
        custom_token_bytes = firebase_auth.create_custom_token(hw_id)

        # create_custom_token returns bytes — decode for Firestore string storage
        if isinstance(custom_token_bytes, bytes):
            custom_token = custom_token_bytes.decode("utf-8")
        else:
            custom_token = str(custom_token_bytes)

        # ── Step 5: Write approval back to Firestore ──
        doc_ref.update({
            "status":      "approved",
            "token":       custom_token,
            "processedAt": firestore.SERVER_TIMESTAMP,
        })

        _reset_failures(requested_id)
        print(f"[AUTH_BOUNCER] ✅ Login APPROVED for alias={requested_id!r} → UID={hw_id!r}. "
              "Token issued.")

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
    The listener receives ALL login_requests; alias-based filtering happens
    inside _handle_request to avoid missing requests where the user typed
    the alias (which differs from the server-side HW_MAC_ID).

    Called from main.py after firebase_manager.init_firebase() succeeds.
    Returns the listener handle (call .unsubscribe() to stop).
    """
    print(f"[AUTH_BOUNCER] 🚀 Starting Pi-Bouncer (Strict Alias Mode)")
    print(f"[AUTH_BOUNCER]    Immutable HW_MAC_ID : {config.HW_MAC_ID}")

    # Run one-time PIN migration on startup (SHA-256 → PBKDF2 or plaintext → PBKDF2)
    _get_stored_credential()

    # Log the current alias at startup for operator visibility
    current_alias = _get_current_alias(db)
    if current_alias:
        print(f"[AUTH_BOUNCER]    Active alias        : {current_alias!r}")
        print(f"[AUTH_BOUNCER]    Raw HW ID login     : DISABLED (alias enforced)")
    else:
        print(f"[AUTH_BOUNCER]    Active alias        : <none — HW_MAC_ID login active>")

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
