"""
Smart Sprout — Main Event Loop
──────────────────────────────────────────────────────────
Reads all hardware sensors on a configurable interval,
publishes telemetry via local MQTT, and listens for
incoming "Force Water" manual override commands.
──────────────────────────────────────────────────────────
"""
import time
import signal
import threading
import config
from network import firebase_manager
from network import auth_bouncer
from storage import local_db
from drivers.sensors import SensorManager

# ═══════════════════════════════════════════════════════
# Global State
_auth_bouncer_listener = None
# ═══════════════════════════════════════════════════════
_running = True
_pump_locked = False  # True when XKC tank sensor reads LOW or FAULT (binary sensor, no percentage)
_system_locked = False  # Cloud-synced Emergency Stop flag (system_lock in Firestore)
sensor_manager = None
_current_mode = "manual"
_auto_strategy = "sensor"
_auto_timer_hour = 8
_auto_timer_minute = 0
_last_auto_water = {1: 0, 2: 0, 3: 0} # Cooldown tracking per zone
_last_daily_water_date = ""
# Per-zone enabled flags — mirrors zone chips in Flutter auto-mode UI.
# Keys are 1-indexed zone numbers. Default: all zones active.
_enabled_zones: set = {1, 2, 3}
_last_sent_telemetry = {}  # Tracks last cloud-pushed values for differential sync
_force_sync = False
_last_push_time = 0.0        # Minimum push cooldown guard — prevents rapid-fire writes

# Dead-Man's Switch state
_manual_pump_active = False
_manual_pump_zone = 0

# External Hydration Detection
_prev_moisture = {}  # {"bed1": 42.0, "bed2": 55.0, ...}
_pump_running = False  # True when any pump/valve is active
_last_hydration_alert = {} # Track last alert time per zone


def _signal_handler(sig, frame):
    global _running
    print("\n[MAIN] Graceful shutdown requested...")
    _running = False


signal.signal(signal.SIGINT, _signal_handler)
signal.signal(signal.SIGTERM, _signal_handler)


# Local handling removed. All commands come through Firebase.


def _force_water_task(zone: int, duration: int, target_moisture: float = 0.0):
    """
    Run a watering cycle in its own thread.
    
    AUTO-MODE (target_moisture > 0):  Pulse & Soak cycle
      - Burst: pump ON for PULSE_BURST_SECONDS (5s)
      - Soak:  pump OFF for PULSE_SOAK_SECONDS (20s)
      - Check: re-read moisture. If >= target → done.
      - Repeat until target reached OR elapsed >= duration (safety timeout)
    
    MANUAL MODE (target_moisture == 0):  Continuous run
      - Protected by Dead-Man's Switch heartbeat monitor.
    """
    global _pump_running
    try:
        _pump_running = True
        firebase_manager.update_pump_status(zone, True)   # ← Optimistic UI ACK
        sensor_manager.activate_zone(zone)
        start_time = time.time()

        if target_moisture > 0:
            # ── Pulse & Soak (Indoor Auto-Watering) ──
            burst = config.PULSE_BURST_SECONDS
            soak = config.PULSE_SOAK_SECONDS
            cycle = 0

            while True:
                elapsed = time.time() - start_time
                if elapsed >= duration:
                    print(f"[AUTO] Zone {zone}: Safety timeout ({duration}s) reached. Stopping.")
                    break

                cycle += 1
                print(f"[AUTO] Zone {zone}: Pulse #{cycle} — burst {burst}s")
                sensor_manager.activate_zone(zone)
                time.sleep(burst)

                # Deactivate for soak period
                sensor_manager.deactivate_all()
                print(f"[AUTO] Zone {zone}: Soaking {soak}s...")
                time.sleep(soak)

                # Re-read moisture after soak
                soil, _, _ = sensor_manager.read_soil_moisture()
                current = soil.get(f"bed{zone}", 0.0)
                elapsed = time.time() - start_time
                print(f"[AUTO] Zone {zone}: {current:.1f}% / target {target_moisture:.1f}% (elapsed {elapsed:.0f}s/{duration}s)")

                if current >= target_moisture:
                    print(f"[AUTO] Zone {zone}: ✅ Target saturation reached ({current:.1f}% >= {target_moisture:.1f}%)")
                    break
        else:
            # ── Legacy continuous run (manual force water) ──
            time.sleep(duration)

        sensor_manager.deactivate_all()
        firebase_manager.update_pump_status(zone, False)  # ← Pump done
        _pump_running = False
        print(f"[CMD] Force water zone {zone} completed ({time.time() - start_time:.0f}s)")
    except Exception as e:
        print(f"[ERROR] Force water task failed: {e}")
        sensor_manager.deactivate_all()
        firebase_manager.update_pump_status(zone, False)  # ← Pump error
        _pump_running = False


