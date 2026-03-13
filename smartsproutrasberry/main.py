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

# ═══════════════════════════════════════════════════════
# Global State
# ═══════════════════════════════════════════════════════
_running = True
_pump_locked = False  # True when tank is critically low


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
        sensors.activate_zone(zone)
        time.sleep(duration)
        sensors.deactivate_all()
        print(f"[CMD] Force water zone {zone} completed ({duration}s)")
    except Exception as e:
        print(f"[ERROR] Force water task failed: {e}")
        sensors.deactivate_all()

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
        sensors.deactivate_all()
        print("[CMD] Emergency stop — all zones deactivated")
    elif command == "calibrate":
        print("[SETTINGS] Starting calibration routine from Firebase...")
        result = sensors.run_calibration()
        print(f"[SETTINGS] Calibration complete: {result}")
    elif command == "dry_calibrate":
        print("[SETTINGS] Starting dry calibration from Firebase...")
        zone = payload.get("zone", None)
        result = sensors.run_dry_calibration(target_zone=zone)
        print(f"[SETTINGS] Dry calibration complete: {result}")
    elif command == "adjust_offset":
        zone = payload.get("zone", 1)
        adjustment = payload.get("adjustment", 0)
        print(f"[SETTINGS] Adjusting manual offset for zone {zone} by {adjustment}%")
        cal_data = sensors.load_calibration()
        zone_key = f"zone_{zone}"
        if zone_key in cal_data:
            new_offset = cal_data[zone_key].get("manual_offset_pct", 0) + adjustment
            new_offset = max(-50, min(50, new_offset))
            cal_data[zone_key]["manual_offset_pct"] = new_offset
            sensors.save_calibration()

# ═══════════════════════════════════════════════════════
# Telemetry Collection
# ═══════════════════════════════════════════════════════
def collect_telemetry(interval: float) -> dict:
    """
    Reads ALL sensors and returns a unified telemetry dict.
    The 'status' field indicates health: 'ok', 'sensor_fault', 'tank_low'.
    """
    global _pump_locked

    soil = sensors.read_soil_moisture()
    dht = sensors.read_dht22()
    tank = sensors.read_tank_level()
    flow = sensors.read_flow_rate(interval)

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
    if any(s < 0 for s in soil):
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
        "flow_rate": flow,
        "pump_locked": _pump_locked,
        "system_status": system_status,
        "alerts": alerts,
    }

    return telemetry


# ═══════════════════════════════════════════════════════
# Main Loop
# ═══════════════════════════════════════════════════════
def main():
    print("═" * 55)
    print("  🌱 Smart Sprout — Raspberry Pi Controller v1.0")
    print("═" * 55)

    # ── Initialize Hardware ──
    sensors.setup_relays()
    sensors.setup_flow_sensor()
    print("[INIT] Hardware initialized.")

    # MQTT logic removed for Zero-Trust Architecture

    # ── Connect Firebase ──
    if firebase_manager.init_firebase():
        firebase_manager.listen_for_commands(handle_firebase_command)

    interval = config.TELEMETRY_INTERVAL
    print(f"[MAIN] Starting telemetry loop (every {interval}s)...\n")

    # ── Main Polling Loop ──
    try:
        while _running:
            telemetry = collect_telemetry(interval)

            try:
                # Publish telemetry to Firebase
                firebase_manager.push_telemetry(telemetry)

                # Publish alerts separately to Firebase
                if telemetry["alerts"]:
                    firebase_manager.push_alerts(telemetry["alerts"])
            except Exception as e:
                print(f"[FIREBASE] Offline or error pushing to cloud: {e}")

            print(
                f"[TEL] Soil={telemetry['soil_moisture']} | "
                f"Tank={telemetry['tank_level']}% | "
                f"Flow={telemetry['flow_rate']}L/m | "
                f"Temp={telemetry['temperature']}°C | "
                f"Status={telemetry['system_status']}"
            )

            time.sleep(interval)

    except KeyboardInterrupt:
        pass
    finally:
        firebase_manager.cleanup()
        sensors.cleanup()
        print("[MAIN] Goodbye! 🌿")


if __name__ == "__main__":
    main()
