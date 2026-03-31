"""
Smart Sprout — Firebase Cloud Integration
──────────────────────────────────────────────────────────
Handles synchronization between the Raspberry Pi and 
Firebase Cloud Firestore (telemetry pushing & command listening).
"""
import firebase_admin
from firebase_admin import credentials, firestore
from google.cloud.firestore_v1.base_query import FieldFilter
import time
import threading
import sys
import datetime
from datetime import timedelta
import config

_db = None
_command_listener = None
_last_cleanup_time = 0

def init_firebase():
    global _db
    try:
        cred = credentials.Certificate(config.FIREBASE_CREDENTIALS_PATH)
        firebase_admin.initialize_app(cred)
        _db = firestore.client()
        print(f"[FIREBASE] Initialized with device ID: {config.DEVICE_ID}")
        return True
    except FileNotFoundError:
        print(f"[FIREBASE_ERROR] Service account key not found at {config.FIREBASE_CREDENTIALS_PATH}")
        print("Please download it from Firebase Console -> Project Settings -> Service Accounts")
        return False
    except Exception as e:
        print(f"[FIREBASE_ERROR] Failed to initialize Firebase: {e}")
        return False

def send_heartbeat():
    """Writes a last_heartbeat timestamp to the device document."""
    if not _db:
        return
    try:
        doc_ref = _db.collection('devices').document(config.DEVICE_ID)
        doc_ref.set({
            'last_heartbeat': firestore.SERVER_TIMESTAMP,
            'status': 'online',
        }, merge=True)
    except Exception as e:
        print(f"[HEARTBEAT] Error sending heartbeat: {e}")

def push_telemetry(telemetry_data):
    """Pushes the latest telemetry array as historical entries and updates current status."""
    if not _db:
        return
        
    try:
        doc_ref = _db.collection('devices').document(config.DEVICE_ID)
        
        # 1. Update the main device document with current status
        doc_ref.set({
            'status': 'online',
            'system_status': telemetry_data.get('system_status', 'unknown'),
            'lastSync': firestore.SERVER_TIMESTAMP,
            'tank_level': telemetry_data.get('tank_level', 0),
            'pump_locked': telemetry_data.get('pump_locked', False),
            'soil_moisture': telemetry_data.get('soil_moisture', [0.0, 0.0, 0.0]),
            'temperature': telemetry_data.get('temperature', 0.0),
            'humidity': telemetry_data.get('humidity', 0.0),
            'flow_rate': telemetry_data.get('flow_rate', 0.0),
            'alerts': telemetry_data.get('alerts', []),
            'soil_offsets': telemetry_data.get('soil_offsets', [0.0, 0.0, 0.0]),
            'start_threshold': telemetry_data.get('start_threshold', {}),
            'target_moisture': telemetry_data.get('target_moisture', {}),
            'max_pump_runtime': telemetry_data.get('max_pump_runtime', {}),
        }, merge=True)
        
        # 2. Add historical reading to subcollection
        doc_ref.collection('telemetry').add(telemetry_data)
        
    except Exception as e:
        print(f"[FIREBASE_ERROR] Failed to push telemetry: {e}")

def push_alerts(alerts):
    """Pushes alerts to Firestore."""
    if not _db or not alerts:
        return
        
    try:
        doc_ref = _db.collection('devices').document(config.DEVICE_ID)
        for alert in alerts:
            # Add to an alerts subcollection for history
            doc_ref.collection('alerts').add({
                'type': alert,
                'timestamp': firestore.SERVER_TIMESTAMP,
                'resolved': False
            })
    except Exception as e:
        print(f"[FIREBASE_ERROR] Failed to push alerts: {e}")

def listen_for_commands(callback):
    """Listens for remote commands added to the commands subcollection."""
    global _command_listener
    if not _db:
        return

    try:
        doc_ref = _db.collection('devices').document(config.DEVICE_ID)
        commands_ref = doc_ref.collection('commands').where(
            filter=FieldFilter('processed', '==', False)
        )
        
        def on_snapshot(col_snapshot, changes, read_time):
            for change in changes:
                if change.type.name == 'ADDED':
                    cmd_data = change.document.to_dict()
                    cmd_id = change.document.id
                    
                    print(f"[FIREBASE_CMD] Received: {cmd_data}")
                    
                    # Execute the callback (e.g., in main.py)
                    try:
                        callback(cmd_data)
                        
                        # Mark as processed
                        change.document.reference.update({
                            'processed': True,
                            'processedAt': firestore.SERVER_TIMESTAMP
                        })
                    except Exception as e:
                        print(f"[FIREBASE_ERROR] Error executing command {cmd_id}: {e}")
                        
        _command_listener = commands_ref.on_snapshot(on_snapshot)
        print("[FIREBASE] Listening for remote commands.")
    except Exception as e:
        print(f"[FIREBASE_ERROR] Failed to setup command listener: {e}")