def _manual_heartbeat_monitor(zone: int):
    """
    Dead-Man's Switch: monitors the manual_heartbeat timestamp in Firestore.
    If heartbeat becomes stale (>5 seconds), force pump OFF immediately.
    Runs in its own thread while manual water is active.
    """
    global _manual_pump_active, _pump_running
    print(f"[DEADMAN] Heartbeat monitor started for Zone {zone}")

    while _manual_pump_active and _running:
        try:
            age = firebase_manager.get_manual_heartbeat()
            if age > 5.0:
                print("=" * 60)
                print(f"[DEADMAN] ⚠️  HEARTBEAT STALE ({age:.1f}s) — KILLING PUMP!")
                print(f"[DEADMAN] Zone {zone}: CONNECTION_LOST_SHUTDOWN")
                print("=" * 60)
                sensor_manager.deactivate_all()
                _manual_pump_active = False
                _pump_running = False
                # Notify UI that pump went off via Firestore
                firebase_manager.update_pump_status(zone, False)
                # Push alert to Firestore
                try:
                    firebase_manager.push_telemetry({
                        'system_status': 'CONNECTION_LOST_SHUTDOWN',
                        'pump_status': {'pump': 'OFF', 'zone': 0},
                        'alerts': [f'Manual heartbeat lost — Zone {zone} pump killed for safety.'],
                    })
                except Exception:
                    pass
                return
        except Exception as e:
            print(f"[DEADMAN] Error checking heartbeat: {e}")
        time.sleep(3)  # Check every 3s — was 2s (saves 50% of heartbeat reads during manual water)

    print(f"[DEADMAN] Heartbeat monitor stopped for Zone {zone}")

