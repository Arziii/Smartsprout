"""
Smart Sprout — Sensor Drivers
Hardware abstraction layer for all physical sensors.
All reads are wrapped in try/except to prevent crashes from I2C IOErrors or voltage spikes.
"""
import time
import threading
import json
import os
import config

# ──────────────────────────────────────────────────────
# Conditional imports: graceful fallback for dev machines
# ──────────────────────────────────────────────────────
try:
    import RPi.GPIO as GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setwarnings(False)
    _GPIO_AVAILABLE = True
except (ImportError, RuntimeError):
    _GPIO_AVAILABLE = False
    print("[WARN] RPi.GPIO not available — running in SIMULATION mode.")

try:
    from smbus2 import SMBus
    _SMBUS_AVAILABLE = True
except ImportError:
    _SMBUS_AVAILABLE = False
    print("[WARN] smbus2 not available — soil sensors will return mock data.")

try:
    import board
    import adafruit_bme280.basic as adafruit_bme280
    _BME_AVAILABLE = True
    
    # Initialize I2C and the BME280 sensor
    _i2c = board.I2C()
    _bme_device = adafruit_bme280.Adafruit_BME280_I2C(_i2c, address=config.BME280_I2C_ADDRESS)
    
except (ImportError, ValueError, RuntimeError, AttributeError) as e:
    _BME_AVAILABLE = False
    _bme_device = None
    print(f"[WARN] BME280 init failed ({e}) — Temp/Hum/Pres will return mock data.")


# ═══════════════════════════════════════════════════════
# ADS1115 — 3-Channel Soil Moisture via I2C ADC
# ═══════════════════════════════════════════════════════
CALIBRATION_FILE = os.path.join(os.path.dirname(__file__), 'calibration_offsets.json')
_calibration_data = None

def load_calibration():
    global _calibration_data
    if _calibration_data is None:
        try:
            with open(CALIBRATION_FILE, 'r') as f:
                _calibration_data = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            print("[WARN] Could not load calibration_offsets.json. Creating default.")
            _calibration_data = {
                "zone_1": {"dry_raw": config.SOIL_DRY, "wet_raw": config.SOIL_WET, "manual_offset_pct": 0},
                "zone_2": {"dry_raw": config.SOIL_DRY, "wet_raw": config.SOIL_WET, "manual_offset_pct": 0},
                "zone_3": {"dry_raw": config.SOIL_DRY, "wet_raw": config.SOIL_WET, "manual_offset_pct": 0}
            }
            save_calibration()
    return _calibration_data

def save_calibration():
    if _calibration_data is not None:
        with open(CALIBRATION_FILE, 'w') as f:
            json.dump(_calibration_data, f, indent=4)

# ADS1115 Register addresses
_ADS_CONVERSION_REG = 0x00
_ADS_CONFIG_REG = 0x01

# Config bits for single-shot, FSR ±4.096V, 128 SPS
_ADS_BASE_CONFIG = 0xC183  # OS=1, MUX=000, PGA=001, MODE=1, DR=100, COMP=11

def _read_ads1115_channel(bus: "SMBus", channel: int) -> int:
    """Read a single ADC channel (0-3) from the ADS1115."""
    mux = (0x04 + channel) << 12
    config_val = _ADS_BASE_CONFIG | mux
    bus.write_i2c_block_data(
        config.ADS1115_I2C_ADDRESS,
        _ADS_CONFIG_REG,
        [(config_val >> 8) & 0xFF, config_val & 0xFF],
    )
    time.sleep(0.01)  # Wait for conversion
    data = bus.read_i2c_block_data(config.ADS1115_I2C_ADDRESS, _ADS_CONVERSION_REG, 2)
    raw = (data[0] << 8) | data[1]
    if raw > 32767:
        raw -= 65536
    return raw


