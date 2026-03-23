"""
Smart Sprout — GPIO & Pin Configuration
Centralizes all hardware pin assignments from the .env file.
"""
import os
import json
from dotenv import load_dotenv

load_dotenv()

# ═══════════════════════════════════════════════════════
# Dynamic Device Config (device_config.json)
# ═══════════════════════════════════════════════════════
_DEVICE_CONFIG_FILE = os.path.join(os.path.dirname(__file__), 'device_config.json')

def _load_device_config() -> dict:
    """Load the device config JSON, falling back to defaults if missing."""
    try:
        with open(_DEVICE_CONFIG_FILE, 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        default = {"device_id": os.getenv("DEVICE_ID", "SPROUT_A1B2"), "password": "1234"}
        _save_device_config(default)
        return default

def _save_device_config(data: dict):
    """Persist the device config to disk."""
    with open(_DEVICE_CONFIG_FILE, 'w') as f:
        json.dump(data, f, indent=4)

def get_device_id() -> str:
    """Read the current device ID from device_config.json."""
    return _load_device_config().get("device_id", os.getenv("DEVICE_ID", "SPROUT_A1B2"))

def update_device_id(new_id: str):
    """Update the device ID in device_config.json."""
    cfg = _load_device_config()
    cfg["device_id"] = new_id
    _save_device_config(cfg)
    print(f"[CONFIG] Device ID updated to: {new_id}")

def factory_reset():
    """Reset device_config.json to defaults and wipe calibration."""
    _save_device_config({"device_id": "SPROUT_A1B2", "password": "1234"})
    cal_file = os.path.join(os.path.dirname(__file__), 'calibration_offsets.json')
    if os.path.exists(cal_file):
        os.remove(cal_file)
    print("[CONFIG] Factory reset complete.")

# ── I2C (ADS1115 ADC) ──
ADS1115_I2C_BUS = int(os.getenv("ADS1115_I2C_BUS", "1"))
ADS1115_I2C_ADDRESS = int(os.getenv("ADS1115_I2C_ADDRESS", "0x48"), 16)

# ── Digital Sensors ──
DHT22_PIN = int(os.getenv("DHT22_GPIO_PIN", "4"))
ULTRASONIC_TRIGGER = int(os.getenv("ULTRASONIC_TRIGGER_PIN", "5"))
ULTRASONIC_ECHO = int(os.getenv("ULTRASONIC_ECHO_PIN", "6"))

# ── Relay Module (Active LOW) ──
RELAY_PUMP = int(os.getenv("RELAY_PUMP_PIN", "17"))
RELAY_VALVE_1 = int(os.getenv("RELAY_VALVE1_PIN", "27"))
RELAY_VALVE_2 = int(os.getenv("RELAY_VALVE2_PIN", "22"))
RELAY_VALVE_3 = int(os.getenv("RELAY_VALVE3_PIN", "23"))

ALL_RELAY_PINS = [RELAY_PUMP, RELAY_VALVE_1, RELAY_VALVE_2, RELAY_VALVE_3]

# ── Hardware Reset Button (Active LOW with internal pull-up) ──
RESET_BUTTON_PIN = int(os.getenv("RESET_BUTTON_PIN", "24"))
RESET_HOLD_SECONDS = int(os.getenv("RESET_HOLD_SECONDS", "5"))
RESET_LED_PIN = int(os.getenv("RESET_LED_PIN", "18"))

# ── Safety ──
PUMP_TIMEOUT_SECONDS = int(os.getenv("PUMP_TIMEOUT_SECONDS", "30"))

# ── Precision Saturation Defaults ──
DEFAULT_TARGET_MOISTURE = float(os.getenv("DEFAULT_TARGET_MOISTURE", "65.0"))
DEFAULT_MAX_PUMP_RUNTIME = int(os.getenv("DEFAULT_MAX_PUMP_RUNTIME", "30"))

# ── Pulse & Soak (Indoor Auto-Watering) ──
PULSE_BURST_SECONDS = int(os.getenv("PULSE_BURST_SECONDS", "5"))
PULSE_SOAK_SECONDS = int(os.getenv("PULSE_SOAK_SECONDS", "20"))

# ── Calibration ──
SOIL_DRY = int(os.getenv("SOIL_SENSOR_DRY", "26000"))
SOIL_WET = int(os.getenv("SOIL_SENSOR_WET", "13000"))

TANK_HEIGHT_CM = float(os.getenv("TANK_HEIGHT_CM", "40"))
TANK_EMPTY_DISTANCE = float(os.getenv("TANK_EMPTY_DISTANCE_CM", "40"))
TANK_FULL_DISTANCE = float(os.getenv("TANK_FULL_DISTANCE_CM", "5"))

# ── Safety ──
TANK_LOW_THRESHOLD = int(os.getenv("TANK_LOW_THRESHOLD", "10"))
# ── MQTT ──
MQTT_HOST = os.getenv("MQTT_BROKER_HOST", "localhost")
MQTT_PORT = int(os.getenv("MQTT_BROKER_PORT", "1883"))

# ── Firebase ──
FIREBASE_CREDENTIALS_PATH = os.getenv("FIREBASE_CREDENTIALS_PATH", "firebase-adminsdk.json")
DEVICE_ID = get_device_id()

# ── Timing ──
TELEMETRY_INTERVAL = int(os.getenv("TELEMETRY_INTERVAL", "3"))
CLOUD_SYNC_INTERVAL = int(os.getenv("CLOUD_SYNC_INTERVAL", "1800"))

# ── Storage Management ──
STORAGE_RETENTION_DAYS = int(os.getenv("STORAGE_RETENTION_DAYS", "30"))
CLEANUP_INTERVAL_HOURS = int(os.getenv("CLEANUP_INTERVAL_HOURS", "24"))

# ── System Info ──
FIRMWARE_VERSION = os.getenv("FIRMWARE_VERSION", "1.0.4")