def handle_firebase_command(payload: dict):
    """Handle incoming commands from Firebase Cloud Firestore."""
    global _pump_locked, _force_sync, _system_locked
    command = payload.get("command", "")
    print(f"[FIREBASE_CMD_PROCESS] {payload}")

    # ── System Lock Enforcement ──
    # If the system is locked (Emergency Stop active), block ALL watering commands.
    # The only allowed commands are stop_all (to ensure pumps are OFF) and
    # administrative commands (sync, reboot, etc.).
    watering_commands = {"force_water", "set_mode"}
    if _system_locked and command in watering_commands:
        print(f"[SAFETY] Command '{command}' BLOCKED — System Lock (Emergency Stop) is active.")
        # Safety guard: make absolutely sure pumps are off
        if sensor_manager:
            sensor_manager.deactivate_all()
        return

    if command == "force_water":
        zone = payload.get("zone", 0)
        if _pump_locked:
            print(f"[SAFETY] Force water BLOCKED for zone {zone} — tank too low")
            return
            
        if zone in (1, 2, 3):
            duration = payload.get("duration_seconds", 10)
            threading.Thread(
                target=_force_water_task,
                args=(zone, duration),
                daemon=True,
            ).start()
            # Start Dead-Man's Switch monitor for manual water only
            if duration >= 60:  # Manual water uses 600s, auto uses shorter
                _manual_pump_active = True
                _manual_pump_zone = zone
                threading.Thread(
                    target=_manual_heartbeat_monitor,
                    args=(zone,),
                    daemon=True,
                ).start()
    elif command == "stop_all":
        _manual_pump_active = False  # Stop heartbeat monitor
        sensor_manager.deactivate_all()
        _pump_running = False
        # Clear all per-zone pump status flags so UI reverts cleanly
        for z in [1, 2, 3]:
            firebase_manager.update_pump_status(z, False)
        print("[CMD] Emergency stop — all zones deactivated")
    elif command == "calibrate":
        print("[SETTINGS] Starting calibration routine from Firebase...")
        result = sensor_manager.run_calibration()
        print(f"[SETTINGS] Calibration complete: {result}")
    elif command == "dry_calibrate":
        print("[SETTINGS] Starting dry calibration from Firebase...")
        zone = payload.get("zone", None)
        result = sensor_manager.run_dry_calibration(target_zone=zone)
        print(f"[SETTINGS] Dry calibration complete: {result}")
        _force_sync = True
    elif command == "run_wet_calibration":
        # Expected payload: {'command': 'run_wet_calibration', 'zone': 1}
        # 'zone' is optional — omit or set to None to calibrate all zones.
        zone = payload.get("zone", None)
        print(f"[SETTINGS] Starting wet calibration from Firebase (zone={zone})...")
        result = sensor_manager.run_wet_calibration(target_zone=zone)
        print(f"[SETTINGS] Wet calibration complete: {result}")
        _force_sync = True
    elif command == "set_offset":
        zone = payload.get("zone", 1)
        value = payload.get("value", 0)
        print(f"[SETTINGS] Setting absolute offset for zone {zone} to {value}%")
        cal_data = sensor_manager.load_calibration()
        zone_key = f"zone_{zone}"
        if zone_key in cal_data:
            cal_data[zone_key]["manual_offset_pct"] = max(0, min(100, value))
            sensor_manager.save_calibration()
            _force_sync = True
    elif command == "adjust_offset":
        zone = payload.get("zone", 1)
        adjustment = payload.get("adjustment", 0)
        print(f"[SETTINGS] Adjusting manual offset for zone {zone} by {adjustment}%")
        cal_data = sensor_manager.load_calibration()
        zone_key = f"zone_{zone}"
        if zone_key in cal_data:
            new_offset = cal_data[zone_key].get("manual_offset_pct", 0) + adjustment
            new_offset = max(-50, min(50, new_offset))
            cal_data[zone_key]["manual_offset_pct"] = new_offset
            sensor_manager.save_calibration()
            _force_sync = True
    elif command == "FORCE_SYNC":
        requested_at = payload.get("requested_at", "")
        print(f"[FIREBASE] Force sync requested from mobile app (requested_at={requested_at})")
        _force_sync = True
    elif command == "set_mode":
        global _current_mode, _auto_strategy, _auto_timer_hour, _auto_timer_minute, _enabled_zones
        _current_mode = payload.get("mode", "manual")
        # Only override strategy/timer if explicitly provided — prevents
        # a mode toggle OFF (which omits 'strategy') from silently
        # resetting the active strategy to the default 'sensor'.
        if "strategy" in payload:
            _auto_strategy = payload["strategy"]
        if "timer_hour" in payload:
            _auto_timer_hour = payload["timer_hour"]
        if "timer_minute" in payload:
            _auto_timer_minute = payload["timer_minute"]
        # enabled_zones: list of 1-indexed zone numbers the user has toggled ON.
        # If the key is absent (e.g. manual mode toggle), keep the previous set unchanged.
        if "enabled_zones" in payload:
            raw_zones = payload["enabled_zones"]
            _enabled_zones = set(int(z) for z in raw_zones) if raw_zones else set()
            print(f"[SETTINGS] Zone filter updated → active zones: {sorted(_enabled_zones)}")
        print(f"[SETTINGS] Switched to {_current_mode.upper()} mode, Strategy: {_auto_strategy}, Time: {_auto_timer_hour:02d}:{_auto_timer_minute:02d}")
    elif command == "set_triggers":
        zone = payload.get("zone", 1)
        start = float(payload.get("start_threshold", 50))
        target = float(payload.get("target_saturation", 65))
        timeout = int(payload.get("safety_timeout", 30))
        print(f"[SETTINGS] Setting triggers for zone {zone}: start={start}%, target={target}%, timeout={timeout}s")
        
        cal_data = sensor_manager.load_calibration()
        zone_key = f"zone_{zone}"
        if zone_key not in cal_data:
            cal_data[zone_key] = {}
        cal_data[zone_key]["start_threshold"] = start
        cal_data[zone_key]["target_moisture"] = target
        cal_data[zone_key]["max_pump_runtime"] = timeout
        sensor_manager.save_calibration()
        _force_sync = True
    elif command == "RESTART_APP":
        print("[MAINTENANCE] Kiosk UI refresh requested. (Handled locally by Flutter)")
    elif command == "REBOOT_PI":
        import os
        print("[MAINTENANCE] Hardware reboot requested. Rebooting now...")
        os.system("sudo reboot")
    elif command == "SYNC_CONFIG":
        new_id = payload.get("new_device_id", "")
        if new_id:
            print(f"[CONFIG] SYNC_CONFIG received. Changing device ID to: {new_id}")
            config.update_device_id(new_id)
            # Reload the module-level DEVICE_ID so firebase_manager uses the new path
            config.DEVICE_ID = new_id
            # Re-initialize Firebase listeners on the new document path
            firebase_manager.cleanup()
            firebase_manager.listen_for_commands(handle_firebase_command)
            _force_sync = True
            print(f"[CONFIG] Device ID changed successfully. Now listening as: {new_id}")
        else:
            print("[CONFIG] SYNC_CONFIG received but no new_device_id provided.")