def read_soil_moisture() -> tuple[dict, dict, bool]:
    """
    Returns a 3-tuple: (calibrated_dict, raw_dict, is_fault_boolean)
    calibrated_dict: {bed1: float, ...} with manual offsets applied (0-100%)
    raw_dict:        {bed1: float, ...} raw sensor percentage BEFORE offsets (0-100%)
    """
    cal_data = load_calibration()
    
    if not _SMBUS_AVAILABLE:
        # No hardware: raw is 0%, calibrated is 0% + offset
        raw_results = {"bed1": 0.0, "bed2": 0.0, "bed3": 0.0}
        cal_results = {
            "bed1": max(0.0, min(100.0, 0.0 + cal_data["zone_1"].get("manual_offset_pct", 0))),
            "bed2": max(0.0, min(100.0, 0.0 + cal_data["zone_2"].get("manual_offset_pct", 0))),
            "bed3": max(0.0, min(100.0, 0.0 + cal_data["zone_3"].get("manual_offset_pct", 0)))
        }
        return cal_results, raw_results, False

    try:
        bus = SMBus(config.ADS1115_I2C_BUS)
        cal_results = {}
        raw_results = {}
        for ch in range(3):
            zone_key = f"zone_{ch+1}"
            dry_raw = cal_data[zone_key].get("dry_raw", config.SOIL_DRY)
            wet_raw = cal_data[zone_key].get("wet_raw", config.SOIL_WET)
            offset = cal_data[zone_key].get("manual_offset_pct", 0)

            raw = _read_ads1115_channel(bus, ch)
            
            # Avoid division by zero
            if dry_raw == wet_raw:
               pct = 0.0
            else:
               # Invert: capacitive sensors read HIGH when dry
               pct = (dry_raw - raw) / (dry_raw - wet_raw) * 100.0
            
            # Raw sensor percentage (before offset), clamped
            raw_pct = max(0.0, min(100.0, pct))
            raw_results[f"bed{ch+1}"] = round(raw_pct, 1)

            # Calibrated = raw + offset, clamped
            cal_pct = max(0.0, min(100.0, pct + offset))
            cal_results[f"bed{ch+1}"] = round(cal_pct, 1)
        bus.close()
        return cal_results, raw_results, False
    except (IOError, OSError) as e:
        print(f"[WARN] I2C soil read failed (no hardware?): {e} — returning mock data.")
        mock_results = {"bed1": -1.0, "bed2": -1.0, "bed3": -1.0}
        return mock_results, mock_results, True  # Return fault sentinel and set fault bit

def run_dry_calibration(target_zone=None) -> dict:
    """
    Samples current sensor values and sets them as the new 'dry' reference (0%).
    target_zone: 1, 2, 3 or None (all zones)
    """
    cal_data = load_calibration()
    results = {"status": "success", "updates": {}}
    
    if not _SMBUS_AVAILABLE:
        print("[WARN] Dry calibration called but SMBus not available.")
        return {"status": "error", "message": "Simulation mode, hardware not available."}
        
    try:
        bus = SMBus(config.ADS1115_I2C_BUS)
        zones_to_test = [target_zone - 1] if target_zone in (1, 2, 3) else [0, 1, 2]
        
        for ch in zones_to_test:
            readings = []
            for _ in range(10):
                readings.append(_read_ads1115_channel(bus, ch))
                time.sleep(0.02)
            avg_raw = int(sum(readings) / len(readings))
            
            zone_key = f"zone_{ch+1}"
            cal_data[zone_key]["dry_raw"] = avg_raw
            cal_data[zone_key]["manual_offset_pct"] = 0 # Reset manual offset on recalibration
            results["updates"][zone_key] = avg_raw
            
        bus.close()
        save_calibration()
        return results
    except (IOError, OSError) as e:
        print(f"[ERROR] Dry calibration failed: {e}")
        return {"status": "error", "message": str(e)}




# ═══════════════════════════════════════════════════════
# BME280 — Temperature, Humidity & Pressure
# ═══════════════════════════════════════════════════════
def read_environment() -> dict:
    """
    Returns {"temperature": float, "humidity": float, "pressure": float}.
    Values are 0.0 on sensor fault or simulation.
    """
    if not _BME_AVAILABLE or not _bme_device:
        return {"temperature": -1.0, "humidity": -1.0, "pressure": -1.0}

    try:
        return {
            "temperature": round(_bme_device.temperature, 1),
            "humidity": round(_bme_device.humidity, 1),
            "pressure": round(_bme_device.pressure, 1),
        }
    except Exception as e:
        print(f"[ERROR] BME280 read failure: {e}")
        return {"temperature": -1.0, "humidity": -1.0, "pressure": -1.0}


# ═══════════════════════════════════════════════════════
# XKC-Y26-V — Non-contact Tank Level (Digital)
# ═══════════════════════════════════════════════════════
def _setup_tank_sensor():
    if not _GPIO_AVAILABLE:
        return
    GPIO.setup(config.XKC_LEVEL_PIN, GPIO.IN)


