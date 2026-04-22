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
    import adafruit_bmp280
    _BME_AVAILABLE = True
    
    # Initialize I2C and the BMP280 sensor (Chip ID 0x58)
    _i2c = board.I2C()
    _bme_device = adafruit_bmp280.Adafruit_BMP280_I2C(_i2c, address=config.BMP280_I2C_ADDRESS)
    
except (ImportError, ValueError, RuntimeError, AttributeError) as e:
    _BME_AVAILABLE = False
    _bme_device = None
    print(f"[WARN] BMP280 init failed ({e}) — Temp/Pres will return mock data.")


# ═══════════════════════════════════════════════════════
# ADS1115 — 3-Channel Soil Moisture via I2C ADC
# ═══════════════════════════════════════════════════════
CALIBRATION_FILE = os.path.join(os.path.dirname(__file__), '..', 'storage', 'calibration_offsets.json')
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
        temp_file = CALIBRATION_FILE + '.tmp'
        try:
            # Write to a safe temporary file first
            with open(temp_file, 'w') as f:
                json.dump(_calibration_data, f, indent=4)
            # Instantly overwrite the real file (Atomic operation)
            os.replace(temp_file, CALIBRATION_FILE)
        except Exception as e:
            print(f"[ERROR] Failed to save calibration atomically: {e}")

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
        # No hardware detected — return fault sentinels so the UI shows FAULT, not 0%.
        print("[WARN] read_soil_moisture: SMBus not available — returning fault sentinels (-1.0).")
        fault_results = {"bed1": -1.0, "bed2": -1.0, "bed3": -1.0}
        return fault_results, fault_results, True

    try:
        cal_results = {}
        raw_results = {}
        with SMBus(config.ADS1115_I2C_BUS) as bus:  # Context manager guarantees fd release on any exception
            for ch in range(3):
                zone_key = f"zone_{ch+1}"
                dry_raw = cal_data[zone_key].get("dry_raw", config.SOIL_DRY)
                wet_raw = cal_data[zone_key].get("wet_raw", config.SOIL_WET)
                offset = cal_data[zone_key].get("manual_offset_pct", 0)

                raw = _read_ads1115_channel(bus, ch)

                # Fault detection for physically disconnected probes
                # A 3.3V sensor on a ±4.096V scale shouldn't read below 1000 or near 32767.
                if raw < 1000 or raw > 30000:
                    raw_results[f"bed{ch+1}"] = -1.0
                    cal_results[f"bed{ch+1}"] = -1.0
                    continue

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
        zones_to_test = [target_zone - 1] if target_zone in (1, 2, 3) else [0, 1, 2]
        with SMBus(config.ADS1115_I2C_BUS) as bus:  # Context manager guarantees fd release on any exception
            for ch in zones_to_test:
                readings = []
                for _ in range(10):
                    readings.append(_read_ads1115_channel(bus, ch))
                    time.sleep(0.02)
                avg_raw = int(sum(readings) / len(readings))

                zone_key = f"zone_{ch+1}"
                cal_data[zone_key]["dry_raw"] = avg_raw
                cal_data[zone_key]["manual_offset_pct"] = 0  # Reset manual offset on recalibration
                results["updates"][zone_key] = avg_raw
        save_calibration()
        return results
    except (IOError, OSError) as e:
        print(f"[ERROR] Dry calibration failed: {e}")
        return {"status": "error", "message": str(e)}



