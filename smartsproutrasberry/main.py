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
import firebase_manager

from sensors import SensorManager

# ═══════════════════════════════════════════════════════
# Global State
# ═══════════════════════════════════════════════════════
_running = True
_pump_locked = False  # True when XKC tank sensor reads LOW or FAULT (binary sensor, no percentage)
sensor_manager = None
_current_mode = "manual"
_auto_strategy = "sensor"
_auto_timer_hour = 8
_auto_timer_minute = 0
_last_auto_water = {1: 0, 2: 0, 3: 0} # Cooldown tracking per zone
_last_daily_water_date = ""
_last_sent_telemetry = {}  # Tracks last cloud-pushed values for differential sync
_force_sync = False

# Dead-Man's Switch state
_manual_pump_active = False
_manual_pump_zone = 0

# External Hydration Detection
_prev_moisture = {}  # {"bed1": 42.0, "bed2": 55.0, ...}
_pump_running = False  # True when any pump/valve is active


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
        time.sleep(2)  # Check every 2 seconds

    print(f"[DEADMAN] Heartbeat monitor stopped for Zone {zone}")

def handle_firebase_command(payload: dict):
    """Handle incoming commands from Firebase Cloud Firestore."""
    global _pump_locked, _force_sync
    command = payload.get("command", "")
    print(f"[FIREBASE_CMD_PROCESS] {payload}")
    
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
        global _current_mode, _auto_strategy, _auto_timer_hour, _auto_timer_minute
        _current_mode = payload.get("mode", "manual")
        _auto_strategy = payload.get("strategy", "sensor")
        _auto_timer_hour = payload.get("timer_hour", 8)
        _auto_timer_minute = payload.get("timer_minute", 0)
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
        import os
        print("[MAINTENANCE] Kiosk application restart requested. Killing Flutter UI...")
        os.system("pkill -f smartsprout")
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

    # Tank safety lock String formatting
    if tank == "LOW" or tank == "FAULT":
        _pump_locked = True
        alerts.append("tank_empty" if tank == "LOW" else "tank_sensor_fault")
        system_status = "tank_low" if tank == "LOW" else "sensor_fault"
    elif tank == "HIGH":
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
        "system_status": system_status,
        "hardware_status": hardware_status,
        "alerts": alerts,
    }

    return telemetry


# ═══════════════════════════════════════════════════════
# Differential Sync — Threshold-based immediate push
# ═══════════════════════════════════════════════════════
def _should_differential_push(current: dict) -> bool:
    """
    Returns True if critical sensor values have changed beyond thresholds
    compared to the last cloud-pushed telemetry. This triggers an immediate
    sync even if the Eco-Mode timer hasn't expired.
    """
    global _last_sent_telemetry
    if not _last_sent_telemetry:
        return False  # First reading — let the normal sync handle it

    # Temperature delta > 1.5°C
    last_temp = _last_sent_telemetry.get("temperature", 0)
    curr_temp = current.get("temperature", 0)
    if abs(curr_temp - last_temp) > 1.5:
        print(f"[DIFF_SYNC] Temperature change detected: {last_temp}→{curr_temp}°C")
        return True

    # Tank level string comparison
    last_tank = _last_sent_telemetry.get("tank_level", "FAULT")
    curr_tank = current.get("tank_level", "FAULT")
    if curr_tank != last_tank:
        print(f"[DIFF_SYNC] Tank level change detected: {last_tank}→{curr_tank}")
        return True

    # Soil moisture delta > 3% (any bed)
    last_soil = _last_sent_telemetry.get("soil_moisture", {})
    curr_soil = current.get("soil_moisture", {})
    for bed in curr_soil:
        last_val = last_soil.get(bed, 0)
        curr_val = curr_soil.get(bed, 0)
        if isinstance(curr_val, (int, float)) and isinstance(last_val, (int, float)):
            if abs(curr_val - last_val) > 3:
                print(f"[DIFF_SYNC] Soil {bed} change detected: {last_val}→{curr_val}%")
                return True

    return False