# ═══════════════════════════════════════════════════════
# Telemetry Collection
# ═══════════════════════════════════════════════════════
def collect_telemetry() -> dict:
    """
    Reads ALL sensors and returns a unified telemetry dict.
    The 'status' field indicates health: 'ok', 'sensor_fault', 'tank_low'.
    NOTE: This function only reads hardware. It never writes to Firebase.
    Cloud pushes are gated entirely by the main loop's Eco-Mode / Differential
    Sync / FORCE_SYNC logic.
    """
    global _pump_locked

    soil, soil_raw, soil_fault = sensor_manager.read_soil_moisture()
    env = sensor_manager.read_environment()
    tank = sensor_manager.read_tank_level()

    # ── Safety Logic ──
    alerts = []
    system_status = "ok"

    # Tank safety lock
    # "FULL" = water detected (Active-Low: GPIO LOW), pump allowed.
    # "LOW"  = no water detected, pump locked.
    # "FAULT"= sensor disconnected or signal unstable, pump locked for safety.
    if tank == "LOW" or tank == "FAULT":
        _pump_locked = True
        alerts.append("tank_empty" if tank == "LOW" else "tank_sensor_fault")
        system_status = "tank_low" if tank == "LOW" else "sensor_fault"
    elif tank == "FULL":
        _pump_locked = False

    # Hardware status tracking
    hardware_status = {
        "bed1": "fault" if soil.get("bed1", 0) < 0 else "ok",
        "bed2": "fault" if soil.get("bed2", 0) < 0 else "ok",
        "bed3": "fault" if soil.get("bed3", 0) < 0 else "ok",
        "environment": "fault" if env["temperature"] == -1.0 and env["humidity"] == -1.0 else "ok",
        "tank": "fault" if tank == "FAULT" else "ok",
    }

    # Sensor fault detection
    if soil_fault or any(s < 0 for s in soil.values()):
        alerts.append("soil_sensor_fault")
        system_status = "sensor_fault"
    if hardware_status["environment"] == "fault":
        alerts.append("environment_sensor_fault")
        if system_status == "ok":
            system_status = "sensor_fault"
    if tank == "FAULT":
        # Note: If tank == "FAULT", alerts/system_status is now handled by the safety logic above.
        pass

    # Read current offsets and triggers from calibration data
    cal_data = sensor_manager.load_calibration()
    soil_offsets = {}
    start_threshold = {}
    target_moisture = {}
    max_pump_runtime = {}
    for i in range(1, 4):
        zone_data = cal_data.get(f"zone_{i}", {})
        soil_offsets[f"bed{i}"] = zone_data.get("manual_offset_pct", 0)
        start_threshold[f"bed{i}"] = zone_data.get("start_threshold", config.DEFAULT_TARGET_MOISTURE - 15)
        target_moisture[f"bed{i}"] = zone_data.get("target_moisture", config.DEFAULT_TARGET_MOISTURE)
        max_pump_runtime[f"bed{i}"] = zone_data.get("max_pump_runtime", config.DEFAULT_MAX_PUMP_RUNTIME)

    telemetry = {
        "timestamp": int(time.time()),
        "soil_moisture": soil,
        "soil_moisture_raw": soil_raw,
        "soil_offsets": soil_offsets,
        "start_threshold": start_threshold,
        "target_moisture": target_moisture,
        "max_pump_runtime": max_pump_runtime,
        "temperature": env["temperature"],
        "humidity": env["humidity"],
        "pressure": env["pressure"],
        "tank_level": tank,
        "pump_locked": _pump_locked,
        "system_lock": _system_locked,  # Cloud-synced Emergency Stop flag
        "system_status": system_status,
        "hardware_status": hardware_status,
        "alerts": alerts,
    }

    return telemetry


# ═══════════════════════════════════════════════════════
# Differential Sync — Threshold-based immediate push
# ═══════════════════════════════════════════════════════
# ── Differential Sync Thresholds ──
# These are intentionally conservative to suppress sensor jitter/noise.
# A 3% moisture threshold caused 28,800+ writes/day due to ADC noise.
# New thresholds: moisture=8%, temperature=3°C — only genuine changes push.
_DIFF_MOISTURE_THRESHOLD       = 8.0   # % points — filters ADC jitter
_DIFF_MOISTURE_URGENT_THRESHOLD = 25.0  # % points — bypasses 60s cooldown entirely
_DIFF_TEMP_THRESHOLD           = 3.0   # °C — filters ambient fluctuation
_MIN_PUSH_INTERVAL             = 60    # seconds — minimum between small/gradual changes