def read_tank_level() -> float:
    """
    Returns tank fill percentage (0-100%).
    Since XKC is a digital sensor, it returns 100% if water is detected 
    at the sensor's mounting level, and 0% if not.
    """
    if not _GPIO_AVAILABLE:
        return 0.0

    try:
        _setup_tank_sensor()
        # XKC-Y26-V typically outputs HIGH when water is detected.
        # Ensure your specific model's logic matches (adjust if needed).
        if GPIO.input(config.XKC_LEVEL_PIN):
            return 100.0
        return 0.0

    except Exception as e:
        print(f"[ERROR] Tank level read failed: {e}")
        return -1.0





# ═══════════════════════════════════════════════════════
# System Utilities — Wi-Fi, Calibration, Firmware
# ═══════════════════════════════════════════════════════
import subprocess
import json as _json


def scan_wifi() -> list[dict]:
    """
    Scan for available Wi-Fi networks using nmcli.
    Returns a list of dicts: [{"ssid": str, "signal": int, "security": str}]
    """
    try:
        result = subprocess.run(
            ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY", "dev", "wifi", "list"],
            capture_output=True, text=True, timeout=15,
        )
        networks = []
        seen = set()
        for line in result.stdout.strip().split("\n"):
            if not line:
                continue
            parts = line.split(":")
            if len(parts) >= 3:
                ssid = parts[0]
                if not ssid or ssid in seen:
                    continue
                seen.add(ssid)
                networks.append({
                    "ssid": ssid,
                    "signal": int(parts[1]) if parts[1].isdigit() else 0,
                    "security": parts[2] if parts[2] else "Open",
                })
        return networks
    except Exception as e:
        print(f"[ERROR] Wi-Fi scan failed: {e}")
        return []


