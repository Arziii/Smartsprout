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
_DEVICE_CONFIG_FILE = os.path.join(os.path.dirname(__file__), 'storage', 'device_config.json')

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
    cal_file = os.path.join(os.path.dirname(__file__), 'storage', 'calibration_offsets.json')
    if os.path.exists(cal_file):
        os.remove(cal_file)
    print("[CONFIG] Factory reset complete.")

# ── I2C Bus Address ──
ADS1115_I2C_BUS = int(os.getenv("ADS1115_I2C_BUS", "1"))
ADS1115_I2C_ADDRESS = int(os.getenv("ADS1115_I2C_ADDRESS", "0x48"), 16)

# ── DHT22 Temperature/Humidity Sensor (GPIO, not I2C) ──
# Module version powered from 3.3V — DATA line stays ≤3.3V, GPIO-safe.
DHT22_PIN = int(os.getenv("DHT22_PIN", "4"))

# Retry settings for DHT22 reads.
# DHT22 on Linux misses ~30-50% of reads due to OS scheduling jitter.
# The driver retries up to DHT_MAX_RETRIES times (DHT_RETRY_DELAY_S apart)
# before falling back to the last-known-good cached value.
DHT_MAX_RETRIES  = int(os.getenv("DHT_MAX_RETRIES", "5"))
DHT_RETRY_DELAY_S = float(os.getenv("DHT_RETRY_DELAY_S", "0.5"))

# ── Digital Sensors ──
# XKC-Y26-V is a binary non-contact sensor: output is HIGH, LOW, or FAULT (string).
# No percentage threshold applies — do NOT add TANK_LOW_THRESHOLD here.
XKC_LEVEL_PIN = int(os.getenv("XKC_LEVEL_PIN", "6"))

# ── Relay Module (Active LOW) ──
# 3 independent pumps — one per zone. No shared main pump.
RELAY_PUMP_1 = int(os.getenv("RELAY_PUMP1_PIN", "17"))
RELAY_PUMP_2 = int(os.getenv("RELAY_PUMP2_PIN", "27"))
RELAY_PUMP_3 = int(os.getenv("RELAY_PUMP3_PIN", "22"))

ALL_RELAY_PINS = [RELAY_PUMP_1, RELAY_PUMP_2, RELAY_PUMP_3]

# ── Hardware Reset Button (Active LOW with internal pull-up) ──
RESET_BUTTON_PIN = int(os.getenv("RESET_BUTTON_PIN", "24"))
RESET_HOLD_SECONDS = int(os.getenv("RESET_HOLD_SECONDS", "5"))
RESET_LED_PIN = int(os.getenv("RESET_LED_PIN", "18"))

# ── Safety ──
PUMP_TIMEOUT_SECONDS = int(os.getenv("PUMP_TIMEOUT_SECONDS", "120"))

# ── Precision Saturation Defaults ──
DEFAULT_TARGET_MOISTURE = float(os.getenv("DEFAULT_TARGET_MOISTURE", "65.0"))
DEFAULT_MAX_PUMP_RUNTIME = int(os.getenv("DEFAULT_MAX_PUMP_RUNTIME", "30"))

# ── Pulse & Soak (Indoor Auto-Watering) ──
PULSE_BURST_SECONDS = int(os.getenv("PULSE_BURST_SECONDS", "5"))
PULSE_SOAK_SECONDS = int(os.getenv("PULSE_SOAK_SECONDS", "20"))

# ── Calibration ──
SOIL_DRY = int(os.getenv("SOIL_SENSOR_DRY", "12491"))
SOIL_WET = int(os.getenv("SOIL_SENSOR_WET", "6165"))


# ── Firebase ──
FIREBASE_CREDENTIALS_PATH = os.path.join(os.path.dirname(__file__), 'storage', 'firebase-adminsdk.json')

# HW_MAC_ID is the IMMUTABLE hardware identity baked into .env at provisioning time.
# It is the canonical Firestore document key (devices/{HW_MAC_ID}) and the UID
# used when minting Custom Tokens.  It NEVER changes, even when the user sets an alias.
HW_MAC_ID = os.getenv("DEVICE_ID", "SPROUT_A1B2")

# DEVICE_ID is kept for backward compat with the rest of main.py / telemetry.
DEVICE_ID = get_device_id()

# ── Timing ──
TELEMETRY_INTERVAL = int(os.getenv("TELEMETRY_INTERVAL", "3"))
CLOUD_SYNC_INTERVAL = int(os.getenv("CLOUD_SYNC_INTERVAL", "1800"))


# ── System Info ──
FIRMWARE_VERSION = os.getenv("FIRMWARE_VERSION", "1.0.4")
CLEANUP_INTERVAL_HOURS = int(os.getenv("CLEANUP_INTERVAL_HOURS", "24"))
STORAGE_RETENTION_DAYS = int(os.getenv("STORAGE_RETENTION_DAYS", "30"))