def _should_differential_push(current: dict) -> bool:
    """
    Returns True if critical sensor values have changed beyond thresholds
    compared to the last cloud-pushed telemetry. This triggers an immediate
    sync even if the Eco-Mode timer hasn't expired.

    Two-tier moisture threshold:
      - URGENT (>25%): Bypasses the 60s cooldown entirely. A drop from 100→8%
        is always pushed immediately regardless of when the last push was.
      - NORMAL (>8%): Respects the 60s cooldown. Catches gradual real changes
        but blocks the ADC jitter noise (~1-3%).
    """
    global _last_sent_telemetry, _last_push_time, _pump_running

    # ── Live Watering Bypass ──
    # If the pump is active, bypass the 60s cooldown and 8% threshold.
    # Streams live updates every 3s to the UI for a premium experience.
    if _pump_running:
        return True

    if not _last_sent_telemetry:
        return False  # First reading — let the normal sync handle it

    # ── Tank Level Change (immediate — highest priority, never rate-limited) ──
    last_tank = _last_sent_telemetry.get("tank_level", "FAULT")
    curr_tank = current.get("tank_level", "FAULT")
    if curr_tank != last_tank:
        print(f"[DIFF_SYNC] Tank level change detected: {last_tank}→{curr_tank}")
        return True

    # ── System Status Change (e.g. sensor_fault → ok) — never rate-limited ──
    last_status = _last_sent_telemetry.get("system_status", "ok")
    curr_status = current.get("system_status", "ok")
    if curr_status != last_status:
        print(f"[DIFF_SYNC] System status change detected: {last_status}→{curr_status}")
        return True

    # ── URGENT Soil Moisture Delta > 25% — bypasses 60s cooldown ──
    # A genuine event like pulling a probe from water (100%→8%) is a 92% swing.
    # This must NEVER be blocked by the cooldown timer.
    last_soil = _last_sent_telemetry.get("soil_moisture", {})
    curr_soil = current.get("soil_moisture", {})
    for bed in curr_soil:
        last_val = last_soil.get(bed, 0)
        curr_val = curr_soil.get(bed, 0)
        if isinstance(curr_val, (int, float)) and isinstance(last_val, (int, float)):
            delta = abs(curr_val - last_val)
            if delta > _DIFF_MOISTURE_URGENT_THRESHOLD:
                print(f"[DIFF_SYNC] URGENT soil change on {bed}: {last_val}→{curr_val}% (Δ{delta:.1f}%) — cooldown bypassed")
                return True

    # ── Minimum Push Cooldown ──
    # For gradual/small changes only. Prevents jitter from burning quota.
    if (time.time() - _last_push_time) < _MIN_PUSH_INTERVAL:
        return False

    # ── Temperature Delta > 3°C ──
    last_temp = _last_sent_telemetry.get("temperature", 0)
    curr_temp = current.get("temperature", 0)
    if abs(curr_temp - last_temp) > _DIFF_TEMP_THRESHOLD:
        print(f"[DIFF_SYNC] Temperature change detected: {last_temp}→{curr_temp}°C")
        return True

    # ── Normal Soil Moisture Delta > 8% (gradual changes, rate-limited) ──
    # Catches real watering/drying cycles while blocking ADC noise (~1-3%).
    for bed in curr_soil:
        last_val = last_soil.get(bed, 0)
        curr_val = curr_soil.get(bed, 0)
        if isinstance(curr_val, (int, float)) and isinstance(last_val, (int, float)):
            if abs(curr_val - last_val) > _DIFF_MOISTURE_THRESHOLD:
                print(f"[DIFF_SYNC] Soil {bed} change detected: {last_val}→{curr_val}%")
                return True

    return False