def perform_storage_cleanup(force=False):
    """Deletes telemetry and processed commands older than the retention period."""
    global _last_cleanup_time
    if not _db:
        return
        
    current_time = time.time()
    # Only run once every CLEANUP_INTERVAL_HOURS unless forced
    if not force and (current_time - _last_cleanup_time) < (config.CLEANUP_INTERVAL_HOURS * 3600):
        return

    try:
        retention_days = config.STORAGE_RETENTION_DAYS
        # Calculate cutoff timestamp (Unix integer)
        cutoff_timestamp = int(current_time - (retention_days * 86400))
        # Calculate cutoff for Firestore Timestamps
        cutoff_date = datetime.datetime.now(datetime.timezone.utc) - timedelta(days=retention_days)
        
        print(f"[FIREBASE] Starting storage cleanup (Retention: {retention_days} days)...")
        
        doc_ref = _db.collection('devices').document(config.DEVICE_ID)
        
        # 1. Cleanup Telemetry (using the integer timestamp)
        telemetry_ref = doc_ref.collection('telemetry').where(
            filter=FieldFilter('timestamp', '<', cutoff_timestamp)
        )
        docs = telemetry_ref.limit(500).stream()
        deleted_count = 0
        for doc in docs:
            doc.reference.delete()
            deleted_count += 1
            
        # 2. Cleanup Processed Commands (using Firestore timestamp)
        commands_ref = doc_ref.collection('commands').where(
            filter=FieldFilter('processed', '==', True)
        ).where(
            filter=FieldFilter('processedAt', '<', cutoff_date)
        )
        docs = commands_ref.limit(500).stream()
        cmd_deleted_count = 0
        for doc in docs:
            doc.reference.delete()
            cmd_deleted_count += 1
            
        if deleted_count > 0 or cmd_deleted_count > 0:
            print(f"[FIREBASE] Cleanup finished: Deleted {deleted_count} telemetry and {cmd_deleted_count} commands.")
        
        _last_cleanup_time = current_time
            
    except Exception as e:
        print(f"[FIREBASE_ERROR] Storage cleanup failed: {e}")

# ═══════════════════════════════════════════════════════
# Zone Targets — Precision Saturation Settings
# ═══════════════════════════════════════════════════════
_cached_zone_targets = None
_zone_targets_last_fetch = 0

def get_zone_targets() -> dict:
    """
    Reads target_moisture and max_pump_runtime from the device document.
    Returns: { 1: {"target": 65.0, "timeout": 30}, 2: {...}, 3: {...} }
    Cached for 5 minutes to reduce Firestore reads.
    """
    global _cached_zone_targets, _zone_targets_last_fetch
    import time as _t

    now = _t.time()
    if _cached_zone_targets and (now - _zone_targets_last_fetch) < 300:
        return _cached_zone_targets

    defaults = {
        1: {"target": config.DEFAULT_TARGET_MOISTURE, "timeout": config.DEFAULT_MAX_PUMP_RUNTIME},
        2: {"target": config.DEFAULT_TARGET_MOISTURE, "timeout": config.DEFAULT_MAX_PUMP_RUNTIME},
        3: {"target": config.DEFAULT_TARGET_MOISTURE, "timeout": config.DEFAULT_MAX_PUMP_RUNTIME},
    }

    if not _db:
        _cached_zone_targets = defaults
        return defaults

    try:
        doc_ref = _db.collection('devices').document(config.DEVICE_ID)
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict()
            target_map = data.get('target_moisture', {})
            timeout_map = data.get('max_pump_runtime', {})
            for z in [1, 2, 3]:
                bed_key = f"bed{z}"
                defaults[z]["target"] = float(target_map.get(bed_key, config.DEFAULT_TARGET_MOISTURE))
                defaults[z]["timeout"] = int(timeout_map.get(bed_key, config.DEFAULT_MAX_PUMP_RUNTIME))
        _cached_zone_targets = defaults
        _zone_targets_last_fetch = now
        print(f"[FIREBASE] Zone targets refreshed: {defaults}")
    except Exception as e:
        print(f"[FIREBASE_ERROR] Failed to fetch zone targets: {e}")
        _cached_zone_targets = defaults

    return defaults


def get_manual_heartbeat() -> float:
    """
    Reads the manual_heartbeat timestamp from the device document.
    Returns seconds since last heartbeat, or 999 if unavailable.
    """
    if not _db:
        return 999.0
    try:
        doc = _db.collection('devices').document(config.DEVICE_ID).get()
        if doc.exists:
            data = doc.to_dict()
            hb = data.get('manual_heartbeat')
            if hb and hasattr(hb, 'timestamp'):
                # Firestore Timestamp → epoch seconds
                age = time.time() - hb.timestamp()
                return max(0, age)
            elif isinstance(hb, (int, float)):
                return max(0, time.time() - hb)
        return 999.0
    except Exception as e:
        print(f"[FIREBASE_ERROR] get_manual_heartbeat: {e}")
        return 999.0


def update_pump_status(zone: int, is_active: bool):
    """
    Immediately patches pump_status_zoneN on the device document.
    This is a fast, dedicated write so the Flutter UI can confirm
    activation in ~1-2 seconds without waiting for a full telemetry push.
    """
    if not _db:
        return
    field_key = f"pump_status_zone{zone}"
    try:
        doc_ref = _db.collection('devices').document(config.DEVICE_ID)
        doc_ref.set({field_key: is_active}, merge=True)
        state = "ON" if is_active else "OFF"
        print(f"[PUMP_STATUS] Zone {zone} -> {state} ({field_key}={is_active})")
    except Exception as e:
        print(f"[FIREBASE_ERROR] update_pump_status zone {zone}: {e}")


def cleanup():
    """Clean up Firebase listeners."""
    global _command_listener
    if _command_listener:
        _command_listener.unsubscribe()
        _command_listener = None