def run_wet_calibration(target_zone=None) -> dict:
    """
    Samples current sensor values while probes are submerged in water
    and sets them as the new 'wet' reference (100%).

    Takes 10 averaged readings per zone from the ADS1115 via the
    with SMBus(...) as bus: context manager to guarantee the file
    descriptor is released even on IOError, preventing [Errno 24] leaks.

    target_zone: 1, 2, 3 or None (calibrates all zones)
    Returns: {"status": "success", "updates": {"zone_1": <avg_raw>, ...}}
             or {"status": "error", "message": <str>} on failure.
    """
    cal_data = load_calibration()
    results = {"status": "success", "updates": {}}

    if not _SMBUS_AVAILABLE:
        print("[WARN] Wet calibration called but SMBus not available.")
        return {"status": "error", "message": "Simulation mode, hardware not available."}

    try:
        zones_to_test = [target_zone - 1] if target_zone in (1, 2, 3) else [0, 1, 2]
        with SMBus(config.ADS1115_I2C_BUS) as bus:  # Context manager guarantees fd release on any exception
            for ch in zones_to_test:
                readings = []
                for _ in range(10):
                    readings.append(_read_ads1115_channel(bus, ch))
                    time.sleep(0.02)
                avg_raw = int(sum(readings) / len(readings))

                zone_key = f"zone_{ch+1}"
                cal_data[zone_key]["wet_raw"] = avg_raw
                results["updates"][zone_key] = avg_raw
        save_calibration()
        print(f"[CAL] Wet calibration complete: {results['updates']}")
        return results
    except (IOError, OSError) as e:
        print(f"[ERROR] Wet calibration failed: {e}")
        return {"status": "error", "message": str(e)}



# ═══════════════════════════════════════════════════════
# BMP280 — Temperature & Pressure (NO humidity support)
# Chip ID: 0x58. Humidity is hardcoded to None because
# the BMP280 physically lacks a humidity sensor.
# ═══════════════════════════════════════════════════════
def read_environment() -> dict:
    """
    Returns {"temperature": float, "humidity": None, "pressure": float}.
    humidity is always None — BMP280 does not support humidity measurement.
    temperature and pressure return -1.0 on sensor fault or simulation.
    """
    if not _BME_AVAILABLE or not _bme_device:
        return {"temperature": -1.0, "humidity": None, "pressure": -1.0}

    try:
        return {
            "temperature": round(_bme_device.temperature, 1),
            "humidity": None,  # BMP280 has no humidity sensor (hardware mismatch resolved)
            "pressure": round(_bme_device.pressure, 1),
        }
    except Exception as e:
        print(f"[ERROR] BMP280 read failure: {e}")
        return {"temperature": -1.0, "humidity": None, "pressure": -1.0}


# ═══════════════════════════════════════════════════════
# XKC-Y26-V — Non-contact Tank Level (Digital, Active-High)
# Wiring: Black (Mode) → GND  |  Yellow (Signal) → GPIO BCM 6 (Pin 31)
# A physical pull-down resistor is wired on BCM 6 (hardware resistor).
# Software PUD is disabled (PUD_OFF) to avoid interfering with it.
#   GPIO HIGH (1) → sensor driving signal  → water detected → "FULL"
#   GPIO LOW  (0) → sensor idle / Unplugged → no water      → "LOW"
# ═══════════════════════════════════════════════════════

def read_tank_level() -> str:
    """
    Returns tank fill state: 'FULL', 'LOW', or 'FAULT'.

    Wiring — Active-High (Black/Mode on GND, Yellow/Signal via Voltage Divider to BCM 6):
      GPIO HIGH (1) = water detected = "FULL"
      GPIO LOW  (0) = no water / dry   = "LOW"
    
    Note: A physical pull-down resistor is wired on this pin — software PUD is
    disabled (PUD_OFF) so it does not interfere with the hardware resistor.
    Disconnected pin reads as 0 (LOW) = safe fail-state.
    """
    if not _GPIO_AVAILABLE:
        print("[WARN] read_tank_level: GPIO not available — returning FAULT sentinel.")
        return "FAULT"

    try:
        # ── Setup ──
        # PUD_OFF: physical resistor on BCM 6 handles biasing — no software pull needed.
        GPIO.setup(config.XKC_LEVEL_PIN, GPIO.IN, pull_up_down=GPIO.PUD_OFF)
        time.sleep(0.05)

        # ── Multi-sample anti-aliasing debounce ──
        # We take 11 samples over ~120ms. If the pin is truly floating 
        # (divider failing) or noisy, it will 'FAULT'.
        samples = []
        for _ in range(11):
            samples.append(GPIO.input(config.XKC_LEVEL_PIN))
            time.sleep(0.011)

        unique_states = set(samples)
        if len(unique_states) > 1:
            print(f"[WARN] Tank sensor signal unstable {samples} — returning FAULT.")
            return "FAULT"

        # Trust the solid state
        solid_state = samples[0]

        # ── Active-High mapping (Fail-Safe) ──
        # GPIO HIGH (1) → Sensor driving signal  → water present → "FULL"
        # GPIO LOW  (0) → Sensor idle / Unplugged → no water      → "LOW"
        if solid_state == GPIO.HIGH:
            return "FULL"
        else:
            return "LOW"

    except Exception as e:
        print(f"[ERROR] Tank level read failed: {e}")
        return "FAULT"


    except Exception as e:
        print(f"[ERROR] Tank level read failed: {e}")
        return "FAULT"






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
            with SMBus(config.ADS1115_I2C_BUS) as bus:  # Context manager guarantees fd release on any exception
                for ch in range(3):
                    readings = []
                    for _ in range(10):
                        readings.append(_read_ads1115_channel(bus, ch))
                        time.sleep(0.02)
                    avg = sum(readings) / len(readings)
                    results["soil_raw"].append(round(avg, 1))
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


