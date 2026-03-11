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

import paho.mqtt.client as mqtt

import config
import sensors

# ═══════════════════════════════════════════════════════
# MQTT Topics
# ═══════════════════════════════════════════════════════
TOPIC_TELEMETRY = "smartsprout/telemetry"
TOPIC_COMMAND = "smartsprout/command"
TOPIC_STATUS = "smartsprout/status"
TOPIC_ALERT = "smartsprout/alert"
TOPIC_SETTINGS = "smartsprout/settings"       # System setting responses
TOPIC_SETTINGS_CMD = "smartsprout/settings/cmd" # Incoming setting commands

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


# ═══════════════════════════════════════════════════════
# MQTT Callbacks
# ═══════════════════════════════════════════════════════
def on_connect(client: mqtt.Client, userdata, flags, rc):
    if rc == 0:
        print(f"[MQTT] Connected to broker at {config.MQTT_HOST}:{config.MQTT_PORT}")
        client.subscribe(TOPIC_COMMAND)
        client.subscribe(TOPIC_SETTINGS_CMD)
        # Publish online status
        client.publish(TOPIC_STATUS, json.dumps({"status": "online"}), retain=True)
    else:
        print(f"[MQTT] Connection failed with code {rc}")


def on_message(client: mqtt.Client, userdata, msg: mqtt.MQTTMessage):
    """Handle incoming commands from the Flutter app."""
    global _pump_locked

    try:
        payload = json.loads(msg.payload.decode())
        command = payload.get("command", "")
        print(f"[MQTT] Received command: {payload}")

        if command == "force_water":
            zone = payload.get("zone", 0)

            # Safety check: don't run pump if tank is critically low
            if _pump_locked:
                alert = {
                    "type": "tank_empty",
                    "message": "PUMP LOCKED — Tank level below safety threshold!",
                }
                client.publish(TOPIC_ALERT, json.dumps(alert))
                print(f"[SAFETY] Force water BLOCKED for zone {zone} — tank too low")
                return

            if zone in (1, 2, 3):
                duration = payload.get("duration_seconds", 10)
                print(f"[CMD] Force watering zone {zone} for {duration}s")

                # Run watering in a separate thread to avoid blocking telemetry
                threading.Thread(
                    target=_force_water_task,
                    args=(zone, duration),
                    daemon=True,
                ).start()
            else:
                print(f"[CMD] Invalid zone in force_water: {zone}")

        elif command == "stop_all":
            sensors.deactivate_all()
            print("[CMD] Emergency stop — all zones deactivated")

        # ── Settings Commands ──
        elif command == "wifi_scan":
            networks = sensors.scan_wifi()
            client.publish(TOPIC_SETTINGS, json.dumps({
                "response": "wifi_scan",
                "networks": networks,
            }))
            print(f"[SETTINGS] Wi-Fi scan: found {len(networks)} networks")

        elif command == "wifi_connect":
            ssid = payload.get("ssid", "")
            password = payload.get("password", "")
            result = sensors.connect_wifi(ssid, password)
            client.publish(TOPIC_SETTINGS, json.dumps({
                "response": "wifi_connect",
                **result,
            }))
            print(f"[SETTINGS] Wi-Fi connect: {result}")

        elif command == "wifi_status":
            status = sensors.get_wifi_status()
            client.publish(TOPIC_SETTINGS, json.dumps({
                "response": "wifi_status",
                **status,
            }))
            print(f"[SETTINGS] Wi-Fi status: {status}")

        elif command == "calibrate":
            print("[SETTINGS] Starting calibration routine...")
            result = sensors.run_calibration()
            client.publish(TOPIC_SETTINGS, json.dumps({
                "response": "calibrate",
                **result,
            }))
            print(f"[SETTINGS] Calibration complete: {result}")

        elif command == "firmware_info":
            info = sensors.get_firmware_info()
            client.publish(TOPIC_SETTINGS, json.dumps({
                "response": "firmware_info",
                **info,
            }))
            print(f"[SETTINGS] Firmware info: {info}")

        else:
            print(f"[CMD] Unknown command: {command}")

    except json.JSONDecodeError:
        print(f"[MQTT] Invalid JSON payload: {msg.payload}")
    except Exception as e:
        print(f"[MQTT] Command processing error: {e}")


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

    # ── Connect MQTT ──
    client = mqtt.Client(client_id="smartsprout-pi", clean_session=True)
    client.on_connect = on_connect
    client.on_message = on_message

    # Set last-will so clients know when the Pi goes offline
    client.will_set(
        TOPIC_STATUS,
        json.dumps({"status": "offline"}),
        qos=1,
        retain=True,
    )

    try:
        client.connect(config.MQTT_HOST, config.MQTT_PORT, keepalive=60)
    except ConnectionRefusedError:
        print(f"[MQTT] Cannot connect to broker at {config.MQTT_HOST}:{config.MQTT_PORT}")
        print("[MQTT] Please ensure Mosquitto is running: sudo systemctl start mosquitto")
        sys.exit(1)

    # Start MQTT network loop in background thread
    client.loop_start()

    interval = config.TELEMETRY_INTERVAL
    print(f"[MAIN] Starting telemetry loop (every {interval}s)...\n")

    # ── Main Polling Loop ──
    try:
        while _running:
            telemetry = collect_telemetry(interval)

            # Publish telemetry
            payload = json.dumps(telemetry)
            client.publish(TOPIC_TELEMETRY, payload, qos=0)

            # Publish alerts separately for the Flutter app to handle
            if telemetry["alerts"]:
                client.publish(
                    TOPIC_ALERT,
                    json.dumps({
                        "type": "system",
                        "alerts": telemetry["alerts"],
                        "tank_level": telemetry["tank_level"],
                    }),
                    qos=1,
                )

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
        print("\n[MAIN] Shutting down...")
        client.publish(TOPIC_STATUS, json.dumps({"status": "offline"}), retain=True)
        client.loop_stop()
        client.disconnect()
        sensors.cleanup()
        print("[MAIN] Goodbye! 🌿")


if __name__ == "__main__":
    main()
