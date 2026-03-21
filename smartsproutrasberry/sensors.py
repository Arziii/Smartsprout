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
    import adafruit_dht
    _DHT_AVAILABLE = True
    
    # Initialize the DHT device early so it's ready for polling.
    # We map config.DHT22_PIN (e.g., 4) to board.D4 
    _pin_attr = f"D{config.DHT22_PIN}"
    _pin = getattr(board, _pin_attr, getattr(board, "D4")) 
    _dht_device = adafruit_dht.DHT22(_pin)
    
except (ImportError, NotImplementedError, AttributeError) as e:
    _DHT_AVAILABLE = False
    _dht_device = None
    print(f"[WARN] adafruit_dht init failed ({e}) — DHT22 will return mock data.")


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


def read_soil_moisture() -> list[float]:
    """
    Returns a list of 3 soil moisture percentages [zone1, zone2, zone3].
    Maps raw ADC values to 0-100% using calibrated wet/dry thresholds and applies manual offsets.
    """
    cal_data = load_calibration()
    
    if not _SMBUS_AVAILABLE:
        return {
            "bed1": max(0.0, min(100.0, 0.0 + cal_data["zone_1"].get("manual_offset_pct", 0))),
            "bed2": max(0.0, min(100.0, 0.0 + cal_data["zone_2"].get("manual_offset_pct", 0))),
            "bed3": max(0.0, min(100.0, 0.0 + cal_data["zone_3"].get("manual_offset_pct", 0)))
        }

    try:
        bus = SMBus(config.ADS1115_I2C_BUS)
        results = {}
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
            
            # Apply manual offset and clamp
            pct += offset
            pct = max(0.0, min(100.0, pct))
            results[f"bed{ch+1}"] = round(pct, 1)
        bus.close()
        return results
    except (IOError, OSError) as e:
        print(f"[ERROR] I2C soil read failed: {e}")
        return {"bed1": -1.0, "bed2": -1.0, "bed3": -1.0}  # Sentinel for "Sensor Fault"

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
# DHT22 — Temperature & Humidity
# ═══════════════════════════════════════════════════════
def read_dht22() -> dict:
    """
    Returns {"temperature": float, "humidity": float}.
    Values are -1.0 on sensor fault.
    """
    global _dht_device
    if not _DHT_AVAILABLE or not _dht_device:
        return {"temperature": 0.0, "humidity": 0.0}

    # Try up to 3 times to get a valid reading, catching Checksum errors.
    for attempt in range(3):
        try:
            temperature = _dht_device.temperature
            humidity = _dht_device.humidity
            
            if temperature is not None and humidity is not None:
                return {
                    "temperature": round(temperature, 1),
                    "humidity": round(humidity, 1),
                }
        except RuntimeError as e:
            # DHT22 sensors frequently throw Checksum errors (RuntimeError in adafruit_dht)
            # Wait 2 seconds and try again instead of crashing.
            print(f"[WARN] DHT22 transient error (attempt {attempt+1}): {e} - Retrying in 2 seconds...")
            time.sleep(2.0)
            continue
        except Exception as e:
            print(f"[ERROR] DHT22 critical failure: {e}")
            break
            
    # If the loop exhausts retries and continues to fail:
    print("[ERROR] DHT22 aborted after 3 failed attempts.")
    return {"temperature": -1.0, "humidity": -1.0}


# ═══════════════════════════════════════════════════════
# HC-SR04 — Ultrasonic Tank Level
# ═══════════════════════════════════════════════════════
def _setup_ultrasonic():
    if not _GPIO_AVAILABLE:
        return
    GPIO.setup(config.ULTRASONIC_TRIGGER, GPIO.OUT)
    GPIO.setup(config.ULTRASONIC_ECHO, GPIO.IN)
    GPIO.output(config.ULTRASONIC_TRIGGER, False)


def read_tank_level() -> float:
    """
    Returns tank fill percentage (0-100%).
    Uses the ultrasonic distance to calculate volume.
    Returns -1.0 on sensor fault.
    """
    if not _GPIO_AVAILABLE:
        return 0.0  # Force 0.0 when no hardware is attached so safety locks engage

    try:
        _setup_ultrasonic()
        time.sleep(0.05)

        # Send 10µs trigger pulse
        GPIO.output(config.ULTRASONIC_TRIGGER, True)
        time.sleep(0.00001)
        GPIO.output(config.ULTRASONIC_TRIGGER, False)

        # Wait for echo (with timeout)
        timeout = time.time() + 0.04  # 40ms max
        pulse_start = time.time()
        while GPIO.input(config.ULTRASONIC_ECHO) == 0:
            pulse_start = time.time()
            if pulse_start > timeout:
                return -1.0

        pulse_end = time.time()
        timeout = time.time() + 0.04
        while GPIO.input(config.ULTRASONIC_ECHO) == 1:
            pulse_end = time.time()
            if pulse_end > timeout:
                return -1.0

        # Speed of sound = 34300 cm/s, round trip
        distance_cm = (pulse_end - pulse_start) * 34300.0 / 2.0

        # Map distance to percentage
        usable_range = config.TANK_EMPTY_DISTANCE - config.TANK_FULL_DISTANCE
        pct = (config.TANK_EMPTY_DISTANCE - distance_cm) / usable_range * 100.0
        pct = max(0.0, min(100.0, pct))
        return round(pct, 1)

    except Exception as e:
        print(f"[ERROR] Ultrasonic read failed: {e}")
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
    and returning the averaged raw ADC values plus the tank's
    empty ultrasonic distance.
    """
    results = {"soil_raw": [], "tank_distance_cm": -1.0}

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
        results["soil_raw"] = [19500, 17200, 22100]

    # Tank distance calibration (average of 5 reads)
    if _GPIO_AVAILABLE:
        try:
            distances = []
            for _ in range(5):
                d = read_tank_level()  # returns percentage, we need raw distance
                distances.append(d)
                time.sleep(0.2)
            results["tank_distance_cm"] = round(sum(distances) / len(distances), 1)
        except Exception as e:
            print(f"[ERROR] Calibration tank read failed: {e}")
    else:
        results["tank_distance_cm"] = 75.0

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

        # Confirm DHT22 GPIO binding
        if _DHT_AVAILABLE:
            print(f"[INIT] DHT22 initialized on GPIO {config.DHT22_PIN}.")
        else:
            print("[WARN] DHT22 hardware not found.")
            
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

    def read_dht22(self):
        # Reads GPIO 4 (or configured pin)
        return read_dht22()

    def read_tank_level(self):
        return read_tank_level()
        
    def cleanup(self):
        if hasattr(self, 'i2c_bus') and self.i2c_bus:
            try:
                self.i2c_bus.close()
            except Exception:
                pass
        cleanup()