def deactivate_zone(zone: int):
    """
    Close the solenoid valve for the specified zone (1-3) only.
    Does NOT affect the main pump or any other active zones.
    Call deactivate_all() for a full emergency stop.
    """
    valve_map = {1: config.RELAY_VALVE_1, 2: config.RELAY_VALVE_2, 3: config.RELAY_VALVE_3}
    if zone not in valve_map:
        print(f"[ERROR] deactivate_zone: Invalid zone: {zone}")
        return
    set_relay(valve_map[zone], False)  # Close valve only
    print(f"[RELAY] Zone {zone} valve CLOSED (pump state unchanged)")


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
    Provides initialization logic for ADS1115 (A0, A1, A2) and BMP280 (I2C)
    per architectural requirements, and proxies commands to the module-level functions.
    NOTE: Physical sensor confirmed as BMP280 (Chip ID 0x58). Humidity unsupported.
    """
    def __init__(self):
        print("[INIT] Initializing SensorManager...")
        # Verify the ADS1115 is reachable on the I2C bus at startup.
        # A short-lived probe is used intentionally — the context manager ensures
        # the fd is released immediately after the check, preventing a persistent
        # leak. All subsequent reads open their own short-lived bus handles.
        if _SMBUS_AVAILABLE:
            try:
                with SMBus(config.ADS1115_I2C_BUS) as probe_bus:
                    # Attempt a dummy read to confirm the device is present
                    probe_bus.read_byte(config.ADS1115_I2C_ADDRESS)
                print("[INIT] ADS1115 ADC verified on I2C bus.")
            except Exception as e:
                print(f"[WARN] ADS1115 not detected at startup: {e}")
        
        # Confirm BMP280 configuration (humidity NOT available on this chip)
        if _BME_AVAILABLE:
            print(f"[INIT] BMP280 initialized on I2C (Address {hex(config.BMP280_I2C_ADDRESS)}). [Temp+Pressure only]")
        else:
            print("[WARN] BMP280 hardware not found.")
            
        print("[INIT] SensorManager ready for polling.")

    def setup_relays(self):
        """Map relays to GPIO 17, 27, 22, 23 (Pump on 17, Zones on 27,22,23)."""
        setup_relays()

    def activate_zone(self, zone: int):
        activate_zone(zone)

    def deactivate_zone(self, zone: int):
        """Close only the specified zone's valve — does not stop the pump."""
        deactivate_zone(zone)

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

    def run_wet_calibration(self, target_zone=None):
        """Captures saturated-soil (wet) reference values for the given zone (or all zones)."""
        return run_wet_calibration(target_zone=target_zone)

    def read_soil_moisture(self):
        # Reads A0, A1, A2 from ADS1115 and returns dict {"bed1": val...}
        return read_soil_moisture()

    def read_environment(self):
        # Reads Temp/Pressure from BMP280. humidity is always None (BMP280 has no humidity sensor).
        return read_environment()

    def read_tank_level(self):
        return read_tank_level()
        
    def cleanup(self):
        # No persistent i2c_bus fd to close — all handles are short-lived context managers.
        cleanup()