# ═══════════════════════════════════════════════════════
# Main Loop
# ═══════════════════════════════════════════════════════
def main():
    global sensor_manager
    print("═" * 55)
    print("  🌱 Smart Sprout — Raspberry Pi Controller v1.0")
    print("═" * 55)

    # ── Initialize Hardware ──
    print("[INIT] Instantiating SensorManager...")
    sensor_manager = SensorManager()
    sensor_manager.setup_relays()
    print("[INIT] Hardware initialized.")

    # ── Start Hardware Reset Button Monitor ──
    import reset_button
    reset_button.start_reset_button_monitor()

    # ── Start Pump Safety Watchdog ──
    import pump_watchdog
    pump_watchdog.start_pump_watchdog()

    # ── Start Heartbeat Thread ──
    def _heartbeat_loop():
        while _running:
            firebase_manager.send_heartbeat()
            time.sleep(60)
    threading.Thread(target=_heartbeat_loop, daemon=True).start()
    print("[INIT] Heartbeat thread started (60s interval)")

    # MQTT logic removed for Zero-Trust Architecture

    # ── Connect Firebase ──
    if firebase_manager.init_firebase():
        firebase_manager.listen_for_commands(handle_firebase_command)

    interval = config.TELEMETRY_INTERVAL          # Local sensor read cadence (3 s)
    cloud_sync_interval = config.CLOUD_SYNC_INTERVAL  # Eco-Mode ceiling (1800 s = 30 min)

    # ── Seed the clock and diff baseline BEFORE entering the loop ──
    # Initialising to time.time() (not 0) prevents an immediate Firebase write
    # on the very first iteration. The first real push will happen once one of
    # the three gate conditions becomes True organically.
    last_cloud_sync = time.time()

    # Seed the differential-sync baseline with a real sensor reading so the
    # diff logic does not compare against an empty dict and fire immediately.
    print("[MAIN] Seeding differential-sync baseline...")
    try:
        _last_sent_telemetry = collect_telemetry()
    except Exception as _seed_err:
        print(f"[WARN] Could not seed telemetry baseline: {_seed_err}")
        _last_sent_telemetry = {}

    print(f"[MAIN] Starting local polling loop (every {interval}s)...")
    print(f"[MAIN] Cloud sync interval set to {cloud_sync_interval}s ({cloud_sync_interval/60:.0f} min). "
          f"Differential threshold: 3% moisture / 1.5°C.\n")

    # ── Main Polling Loop ──
    try:
        while _running:
            global _force_sync
            current_time = time.time()
            telemetry = collect_telemetry()

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
                    # Publish telemetry to Firebase
                    firebase_manager.push_telemetry(telemetry)

                    # Publish alerts separately to Firebase
                    if telemetry["alerts"]:
                        firebase_manager.push_alerts(telemetry["alerts"])

                    # ── Storage Management ──
                    # Cleanup old data (older than 30 days by default)
                    firebase_manager.perform_storage_cleanup()

                    last_cloud_sync = current_time
                    _force_sync = False
                    _last_sent_telemetry = telemetry.copy()  # Update baseline for differential sync
                    mins_until_next = cloud_sync_interval / 60
                    print(f"[FIREBASE] Telemetry synced ✓ (next Eco-Mode push in {mins_until_next:.0f} min unless diff/force fires first).")
                except Exception as e:
                    print(f"[FIREBASE] Push FAILED — will retry on next trigger. Error: {e}")

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
                        alert_msg = f"MANUAL_WATERING_DETECTED: Zone {zone_num} moisture rose +{delta:.1f}% while pump OFF."
                        print(f"[HYDRATION] ⚡ {alert_msg}")
                        try:
                            firebase_manager.push_alerts([alert_msg])
                        except Exception:
                            pass
                # Update previous moisture
                for bed_key, val in raw_moisture.items():
                    if val >= 0:
                        _prev_moisture[bed_key] = val

            # ── Auto Watering AI ──
            if _current_mode == "auto" and telemetry["system_status"] != "tank_low":
                if _auto_strategy == "sensor":
                    # Precision Saturation: fetch per-zone targets from Firestore
                    zone_targets = firebase_manager.get_zone_targets()
                    cal_data = sensor_manager.load_calibration()
                    for key, raw_moisture in telemetry["soil_moisture_raw"].items():
                        if raw_moisture < 0:  # Skip fault readings
                            continue
                        try:
                            z_num = int(key.replace("bed", ""))
                            zone_key = f"zone_{z_num}"
                            threshold = cal_data.get(zone_key, {}).get("manual_offset_pct", 0)
                            if threshold <= 0:  # No threshold set by user
                                continue
                            if raw_moisture < threshold:
                                if current_time - _last_auto_water.get(z_num, 0) > 3600:  # 1 hour cooldown
                                    zt = zone_targets.get(z_num, {})
                                    target = zt.get("target", config.DEFAULT_TARGET_MOISTURE)
                                    timeout = zt.get("timeout", config.DEFAULT_MAX_PUMP_RUNTIME)
                                    print(f"[AUTO-SENSOR] Triggering Zone {z_num} "
                                          f"(Raw: {raw_moisture}% < Threshold: {threshold}%) "
                                          f"→ Target: {target}%, Timeout: {timeout}s")
                                    _last_auto_water[z_num] = current_time
                                    threading.Thread(
                                        target=_force_water_task,
                                        args=(z_num, timeout, target),
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
                            print(f"[AUTO-TIMER] Triggering daily schedule for all zones at {now.strftime('%H:%M')}")
                            def _water_all_sequential():
                                hstatus = telemetry.get("hardware_status", {})
                                for z in [1, 2, 3]:
                                    if hstatus.get(f"bed{z}") == "fault":
                                        print(f"[AUTO-TIMER] Skipping Zone {z} due to hardware fault (hardlocked safety).")
                                        continue
                                    _force_water_task(z, 10)
                                    time.sleep(1) # brief pause
                            threading.Thread(target=_water_all_sequential, daemon=True).start()
                            _last_daily_water_date = today_str

            time.sleep(interval)

    except KeyboardInterrupt:
        pass
    finally:
        firebase_manager.cleanup()
        if sensor_manager:
            sensor_manager.cleanup()
        print("[MAIN] Goodbye! 🌿")


if __name__ == "__main__":
    main()