def connect_wifi(ssid: str, password: str) -> dict:
    """
    Connect the Raspberry Pi to a Wi-Fi network via nmcli.
    Returns {"success": bool, "message": str}.
    """
    try:
        result = subprocess.run(
            ["nmcli", "dev", "wifi", "connect", ssid, "password", password],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            return {"success": True, "message": f"Connected to {ssid}"}
        else:
            return {"success": False, "message": result.stderr.strip() or "Connection failed"}
    except Exception as e:
        return {"success": False, "message": str(e)}


def get_wifi_status() -> dict:
    """Returns current Wi-Fi connection info."""
    try:
        result = subprocess.run(
            ["nmcli", "-t", "-f", "GENERAL.CONNECTION,GENERAL.STATE,WIFI.SSID",
             "dev", "show", "wlan0"],
            capture_output=True, text=True, timeout=10,
        )
        info = {}
        for line in result.stdout.strip().split("\n"):
            if ":" in line:
                key, val = line.split(":", 1)
                info[key.strip()] = val.strip()
        ssid = info.get("GENERAL.CONNECTION", "Not connected")
        state = info.get("GENERAL.STATE", "unknown")
        return {"ssid": ssid, "state": state, "connected": "connected" in state.lower()}
    except Exception as e:
        return {"ssid": "Unknown", "state": "error", "connected": False}


def run_calibration() -> dict:
    """
    Performs a sensor calibration by taking 10 rapid readings
    and returning the averaged raw ADC values.
    """
    results = {"soil_raw": [], "tank_status": "ok"}

    # Soil calibration (average of 10 reads per channel)
    if _SMBUS_AVAILABLE:
        try:
            bus = SMBus(config.ADS1115_I2C_BUS)
            for ch in range(3):
                readings = []
                for _ in range(10):
                    readings.append(_read_ads1115_channel(bus, ch))
                    time.sleep(0.02)
                avg = sum(readings) / len(readings)
                results["soil_raw"].append(round(avg, 1))

            bus.close()
        except (IOError, OSError) as e:
            print(f"[ERROR] Calibration soil read failed: {e}")
            results["soil_raw"] = [-1, -1, -1]

    # Simple digital check for tank sensor
    results["tank_level"] = read_tank_level()

    results["status"] = "complete"
    return results


def get_firmware_info() -> dict:
    """Returns firmware version and system info."""
    import platform
    try:
        uptime_result = subprocess.run(
            ["uptime", "-p"], capture_output=True, text=True, timeout=5
        )
        uptime_str = uptime_result.stdout.strip() if uptime_result.returncode == 0 else "unknown"
    except Exception:
        uptime_str = "unknown"

    return {
        "version": config.FIRMWARE_VERSION,
        "platform": platform.machine(),
        "python": platform.python_version(),
        "uptime": uptime_str,
    }




# ═══════════════════════════════════════════════════════
# Relay Module — Pump + 3 Solenoid Valves
# ═══════════════════════════════════════════════════════
def setup_relays():
    """Initialize all relay pins to OFF (HIGH for active-low relay)."""
    if not _GPIO_AVAILABLE:
        return
    try:
        for pin in config.ALL_RELAY_PINS:
            GPIO.setup(pin, GPIO.OUT)
            GPIO.output(pin, GPIO.HIGH)  # OFF (active-low)
    except Exception as e:
        print(f"[WARN] Failed to initialize relays (are they connected?): {e}")


def set_relay(pin: int, state: bool):
    """
    Turn a relay ON (True) or OFF (False).
    Active-low: GPIO LOW = relay ON, GPIO HIGH = relay OFF.
    """
    if not _GPIO_AVAILABLE:
        print(f"[SIM] Relay pin {pin} -> {'ON' if state else 'OFF'}")
        return
    GPIO.output(pin, GPIO.LOW if state else GPIO.HIGH)


def activate_zone(zone: int):
    """Turn on the pump and the valve for the specified zone (1-3)."""
    valve_map = {1: config.RELAY_VALVE_1, 2: config.RELAY_VALVE_2, 3: config.RELAY_VALVE_3}
    if zone not in valve_map:
        print(f"[ERROR] Invalid zone: {zone}")
        return
    set_relay(config.RELAY_PUMP, True)
    set_relay(valve_map[zone], True)
    print(f"[RELAY] Zone {zone} ACTIVATED (Pump ON, Valve {zone} OPEN)")


def deactivate_all():
    """Emergency stop: turn off pump and all valves."""
    for pin in config.ALL_RELAY_PINS:
        set_relay(pin, False)
    print("[RELAY] ALL ZONES DEACTIVATED")


def cleanup():
    """Release GPIO resources on shutdown."""
    if _GPIO_AVAILABLE:
        deactivate_all()
        GPIO.cleanup()


# ═══════════════════════════════════════════════════════
# Class Wrapper for Object-Oriented Encapsulation
# ═══════════════════════════════════════════════════════

class SensorManager:
    """
    SensorManager object wrapper prioritizing encapsulation for main.py.
    Provides initialization logic for ADS1115 (A0, A1, A2) and DHT22 (GPIO 4)
    per architectural requirements, and proxies commands to the module-level functions.
    """
    def __init__(self):
        print("[INIT] Initializing SensorManager...")
        # Check and initialize ADS1115 via I2C SMBus
        if _SMBUS_AVAILABLE:
            try:
                # Early instantiation to ensure it's ready for polling
                self.i2c_bus = SMBus(config.ADS1115_I2C_BUS)
                print("[INIT] ADS1115 ADC initialized on I2C bus.")
            except Exception as e:
                print(f"[ERROR] Failed to initialize ADS1115: {e}")
                self.i2c_bus = None
        else:
            self.i2c_bus = None

        # Confirm BME280 configuration
        if _BME_AVAILABLE:
            print(f"[INIT] BME280 initialized on I2C (Address {hex(config.BME280_I2C_ADDRESS)}).")
        else:
            print("[WARN] BME280 hardware not found.")
            
        print("[INIT] SensorManager ready for polling.")

    def setup_relays(self):
        """Map relays to GPIO 17, 27, 22, 23 (Pump on 17, Zones on 27,22,23)."""
        setup_relays()

    def activate_zone(self, zone):
        activate_zone(zone)

    def deactivate_all(self):
        deactivate_all()

    def load_calibration(self):
        return load_calibration()

    def save_calibration(self):
        save_calibration()

    def run_calibration(self):
        return run_calibration()

    def run_dry_calibration(self, target_zone=None):
        return run_dry_calibration(target_zone=target_zone)

    def read_soil_moisture(self):
        # Reads A0, A1, A2 from ADS1115 and returns dict {"bed1": val...}
        return read_soil_moisture()

    def read_environment(self):
        # Reads Temp/Hum/Pres from BME280
        return read_environment()

    def read_tank_level(self):
        return read_tank_level()
        
    def cleanup(self):
        if hasattr(self, 'i2c_bus') and self.i2c_bus:
            try:
                self.i2c_bus.close()
            except Exception:
                pass
        cleanup()
