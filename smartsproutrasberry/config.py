"""
Smart Sprout — GPIO & Pin Configuration
Centralizes all hardware pin assignments from the .env file.
"""
import os
from dotenv import load_dotenv

load_dotenv()

# ── I2C (ADS1115 ADC) ──
ADS1115_I2C_BUS = int(os.getenv("ADS1115_I2C_BUS", "1"))
ADS1115_I2C_ADDRESS = int(os.getenv("ADS1115_I2C_ADDRESS", "0x48"), 16)

# ── Digital Sensors ──
DHT22_PIN = int(os.getenv("DHT22_GPIO_PIN", "4"))
ULTRASONIC_TRIGGER = int(os.getenv("ULTRASONIC_TRIGGER_PIN", "5"))
ULTRASONIC_ECHO = int(os.getenv("ULTRASONIC_ECHO_PIN", "6"))
FLOW_SENSOR = int(os.getenv("FLOW_SENSOR_PIN", "13"))

# ── Relay Module (Active LOW) ──
RELAY_PUMP = int(os.getenv("RELAY_PUMP_PIN", "17"))
RELAY_VALVE_1 = int(os.getenv("RELAY_VALVE1_PIN", "27"))
RELAY_VALVE_2 = int(os.getenv("RELAY_VALVE2_PIN", "22"))
RELAY_VALVE_3 = int(os.getenv("RELAY_VALVE3_PIN", "23"))

ALL_RELAY_PINS = [RELAY_PUMP, RELAY_VALVE_1, RELAY_VALVE_2, RELAY_VALVE_3]

# ── Calibration ──
SOIL_DRY = int(os.getenv("SOIL_SENSOR_DRY", "26000"))
SOIL_WET = int(os.getenv("SOIL_SENSOR_WET", "13000"))

TANK_HEIGHT_CM = float(os.getenv("TANK_HEIGHT_CM", "40"))
TANK_EMPTY_DISTANCE = float(os.getenv("TANK_EMPTY_DISTANCE_CM", "40"))
TANK_FULL_DISTANCE = float(os.getenv("TANK_FULL_DISTANCE_CM", "5"))

FLOW_CALIBRATION = float(os.getenv("FLOW_CALIBRATION_FACTOR", "7.5"))


# ── Safety ──
TANK_LOW_THRESHOLD = int(os.getenv("TANK_LOW_THRESHOLD", "10"))
# ── MQTT ──
MQTT_HOST = os.getenv("MQTT_BROKER_HOST", "localhost")
MQTT_PORT = int(os.getenv("MQTT_BROKER_PORT", "1883"))

# ── Timing ──
TELEMETRY_INTERVAL = int(os.getenv("TELEMETRY_INTERVAL", "3"))
CLOUD_SYNC_INTERVAL = int(os.getenv("CLOUD_SYNC_INTERVAL", "1800"))

# ── System Info ──
FIRMWARE_VERSION = os.getenv("FIRMWARE_VERSION", "1.0.4")
