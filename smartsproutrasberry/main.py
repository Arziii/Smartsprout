"""
Smart Sprout — Main Event Loop
──────────────────────────────────────────────────────────
Reads all hardware sensors on a configurable interval,
publishes telemetry via local MQTT, and listens for
incoming "Force Water" manual override commands.
──────────────────────────────────────────────────────────
"""
import json
import time
import signal
import sys
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
    global _pump_locked
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
    elif command == "set_mode":
        global _current_mode, _auto_strategy, _auto_timer_hour, _auto_timer_minute
        _current_mode = payload.get("mode", "manual")
        _auto_strategy = payload.get("strategy", "sensor")
        _auto_timer_hour = payload.get("timer_hour", 8)
        _auto_timer_minute = payload.get("timer_minute", 0)
        print(f"[SETTINGS] Switched to {_current_mode.upper()} mode, Strategy: {_auto_strategy}, Time: {_auto_timer_hour:02d}:{_auto_timer_minute:02d}")

# ═══════════════════════════════════════════════════════
# Telemetry Collection
# ═══════════════════════════════════════════════════════
def collect_telemetry(interval: float) -> dict:
    """
    Reads ALL sensors and returns a unified telemetry dict.
    The 'status' field indicates health: 'ok', 'sensor_fault', 'tank_low'.
    """
    global _pump_locked

    soil = sensor_manager.read_soil_moisture()
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

    # Sensor fault detection (any value is -1.0)
    if any(s < 0 for s in soil.values()):
        alerts.append("soil_sensor_fault")
        system_status = "sensor_fault"
    if dht["temperature"] < 0 or dht["humidity"] < 0:
        alerts.append("dht_sensor_fault")
        system_status = "sensor_fault"
    if tank < 0:
        alerts.append("tank_sensor_fault")
        system_status = "sensor_fault"
        system_status = "sensor_fault"

    telemetry = {
        "timestamp": int(time.time()),
        "soil_moisture": soil,
        "temperature": dht["temperature"],
        "humidity": dht["humidity"],
        "tank_level": tank,
        "pump_locked": _pump_locked,
        "system_status": system_status,
        "alerts": alerts,
    }

    return telemetry


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
            current_time = time.time()
            telemetry = collect_telemetry(interval)

            # Sync to cloud every 30-60 mins as designated by CLOUD_SYNC_INTERVAL
            if (current_time - last_cloud_sync) >= cloud_sync_interval:
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
                    # Sensor strategy: trigger if moisture < threshold, max once per hour per zone
                    MOISTURE_THRESHOLD = getattr(config, 'MOISTURE_THRESHOLD', 30.0)
                    for key, moisture in telemetry["soil_moisture"].items():
                        if moisture >= 0 and moisture < MOISTURE_THRESHOLD: # Valid reading and dry
                            try:
                                z_num = int(key.replace("bed", ""))
                                if current_time - _last_auto_water.get(z_num, 0) > 3600: # 1 hour cooldown
                                    print(f"[AUTO-SENSOR] Triggering Zone {z_num} (Moisture: {moisture}% < {MOISTURE_THRESHOLD}%)")
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