# ═══════════════════════════════════════════════════════
# Main Loop
# ═══════════════════════════════════════════════════════
def main():
    global sensor_manager, _last_sent_telemetry, _last_push_time, _force_sync
    print("═" * 55)
    print("  🌱 Smart Sprout — Raspberry Pi Controller v1.0")
    print("═" * 55)

    # ── Initialize Hardware ──
    print("[INIT] Instantiating SensorManager...")
    sensor_manager = SensorManager()
    sensor_manager.setup_relays()
    print("[INIT] Hardware initialized.")

    # ── Initialize Local SQLite Database ──
    # Must run before the main loop so the persistence layer is ready
    # to accept readings even if Firebase is unavailable at boot.
    local_db.init_db()
    local_db.purge_old_records()  # Trim rows older than 7 days
    stats = local_db.get_stats()
    print(f"[LOCAL_DB] Startup stats — "
          f"Total: {stats.get('total_records', 0)} rows, "
          f"Unsynced: {stats.get('unsynced_records', 0)} rows, "
          f"Size: {stats.get('db_size_kb', 0)} KB")

    # ── Start Hardware Reset Button Monitor ──
    from tools import reset_button
    reset_button.start_reset_button_monitor()

    # ── Start Pump Safety Watchdog ──
    from drivers import pump_watchdog
    pump_watchdog.start_pump_watchdog()

    # ── Start Heartbeat Thread ──
    # REVERTED TO 10S: This is the fastest "Real-time" setting for the defense.
    # The Flutter app "Offline" timeout was updated to 45s (from original 90s)
    # to provide a much snappier response if the device is unplugged.
    HEARTBEAT_INTERVAL = 10  # 10 seconds
    def _heartbeat_loop():
        while _running:
            firebase_manager.send_heartbeat()
            time.sleep(HEARTBEAT_INTERVAL)
    threading.Thread(target=_heartbeat_loop, daemon=True).start()
    print(f"[INIT] Heartbeat thread started ({HEARTBEAT_INTERVAL}s interval)")

    # ── Start Wi-Fi Bridge (Linux Kiosk only) ──
    # Runs a lightweight HTTP server on port 7788 so the Flutter UI can
    # scan/connect/forget Wi-Fi networks via nmcli without needing a plugin.
    from network import wifi_bridge
    threading.Thread(target=wifi_bridge.start_bridge, daemon=True).start()
    print("[INIT] Wi-Fi bridge started on http://127.0.0.1:7788")

    # MQTT logic removed for Zero-Trust Architecture

    # ── Connect Firebase ──
    if firebase_manager.init_firebase():
        firebase_manager.listen_for_commands(handle_firebase_command)

        # ── System Lock Listener ──
        # Watches the system_lock field on the device document in real time.
        # When the flag changes (from mobile OR kiosk), the Pi reacts immediately:
        #   locked=True  → deactivate all pumps + block watering commands
        #   locked=False → release lock, normal operations resume
        def _on_system_lock_change(doc_snapshot, changes, read_time):
            global _system_locked, _pump_running, _manual_pump_active
            for doc in doc_snapshot:
                new_lock = doc.to_dict().get("system_lock", False)
                if new_lock != _system_locked:
                    _system_locked = new_lock
                    if _system_locked:
                        print("[SYSTEM_LOCK] 🔒 Emergency Stop received remotely — shutting down all pumps.")
                        _manual_pump_active = False
                        _pump_running = False
                        if sensor_manager:
                            sensor_manager.deactivate_all()
                        # Clear all per-zone pump status flags in Firestore
                        for z in [1, 2, 3]:
                            try:
                                firebase_manager.update_pump_status(z, False)
                            except Exception:
                                pass
                    else:
                        print("[SYSTEM_LOCK] 🔓 System Lock released — normal operations resumed.")

        try:
            from firebase_admin import firestore as _fstore
            _db = _fstore.client()
            _system_lock_watcher = _db.collection("devices").document(
                config.DEVICE_ID
            ).on_snapshot(_on_system_lock_change)
            print("[INIT] system_lock Firestore listener registered.")
        except Exception as _lock_ex:
            print(f"[WARN] Could not register system_lock listener: {_lock_ex}")

        # ── Start Pi-Bouncer Auth Daemon ──
        from firebase_admin import firestore as _fs
        global _auth_bouncer_listener
        _auth_bouncer_listener = auth_bouncer.start_auth_bouncer(_fs.client())


    interval = config.TELEMETRY_INTERVAL          # Local sensor read cadence (3 s)
    cloud_sync_interval = config.CLOUD_SYNC_INTERVAL  # Eco-Mode ceiling (1800 s = 30 min)

    # Safety bounds to prevent quota spam
    interval = max(interval, 3.0)
    cloud_sync_interval = max(cloud_sync_interval, 1800.0)

    # ── Boot Init ──
    # DO NOT pre-seed _last_sent_telemetry here. Leaving it empty ensures
    # _should_differential_push() skips differential checks on the first loop.
    # The first push is handled by eco_due (last_cloud_sync=0 triggers immediately).
    # _last_sent_telemetry is only set AFTER a confirmed successful push so the
    # baseline always reflects what the cloud actually has — not what the sensor read
    # at an arbitrary boot moment (which may differ from the cloud's last value).
    last_cloud_sync = 0
    _last_sent_telemetry = {}  # Empty — forces eco_due push on first loop

    # Give Firebase a moment to stabilize after init before the first push
    print("[MAIN] Waiting 5s for Firebase connection to stabilize...")
    time.sleep(5)

    print(f"[MAIN] Starting local polling loop (every {interval}s)...")
    print(f"[MAIN] Cloud sync interval set to {cloud_sync_interval}s ({cloud_sync_interval/60:.0f} min). "
          f"Differential threshold: 8% moisture, urgent bypass at 25%.\n")

    # ── Main Polling Loop ──
    try:
        while _running:
            try:
                current_time = time.time()
                telemetry = collect_telemetry()

                # ── Write Local Cache for Linux Kiosk ──
                # The kiosk UI reads this file every 3s to display live sensor data
                # without any Firebase quota usage (direct sensor → UI).
                try:
                    import json as _json_mod
                    import tempfile, os
                    _cache_path = '/tmp/smartsprout_telemetry.json'
                    _tmp_path = _cache_path + '.tmp'
                    with open(_tmp_path, 'w') as _f:
                        _json_mod.dump(telemetry, _f)
                    os.replace(_tmp_path, _cache_path)  # Atomic swap — prevents partial reads
                except Exception as _cache_err:
                    print(f"[WARN] Failed to write local telemetry cache: {_cache_err}")

                # ── Cloud Push Gate ── (Eco-Mode + Differential Sync + FORCE_SYNC)
                # Local sensor reads happen every 3 s (TELEMETRY_INTERVAL).
                # Firebase writes are rate-limited to avoid 429 Quota Exceeded errors.
                # A push is allowed ONLY when one of the three conditions below is met.
                eco_due     = (current_time - last_cloud_sync) >= cloud_sync_interval
                diff_push   = _should_differential_push(telemetry)
                push_reason = None

                if _force_sync:
                    push_reason = "FORCE_SYNC (mobile command)"
                elif diff_push:
                    push_reason = "DIFFERENTIAL_SYNC (sensor value threshold crossed)"
                elif eco_due:
                    push_reason = f"ECO_MODE (30-min interval elapsed)"

                if push_reason:
                    try:
                        print(f"[FIREBASE] Push triggered by: {push_reason}")

                        # ── History vs Status routing ──
                        # FORCE_SYNC and ECO_MODE write BOTH the current-status document
                        # AND the historical telemetry subcollection.
                        # DIFFERENTIAL_SYNC only updates the current-status document —
                        # it does NOT add a history record, cutting subcollection writes by ~90%.
                        write_history = (_force_sync or eco_due)

                        # ── STORE-FIRST (Offline Resilience) ──
                        # Save this reading to SQLite BEFORE attempting the cloud push.
                        # This guarantees the data is preserved even if Firebase is
                        # unreachable. The row starts as synced=0 (unsynced).
                        local_row_id = None
                        if write_history:
                            local_row_id = local_db.save_reading(telemetry)

                        push_ok = firebase_manager.push_telemetry(telemetry, write_history=write_history)

                        if not push_ok:
                            # Cloud write failed — do NOT update any local state.
                            # eco_due stays True (last_cloud_sync unchanged), so
                            # the next loop will automatically retry the push.
                            print(f"[FIREBASE] Push FAILED — baseline NOT updated. Will retry next cycle.")
                        else:
                            # ── Mark current reading as synced ──
                            if local_row_id is not None:
                                local_db.mark_synced([local_row_id])

                            # ── RECOVERY ENGINE ──
                            if write_history:
                                unsynced = local_db.get_unsynced_records(limit=50)
                                if unsynced:
                                    print(f"[RECOVERY] Found {len(unsynced)} offline reading(s) — "
                                          f"backfilling to Firebase...")
                                    recovered_ids = firebase_manager.push_history_batch(unsynced)
                                    if recovered_ids:
                                        local_db.mark_synced(recovered_ids)

                            # Publish alerts separately to Firebase
                            if telemetry["alerts"]:
                                firebase_manager.push_alerts(telemetry["alerts"])

                            # ── Storage Management ──
                            firebase_manager.perform_storage_cleanup()

                            # ── Update guards ONLY after confirmed success ──
                            last_cloud_sync = current_time
                            _last_push_time = current_time
                            _force_sync = False
                            _last_sent_telemetry = telemetry.copy()  # Baseline = what cloud now has
                            print(f"[DIFF_SYNC] Baseline updated: soil={telemetry.get('soil_moisture')}, temp={telemetry.get('temperature')}")
                            mins_until_next = cloud_sync_interval / 60
                            print(f"[FIREBASE] Telemetry synced ✓ (history={'YES' if write_history else 'STATUS-ONLY'}) "
                                  f"(next Eco-Mode push in {mins_until_next:.0f} min unless diff/force fires first).")
                    except Exception as e:
                        print(f"[FIREBASE] Unexpected push error: {e}")

                print(
                    f"[TEL] Soil={telemetry['soil_moisture']} | "
                    f"Tank={telemetry['tank_level']} | "
                    f"Temp={telemetry['temperature']}°C | "
                    f"Status={telemetry['system_status']}"
                )

                # ── External Hydration Detection ──
                if not _pump_running:
                    raw_moisture = telemetry.get("soil_moisture_raw", {})
                    for bed_key, val in raw_moisture.items():
                        if val < 0:  # Skip fault readings
                            continue
                        prev_val = _prev_moisture.get(bed_key, val)
                        delta = val - prev_val
                        if delta > 10:
                            zone_num = bed_key.replace("bed", "")
                            try:
                                z_int = int(zone_num)
                            except ValueError:
                                z_int = 0
                                
                            # 5-minute cooldown per zone to prevent quota burn from ADC noise
                            if current_time - _last_hydration_alert.get(z_int, 0) > 300:
                                alert_msg = f"MANUAL_WATERING_DETECTED: Zone {zone_num} moisture rose +{delta:.1f}% while pump OFF."
                                print(f"[HYDRATION] ⚡ {alert_msg}")
                                try:
                                    firebase_manager.push_alerts([alert_msg])
                                except Exception:
                                    pass
                                _last_hydration_alert[z_int] = current_time
                                
                    # Update previous moisture
                    for bed_key, val in raw_moisture.items():
                        if val >= 0:
                            _prev_moisture[bed_key] = val

                # ── Auto Watering AI ──
                # Guard: never run auto watering while the Emergency Stop is active
                if _current_mode == "auto" and telemetry["system_status"] != "tank_low" and not _system_locked:
                    if _auto_strategy == "sensor":
                        # Precision Saturation: fetch per-zone targets from Firestore
                        zone_targets = firebase_manager.get_zone_targets()
                        cal_data = sensor_manager.load_calibration()
                        for key, raw_moisture in telemetry["soil_moisture_raw"].items():
                            if raw_moisture < 0:  # Skip fault readings
                                continue
                            try:
                                z_num = int(key.replace("bed", ""))
                                # ── Zone enabled guard ──
                                if z_num not in _enabled_zones:
                                    continue  # User disabled this zone in the Flutter UI
                                zone_key = f"zone_{z_num}"
                                zone_cal = cal_data.get(zone_key, {})
                                # BUG FIX: Read 'start_threshold' (set by user via Settings),
                                # NOT 'manual_offset_pct' (calibration offset — unrelated field).
                                threshold = zone_cal.get("start_threshold", 0)
                                target_sat = zone_cal.get("target_moisture", config.DEFAULT_TARGET_MOISTURE)
                                timeout = zone_cal.get("max_pump_runtime", config.DEFAULT_MAX_PUMP_RUNTIME)
                                if threshold <= 0:  # No trigger threshold set by user — skip
                                    continue
                                # BUG FIX: Use <= so a reading AT the threshold also triggers.
                                if raw_moisture <= threshold:
                                    if current_time - _last_auto_water.get(z_num, 0) > 3600:  # 1 hour cooldown
                                        # Also cross-check with Firestore targets in case they
                                        # were updated remotely after the last cal_data load.
                                        zt = zone_targets.get(z_num, {})
                                        final_target = zt.get("target", target_sat)
                                        final_timeout = zt.get("timeout", timeout)
                                        print(f"[AUTO-SENSOR] Triggering Zone {z_num} "
                                              f"(Raw: {raw_moisture}% <= Threshold: {threshold}%) "
                                              f"→ Target: {final_target}%, Timeout: {final_timeout}s")
                                        _last_auto_water[z_num] = current_time
                                        threading.Thread(
                                            target=_force_water_task,
                                            args=(z_num, final_timeout, final_target),
                                            daemon=True,
                                        ).start()
                            except ValueError:
                                pass

                    elif _auto_strategy == "timer":
                        import datetime
                        now = datetime.datetime.now()
                        today_str = now.strftime("%Y-%m-%d")
                        global _last_daily_water_date

                        if now.hour == _auto_timer_hour and now.minute == _auto_timer_minute:
                            if _last_daily_water_date != today_str:
                                active = sorted(_enabled_zones)
                                print(f"[AUTO-TIMER] Daily schedule triggered for zones {active} at {now.strftime('%H:%M')}")

                                # Snapshot calibration data once for all zones
                                cal_data = sensor_manager.load_calibration()

                                def _water_all_sequential(zones=active, cal=cal_data):
                                    hstatus = telemetry.get("hardware_status", {})
                                    soil_now, _, _ = sensor_manager.read_soil_moisture()

                                    for z in zones:
                                        # ── Hardware fault guard ──
                                        if hstatus.get(f"bed{z}") == "fault":
                                            print(f"[AUTO-TIMER] Skipping Zone {z} — hardware fault.")
                                            continue

                                        # ── Read per-zone targets from calibration ──
                                        zone_key = f"zone_{z}"
                                        zone_cal = cal.get(zone_key, {})
                                        target_sat = float(zone_cal.get(
                                            "target_moisture", config.DEFAULT_TARGET_MOISTURE))
                                        timeout = int(zone_cal.get(
                                            "max_pump_runtime", config.DEFAULT_MAX_PUMP_RUNTIME))

                                        # ── Pre-check: is target already met? ──
                                        current = soil_now.get(f"bed{z}", 0.0)
                                        if current >= target_sat:
                                            print(
                                                f"[AUTO-TIMER] Zone {z}: Target saturation already met "
                                                f"({current:.1f}% >= {target_sat:.1f}%) — no watering needed."
                                            )
                                            continue  # Skip — soil is already moist enough

                                        # ── Start watering with Pulse & Soak + saturation stop ──
                                        print(
                                            f"[AUTO-TIMER] Zone {z}: Starting watering "
                                            f"(current {current:.1f}% → target {target_sat:.1f}%, "
                                            f"timeout {timeout}s)"
                                        )
                                        _force_water_task(z, timeout, target_sat)
                                        time.sleep(1)  # brief pause between zones

                                threading.Thread(target=_water_all_sequential, daemon=True).start()
                                _last_daily_water_date = today_str
            except Exception as loop_e:
                print(f"[MAIN] Error in main loop: {loop_e}")

            # Throttle loop to avoid CPU spike and limit sensor reads
            time.sleep(max(3.0, interval))


    except KeyboardInterrupt:
        pass
    finally:
        if _auth_bouncer_listener:
            try:
                _auth_bouncer_listener.unsubscribe()
                print("[AUTH_BOUNCER] Listener unsubscribed.")
            except Exception:
                pass
        firebase_manager.cleanup()
        if sensor_manager:
            sensor_manager.cleanup()
        print("[MAIN] Goodbye! 🌿")


if __name__ == "__main__":
    main()
