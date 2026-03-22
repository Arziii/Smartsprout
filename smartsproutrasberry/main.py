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
_pump_locked = False  # True when tank is critically low
sensor_manager = None
_current_mode = "manual"
_auto_strategy = "sensor"
_auto_timer_hour = 8
_auto_timer_minute = 0
_last_auto_water = {1: 0, 2: 0, 3: 0} # Cooldown tracking per zone
_last_daily_water_date = ""
_last_sent_telemetry = {}  # Tracks last cloud-pushed values for differential sync
_force_sync = False


def _signal_handler(sig, frame):
    global _running
    print("\n[MAIN] Graceful shutdown requested...")
    _running = False


signal.signal(signal.SIGINT, _signal_handler)
signal.signal(signal.SIGTERM, _signal_handler)


# Local handling removed. All commands come through Firebase.


def _force_water_task(zone: int, duration: int):
    """Run a watering cycle in its own thread."""
    try:
        sensor_manager.activate_zone(zone)
        time.sleep(duration)
        sensor_manager.deactivate_all()
        print(f"[CMD] Force water zone {zone} completed ({duration}s)")
    except Exception as e:
        print(f"[ERROR] Force water task failed: {e}")
        sensor_manager.deactivate_all()

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
    elif command == "stop_all":
        sensor_manager.deactivate_all()
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
def collect_telemetry(interval: float) -> dict:
    """
    Reads ALL sensors and returns a unified telemetry dict.
    The 'status' field indicates health: 'ok', 'sensor_fault', 'tank_low'.
    """
    global _pump_locked

    soil, soil_raw, soil_fault = sensor_manager.read_soil_moisture()
    dht = sensor_manager.read_dht22()
    tank = sensor_manager.read_tank_level()

    # ── Safety Logic ──
    alerts = []
    system_status = "ok"

    # Tank safety lock
    if tank >= 0 and tank < config.TANK_LOW_THRESHOLD:
        _pump_locked = True
        alerts.append("tank_empty")
        system_status = "tank_low"
    elif tank >= config.TANK_LOW_THRESHOLD:
        _pump_locked = False

    # Sensor fault detection
    if soil_fault or any(s < 0 for s in soil.values()):
        alerts.append("soil_sensor_fault")
        system_status = "sensor_fault"
    if dht["temperature"] < 0 or dht["humidity"] < 0:
        alerts.append("dht_sensor_fault")
        system_status = "sensor_fault"
    if tank < 0:
        alerts.append("tank_sensor_fault")
        system_status = "sensor_fault"
        system_status = "sensor_fault"

    # Read current offsets from calibration data
    cal_data = sensor_manager.load_calibration()
    soil_offsets = {
        "bed1": cal_data.get("zone_1", {}).get("manual_offset_pct", 0),
        "bed2": cal_data.get("zone_2", {}).get("manual_offset_pct", 0),
        "bed3": cal_data.get("zone_3", {}).get("manual_offset_pct", 0),
    }

    telemetry = {
        "timestamp": int(time.time()),
        "soil_moisture": soil,
        "soil_moisture_raw": soil_raw,
        "soil_offsets": soil_offsets,
        "temperature": dht["temperature"],
        "humidity": dht["humidity"],
        "tank_level": tank,
        "pump_locked": _pump_locked,
        "system_status": system_status,
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

    # Tank level delta > 5%
    last_tank = _last_sent_telemetry.get("tank_level", 0)
    curr_tank = current.get("tank_level", 0)
    if abs(curr_tank - last_tank) > 5:
        print(f"[DIFF_SYNC] Tank level change detected: {last_tank}→{curr_tank}%")
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

    interval = config.TELEMETRY_INTERVAL
    cloud_sync_interval = config.CLOUD_SYNC_INTERVAL
    last_cloud_sync = 0
    print(f"[MAIN] Starting local polling loop (every {interval}s)...")
    print(f"[MAIN] Cloud sync interval set to {cloud_sync_interval} seconds ({(cloud_sync_interval/60):.1f} min).\n")

    # ── Main Polling Loop ──
    try:
        while _running:
            global _force_sync
            current_time = time.time()
            telemetry = collect_telemetry(interval)

            # ── Differential Sync: push immediately if critical values changed ──
            diff_push = _should_differential_push(telemetry)

            # Sync to cloud every 30-60 mins as designated by CLOUD_SYNC_INTERVAL (or immediately if commanded)
            if _force_sync or diff_push or (current_time - last_cloud_sync) >= cloud_sync_interval:
                try:
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
                    print(f"[FIREBASE] Telemetry payload synced to cloud (next sync in {cloud_sync_interval}s).")
                except Exception as e:
                    print(f"[FIREBASE] Offline or error pushing to cloud: {e}")

            print(
                f"[TEL] Soil={telemetry['soil_moisture']} | "
                f"Tank={telemetry['tank_level']}% | "
                f"Temp={telemetry['temperature']}°C | "
                f"Status={telemetry['system_status']}"
            )

            # ── Auto Watering AI ──
            if _current_mode == "auto" and telemetry["system_status"] != "tank_low":
                if _auto_strategy == "sensor":
                    # Sensor strategy: trigger if raw moisture < user's calibration threshold
                    # The threshold is the value the user SET in the Calibration screen
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
                                    print(f"[AUTO-SENSOR] Triggering Zone {z_num} (Raw: {raw_moisture}% < Threshold: {threshold}%)")
                                    _last_auto_water[z_num] = current_time
                                    threading.Thread(target=_force_water_task, args=(z_num, 10), daemon=True).start()
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
                                for z in [1, 2, 3]:
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
